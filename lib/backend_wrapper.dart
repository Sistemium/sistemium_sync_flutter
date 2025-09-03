import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, compute;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:objectid/objectid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistemium_sync_flutter/sync_abstract.dart';
import 'package:sistemium_sync_flutter/sync_logger.dart';
import 'package:sqlite_async/sqlite3.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

// Queue item for sync operations
class SyncQueueItem {
  final String method;
  final Map<String, dynamic> arguments;

  SyncQueueItem({
    required this.method,
    this.arguments = const {},
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncQueueItem &&
          runtimeType == other.runtimeType &&
          method == other.method &&
          const DeepCollectionEquality().equals(arguments, other.arguments);

  @override
  int get hashCode => method.hashCode ^ const DeepCollectionEquality().hash(arguments);
}

class BackendNotifier extends ChangeNotifier {
  final AbstractPregeneratedMigrations abstractPregeneratedMigrations;
  final AbstractSyncConstants abstractSyncConstants;
  final AbstractMetaEntity abstractMetaEntity;

  SqliteDatabase? _db;
  bool _sseConnected = false;
  StreamSubscription? _eventSubscription;
  String? _serverUrl;
  String? userId;
  String? _authToken;

  final Map<String, Timer?> _retryTimers = {};

  // Sync queue system
  final List<SyncQueueItem> _syncQueue = [];
  final ValueNotifier<bool> isProcessingQueue = ValueNotifier<bool>(false);

  BackendNotifier({
    required this.abstractPregeneratedMigrations,
    required this.abstractSyncConstants,
    required this.abstractMetaEntity,
  });

  SqliteDatabase? get db => _db;

  // Single helper for JSON parsing in isolate
  static Map<String, dynamic> _parseJsonInIsolate(String body) {
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<void> initDb({
    String? serverUrl,
    required String userId,
    String? authToken,
  }) async {
    _serverUrl = serverUrl ?? abstractSyncConstants.serverUrl;
    this.userId = userId;
    _authToken = authToken;
    final tempDb = await _openDatabase();
    await abstractPregeneratedMigrations.migrations.migrate(tempDb);

    // Ensure system tables are registered in syncing_table before exposing DB
    await _ensureTableRegistration(tempDb, 'RulesBoard');
    await _ensureTableRegistration(tempDb, 'Archive');

    _db = tempDb;
    _startSyncer();
    notifyListeners();
  }

  Future<void> deinitDb() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _sseConnected = false;

    // Cancel all retry timers
    for (var timer in _retryTimers.values) {
      timer?.cancel();
    }
    _retryTimers.clear();

    if (_db != null) await _db!.close();
    _db = null;
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // System tables syncing_table registration
  // -----------------------------------------------------------------------

  Future<void> _ensureTableRegistration(SqliteDatabase db, String tableName) async {
    try {
      final existing = await db.getAll(
        'SELECT 1 FROM syncing_table WHERE entity_name = ? LIMIT 1',
        [tableName],
      );
      if (existing.isNotEmpty) {
        return;
      }

      final result = await _requestLatestTableTs(tableName);
      
      // If server request failed (network error, auth error, etc), schedule retry
      if (result.hasError) {
        SyncLogger.log('Failed to get $tableName timestamp from server: ${result.error}', error: result.error);
        _scheduleTableRetry(db, tableName);
        return;
      }

      // Server responded successfully - register with the timestamp (which can be null for empty collections)
      await db.execute(
        'INSERT INTO syncing_table (_id, entity_name, last_received_ts) VALUES (?, ?, ?)',
        [ObjectId().hexString, tableName, result.timestamp],
      );
      SyncLogger.log('Successfully registered $tableName with ts: ${result.timestamp}');
    } catch (e, st) {
      SyncLogger.log('Error ensuring $tableName registration: $e', error: e, stackTrace: st);
      _scheduleTableRetry(db, tableName);
    }
  }


  Future<_TimestampResult> _requestLatestTableTs(String tableName) async {
    if (_serverUrl == null) {
      return _TimestampResult(hasError: true, error: 'Server URL not configured');
    }
    
    try {
      final uri = Uri.parse('$_serverUrl/latest-ts').replace(queryParameters: {'name': tableName});
      final headers = {'appid': abstractSyncConstants.appId};
      if (_authToken != null) {
        headers['authorization'] = _authToken!;
      }

      final res = await http.get(uri, headers: headers);
      
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        // Successfully got response - timestamp can be null if collection is empty
        return _TimestampResult(
          hasError: false,
          timestamp: body['ts'] as String?,
        );
      } else {
        // Server responded with error status
        return _TimestampResult(
          hasError: true,
          error: 'Server returned status ${res.statusCode}',
        );
      }
    } catch (e) {
      // Network or other error
      return _TimestampResult(
        hasError: true,
        error: e.toString(),
      );
    }
  }

  void _scheduleTableRetry(SqliteDatabase db, String tableName) {
    _retryTimers[tableName]?.cancel();
    _retryTimers[tableName] = Timer(const Duration(seconds: 30), () async {
      await _ensureTableRegistration(db, tableName);
    });
  }

  Stream<List> watch({
    required String sql,
    required List<String> triggerOnTables,
  }) {
    return _db!.watch(sql, triggerOnTables: triggerOnTables);
  }

  Future<ResultSet> getAll({required String sql}) {
    return _db!.getAll(sql);
  }

  Future<void> write({
    required String tableName,
    required Map data,
    SqliteWriteContext? tx,
  }) async {
    final db = tx ?? _db;
    if (data['_id'] == null) data['_id'] = ObjectId().hexString;
    final columns = data.keys.toList();
    final values = data.values.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    final updatePlaceholders = columns.map((c) => '$c = ?').join(', ');
    final sql =
        '''
      INSERT INTO $tableName (${columns.join(', ')}, is_unsynced)
      VALUES ($placeholders, 1)
      ON CONFLICT(_id) DO UPDATE SET $updatePlaceholders, is_unsynced = 1
    ''';
    await db!.execute(sql, [...values, ...values]);
    if (tx == null) {
      _addToSyncQueue(SyncQueueItem(method: 'sendUnsynced', arguments: {'tableName': tableName}));
    }
  }

  Future<T> writeTransaction<T>({
    required List<String> affectedTables,
    required Future<T> Function(SqliteWriteContext tx) callback,
  }) async {
    if (_db == null) throw Exception('Database not initialized');
    final result = await _db!.writeTransaction(callback);
    
    // Queue sync for each affected table
    for (final tableName in affectedTables) {
      _addToSyncQueue(SyncQueueItem(method: 'sendUnsynced', arguments: {'tableName': tableName}));
    }
    
    return result;
  }

  Future<void> delete({required String tableName, required String id}) async {
    await _db!.writeTransaction((tx) async {
      // First get the document data before deleting
      final docs = await tx.getAll('SELECT * FROM $tableName WHERE _id = ?', [
        id,
      ]);

      if (docs.isEmpty) {
        throw Exception('Document not found for deletion: $id in $tableName');
      }

      final docData = docs.first;

      // Delete the original document
      await tx.execute('DELETE FROM $tableName WHERE _id = ?', [id]);

      // Create Archive entry
      await tx.execute(
        'INSERT INTO Archive (_id, id, name, data, is_unsynced) VALUES (?, ?, ?, ?, 1)',
        [
          ObjectId().hexString, // New Archive _id
          id, // Original document's _id goes in id field
          tableName, // Entity name goes in name field
          jsonEncode(docData), // Complete document data as JSON
        ],
      );
    });

    // Only need to sync Archive table since it has the new unsynced entry
    _addToSyncQueue(SyncQueueItem(method: 'sendUnsynced', arguments: {'tableName': 'Archive'}));
  }

  Future<SqliteDatabase> _openDatabase() async {
    final path = await _getDatabasePath('$userId/sync.db');
    return SqliteDatabase(
      path: path,
      options: SqliteOptions(
        webSqliteOptions: WebSqliteOptions(
          wasmUri: 'sqlite3.wasm',
          workerUri: 'db_worker.js',
        ),
      ),
    );
  }

  Future<String> _getDatabasePath(String name) async {
    String base = '';
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      base = dir.path;
    }
    final full = p.join(base, name);
    final dir = Directory(p.dirname(full));
    if (!await dir.exists()) await dir.create(recursive: true);
    return full;
  }

  Future<void> _fetchData({
    required String name,
    String? lastReceivedTs,
    required int pageSize,
    required Future<void> Function(Map<String, dynamic>) onData,
  }) async {
    final q = {'name': name, 'pageSize': pageSize.toString()};
    if (lastReceivedTs != null) q['ts'] = lastReceivedTs;
    final uri = Uri.parse('$_serverUrl/data').replace(queryParameters: q);
    final headers = {'appid': abstractSyncConstants.appId};
    if (_authToken != null) {
      headers['authorization'] = _authToken!;
    }

    final res = await http.get(uri, headers: headers);
    if (res.statusCode == 200) {
      final data = await compute(_parseJsonInIsolate, res.body);
      await onData(data);
    } else {
      throw Exception('Failed to fetch data');
    }
  }

  // Queue management methods
  void _addToSyncQueue(SyncQueueItem item) {
    // Check if identical item already exists in queue
    if (_syncQueue.contains(item)) {
      SyncLogger.log('Sync operation already in queue: ${item.method}');
      return;
    }
    
    _syncQueue.add(item);
    SyncLogger.log('Added to sync queue: ${item.method}');
    
    // Start processing if not already running
    if (!isProcessingQueue.value) {
      _processQueue();
    }
  }

  Future<void> _processQueue() async {
    if (isProcessingQueue.value || _db == null) return;
    
    isProcessingQueue.value = true;
    
    while (_syncQueue.isNotEmpty && _db != null) {
      final item = _syncQueue.removeAt(0);
      SyncLogger.log('Processing queue item: ${item.method}');
      
      try {
        if (item.method == 'fullSync') {
          await fullSync();
        } else if (item.method == 'syncTable') {
          final tableName = item.arguments['tableName'] as String;
          await syncTable(tableName);
        } else if (item.method == 'sendUnsynced') {
          final tableName = item.arguments['tableName'] as String;
          await _sendUnsyncedForTable(tableName);
        }
        // Add more methods here as needed
        
      } catch (e, stackTrace) {
        SyncLogger.log('Error processing queue item ${item.method}: $e', 
          error: e, stackTrace: stackTrace);
      }
    }
    
    isProcessingQueue.value = false;
    SyncLogger.log('Queue processing complete');
  }

  Future<void> syncTable(String tableName) async {
    SyncLogger.log('Starting sync for table: $tableName');
    
    // First send any unsynced data for this table
    bool sendSuccess = false;
    int retryCount = 0;
    while (!sendSuccess && retryCount < 3) {
      sendSuccess = await _sendUnsyncedForTable(tableName);
      if (!sendSuccess) {
        retryCount++;
        SyncLogger.log('Retry $retryCount for sending unsynced data for $tableName');
      }
    }
    
    if (!sendSuccess) {
      SyncLogger.log('Failed to send unsynced data for $tableName after retries');
      return;
    }
    
    // Get the last received timestamp for this table
    final syncingInfo = await _db!.getAll(
      'SELECT * FROM syncing_table WHERE entity_name = ?',
      [tableName]
    );
    
    if (syncingInfo.isEmpty) {
      SyncLogger.log('Table $tableName not found in syncing_table');
      return;
    }
    
    final table = syncingInfo.first;
    int page = 10000;
    bool more = true;
    String? ts = table['last_received_ts']?.toString() ?? '';
    
    SyncLogger.log('Initial TS for $tableName: $ts');
    
    while (more && _db != null) {
      SyncLogger.log('Fetching $tableName with ts: $ts, page: $page');
      await _fetchData(
        name: tableName,
        lastReceivedTs: ts,
        pageSize: page,
        onData: (resp) async {
          SyncLogger.log('Got response for $tableName, starting transaction');
          await _db!.writeTransaction((tx) async {
            // Check for new unsynced data that appeared during fetch
            SyncLogger.log('Checking unsynced in $tableName');
            final unsynced = await tx.getAll(
              'select * from $tableName where is_unsynced = 1',
            );
            SyncLogger.log('Unsynced check complete for $tableName: ${unsynced.length} records');
            
            if (unsynced.isNotEmpty) {
              SyncLogger.log('Found ${unsynced.length} unsynced records in $tableName');
              SyncLogger.log('First unsynced: ${unsynced.first}');
              more = false;
              // Add table sync back to queue to handle the new unsynced data
              _addToSyncQueue(SyncQueueItem(method: 'syncTable', arguments: {'tableName': tableName}));
              return;
            }
            
            SyncLogger.log('Syncing $tableName');
            SyncLogger.log('Last received TS: $ts');
            SyncLogger.log('Received ${resp['data']?.length ?? 0} rows');
            
            if ((resp['data']?.length ?? 0) == 0) {
              more = false;
              return;
            }
            
            final pk = '_id';
            final cols = abstractMetaEntity.syncableColumnsList[tableName]!;
            final placeholders = List.filled(cols.length, '?').join(', ');
            final updates = cols
                .where((c) => c != pk)
                .map((c) => '$c = excluded.$c')
                .join(', ');
            final sql = '''
INSERT INTO $tableName (${cols.join(', ')}) VALUES ($placeholders)
ON CONFLICT($pk) DO UPDATE SET $updates;
''';
            final data = List<Map<String, dynamic>>.from(resp['data']);
            SyncLogger.log('Last ts in response: ${data.last['ts']}');
            
            final batch = data
                .map<List<Object?>>(
                  (e) => cols.map<Object?>((c) => e[c]).toList(),
                )
                .toList();
            await tx.executeBatch(sql, batch);
            
            await tx.execute(
              'UPDATE syncing_table SET last_received_ts = ? WHERE entity_name = ?',
              [data.last['ts'], tableName],
            );
            
            if (data.length < page) {
              more = false;
            } else {
              ts = data.last['ts'];
            }
          });
        },
      );
      SyncLogger.log('Fetch complete for $tableName, more: $more');
    }
    
    // Process special tables after sync
    if (tableName == 'Archive') {
      SyncLogger.log('Processing Archive entries');
      await _processArchive();
    } else if (tableName == 'RulesBoard') {
      SyncLogger.log('Processing RulesBoard entries');
      await _processRulesBoard();
    }
    
    SyncLogger.log('Table $tableName sync complete');
  }

  Future<void> fullSync() async {
    SyncLogger.log('Starting full sync cycle');
    
    try {
      final tables = await _db!.getAll('select * from syncing_table');
      SyncLogger.log('Found ${tables.length} tables to sync');
      SyncLogger.log('Tables: ${tables.map((t) => t['entity_name']).join(', ')}');
      
      // Sync each table (including Archive and RulesBoard which will be processed internally)
      for (var table in tables) {
        await syncTable(table['entity_name']);
      }
      
      SyncLogger.log('End of sync cycle');
    } catch (e, stackTrace) {
      SyncLogger.log('Error during full sync: $e', error: e, stackTrace: stackTrace);
    }
    
    SyncLogger.log('Full sync complete');
  }

  // -----------------------------------------------------------------------
  // Archive handling
  // -----------------------------------------------------------------------

  Future<void> _processArchive() async {
    // Ensure DB is available
    final dbLocal = _db;
    if (dbLocal == null) return;

    SyncLogger.log('Starting Archive processing...');

    await dbLocal.writeTransaction((tx) async {
      // Only process synced Archive entries (is_unsynced = 0 or NULL)
      // Unsynced entries should remain in the table for later sync
      final archiveEntries = await tx.getAll(
        'SELECT * FROM Archive WHERE is_unsynced = 0 OR is_unsynced IS NULL ORDER BY ts ASC',
      );
      
      if (kDebugMode) {
        SyncLogger.log('Found ${archiveEntries.length} synced Archive entries to process');
      }
      
      if (archiveEntries.isEmpty) return; // nothing to process

      // Process each synced Archive entry
      for (var entry in archiveEntries) {
        if (kDebugMode) {
          SyncLogger.log('Processing Archive entry: ${entry['_id']}');
        }

        final entityName = entry['name'];
        final entityId = entry['id'];

        if (entityName == null || entityId == null) {
          if (kDebugMode) {
            SyncLogger.log('Skipping malformed entry: missing name or id');
          }
          continue;
        }

        // Check if the table exists in syncing_table
        final tableExists = await tx.getAll(
          'SELECT 1 FROM syncing_table WHERE entity_name = ? LIMIT 1',
          [entityName],
        );

        if (tableExists.isEmpty) {
          if (kDebugMode) {
            SyncLogger.log('Skipping delete for $entityName - table not in syncing_table');
          }
          continue;
        }

        if (kDebugMode) {
          SyncLogger.log('Deleting $entityId from $entityName');
        }

        // Delete the referenced document if it exists
        await tx.execute('DELETE FROM "$entityName" WHERE _id = ?', [entityId]);
      }

      // After processing, delete only the synced Archive entries
      if (archiveEntries.isNotEmpty) {
        if (kDebugMode) {
          SyncLogger.log('Clearing processed (synced) Archive entries');
        }
        await tx.execute('DELETE FROM Archive WHERE is_unsynced = 0 OR is_unsynced IS NULL');
      }
    });

    if (kDebugMode) {
      SyncLogger.log('Archive processing complete');
    }
  }

  // -----------------------------------------------------------------------
  // RulesBoard handling
  // -----------------------------------------------------------------------

  Future<void> _processRulesBoard() async {
    // Ensure DB is available
    final dbLocal = _db;
    if (dbLocal == null) return;

    SyncLogger.log('Starting processing...');

    // Step 3: Check if shadow syncing_table exists (indicates resuming)
    final shadowSyncingExists = await dbLocal.getAll(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='syncing_table_shadow'",
    );

    if (shadowSyncingExists.isNotEmpty) {
      SyncLogger.log('Found existing shadow tables, resuming resync...');
      // Jump to step 6 - process shadow syncing table
      await _processShadowSync(dbLocal);
      return;
    }

    // Fetch RulesBoard entries to process
    final rulesEntries = await dbLocal.getAll(
      'SELECT * FROM RulesBoard ORDER BY ts ASC',
    );

    if (rulesEntries.isEmpty) {
      SyncLogger.log('No entries to process.');
      return;
    }

    // Process each RulesBoard entry
    for (final entry in rulesEntries) {
      await _processRulesBoardEntry(dbLocal, entry);
    }
  }

  Future<void> _processRulesBoardEntry(SqliteDatabase db, Map<String, dynamic> entry) async {
    SyncLogger.log('Processing entry: $entry');

    final jsonStr = entry['fullResyncCollections'];
    if (jsonStr == null) return;

    List<String> tablesToResync;
    try {
      final decoded = jsonDecode(jsonStr);
      tablesToResync = (decoded as List).whereType<String>().toList();
    } catch (_) {
      SyncLogger.log('Failed to parse fullResyncCollections');
      return;
    }

    // Filter out system tables
    tablesToResync = tablesToResync.where((tbl) => 
      tbl != 'RulesBoard' && tbl != 'Archive' && tbl != 'syncing_table'
    ).toList();

    if (tablesToResync.isEmpty) {
      SyncLogger.log('No user tables to resync');
      return;
    }

    // Step 4: Create shadow tables
    await db.writeTransaction((tx) async {
      // Create shadow syncing_table
      await tx.execute('''
        CREATE TABLE IF NOT EXISTS syncing_table_shadow (
          _id TEXT PRIMARY KEY,
          entity_name TEXT UNIQUE,
          last_received_ts TEXT
        )
      ''');

      // Copy relevant entries from syncing_table to shadow with NULL timestamps
      for (final table in tablesToResync) {
        final syncingEntry = await tx.getAll(
          'SELECT * FROM syncing_table WHERE entity_name = ?',
          [table],
        );
        
        if (syncingEntry.isNotEmpty) {
          await tx.execute(
            'INSERT OR REPLACE INTO syncing_table_shadow (_id, entity_name, last_received_ts) VALUES (?, ?, NULL)',
            [syncingEntry[0]['_id'], table],
          );

          // Create shadow table for entity with proper structure
          // First get the table structure
          final tableInfo = await tx.getAll('PRAGMA table_info("$table")');
          final columns = tableInfo.map((col) {
            final name = col['name'];
            final type = col['type'];
            final notNull = col['notnull'] == 1 ? 'NOT NULL' : '';
            final pk = col['pk'] == 1 ? 'PRIMARY KEY' : '';
            return '"$name" $type $notNull $pk';
          }).join(', ');
          
          await tx.execute('DROP TABLE IF EXISTS "${table}_shadow"');
          await tx.execute('CREATE TABLE "${table}_shadow" ($columns)');
        }
      }

      // Step 5: Delete the RulesBoard entry we're processing
      await tx.execute('DELETE FROM RulesBoard WHERE _id = ?', [entry['_id']]);
    });

    // Step 6: Process shadow sync
    await _processShadowSync(db);
  }

  Future<void> _processShadowSync(SqliteDatabase db) async {
    if (kDebugMode) {
      SyncLogger.log('Processing shadow sync...');
    }

    // Get tables to sync from shadow syncing_table
    final shadowTables = await db.getAll('SELECT * FROM syncing_table_shadow');

    for (final shadowEntry in shadowTables) {
      final tableName = shadowEntry['entity_name'] as String;
      final lastTs = shadowEntry['last_received_ts'] as String?;

      if (kDebugMode) {
        SyncLogger.log('Syncing shadow table: $tableName from ts: $lastTs');
      }

      // Download data into shadow table using existing sync logic
      await _syncTableIntoShadow(db, tableName, lastTs);
    }

    // Step 7: Compare and clean up
    await _compareAndCleanup(db, shadowTables);
  }

  Future<void> _syncTableIntoShadow(SqliteDatabase db, String tableName, String? initialTs) async {
    int pageSize = 1000;
    bool hasMore = true;
    String? currentTs = initialTs ?? '';  // Convert null to empty string like normal sync does

    if (kDebugMode) {
      SyncLogger.log('Starting shadow sync for $tableName with initialTs: $initialTs (using: $currentTs)');
    }

    while (hasMore && _db != null) {
      try {
        await _fetchData(
          name: tableName,
          lastReceivedTs: currentTs,
          pageSize: pageSize,
          onData: (resp) async {
            await db.writeTransaction((tx) async {
              final data = List<Map<String, dynamic>>.from(resp['data'] ?? []);
              
              if (kDebugMode) {
                SyncLogger.log('Shadow sync $tableName: received ${data.length} records');
              }
              
              if (data.isEmpty) {
                hasMore = false;
                return;
              }

              // Get column info
              final cols = abstractMetaEntity.syncableColumnsList[tableName]!;
              final pk = '_id';
              final placeholders = List.filled(cols.length, '?').join(', ');
              final updates = cols
                  .where((c) => c != pk)
                  .map((c) => '$c = excluded.$c')
                  .join(', ');

              // Insert data into shadow table
              final sql = '''
INSERT INTO "${tableName}_shadow" (${cols.join(', ')}) VALUES ($placeholders)
ON CONFLICT($pk) DO UPDATE SET $updates;
''';
              
              final batch = data
                  .map<List<Object?>>(
                    (e) => cols.map<Object?>((c) => e[c]).toList(),
                  )
                  .toList();
              
              await tx.executeBatch(sql, batch);

              // Update progress with last timestamp
              if (data.isNotEmpty) {
                currentTs = data.last['ts']?.toString();
                await tx.execute(
                  'UPDATE syncing_table_shadow SET last_received_ts = ? WHERE entity_name = ?',
                  [currentTs, tableName],
                );
              }

              // Check if we need to continue
              hasMore = data.length >= pageSize;
            });
          },
        );

        if (!hasMore) break;
      } catch (e) {
        if (kDebugMode) {
          SyncLogger.log('Error syncing shadow table $tableName: $e', error: e);
        }
        rethrow;
      }
    }
  }

  Future<void> _compareAndCleanup(SqliteDatabase db, List<Map<String, dynamic>> shadowTables) async {

    // Replace original tables with shadow tables
    await db.writeTransaction((tx) async {
      for (final shadowEntry in shadowTables) {
        final tableName = shadowEntry['entity_name'] as String;

        if (kDebugMode) {
          // Debug: count records in both tables
          final originalCount = await tx.getAll('SELECT COUNT(*) as count FROM "$tableName"');
          final shadowCount = await tx.getAll('SELECT COUNT(*) as count FROM "${tableName}_shadow"');
          SyncLogger.log('$tableName - Original: ${originalCount[0]['count']} records, Shadow: ${shadowCount[0]['count']} records');
        }

        // Check for unsynced data one more time in this specific table
        final unsyncedCheck = await tx.getAll(
          'SELECT 1 FROM "$tableName" WHERE is_unsynced = 1 LIMIT 1'
        );
        
        if (unsyncedCheck.isNotEmpty) {
          if (kDebugMode) {
            SyncLogger.log('Found unsynced data in $tableName, queueing sync and will resume RulesBoard processing');
          }
          // Queue sending unsynced data for this table
          _addToSyncQueue(SyncQueueItem(method: 'sendUnsynced', arguments: {'tableName': tableName}));
          // Queue processing RulesBoard again to resume after unsynced data is sent
          _addToSyncQueue(SyncQueueItem(method: 'syncTable', arguments: {'tableName': 'RulesBoard'}));
          continue;
        }

        // Truncate original table
        if (kDebugMode) {
          SyncLogger.log('Truncating $tableName and copying from shadow');
        }
        // Workaround: SQLite watch stream bug - DELETE without WHERE clause doesn't trigger watch
        // Adding WHERE 1=1 ensures the watch stream is notified of the deletion
        await tx.execute('DELETE FROM "$tableName" WHERE 1=1');
        
        // Copy all data from shadow to original
        final columns = await tx.getAll('PRAGMA table_info("$tableName")');
        final columnNames = columns.map((c) => '"${c['name']}"').join(', ');
        
        await tx.execute('''
          INSERT INTO "$tableName" ($columnNames)
          SELECT $columnNames FROM "${tableName}_shadow"
        ''');

        // Update syncing_table with last_received_ts from shadow
        final shadowSyncInfo = await tx.getAll(
          'SELECT last_received_ts FROM syncing_table_shadow WHERE entity_name = ?',
          [tableName]
        );
        
        if (shadowSyncInfo.isNotEmpty) {
          final shadowTs = shadowSyncInfo[0]['last_received_ts'];
          await tx.execute(
            'UPDATE syncing_table SET last_received_ts = ? WHERE entity_name = ?',
            [shadowTs, tableName],
          );
          
          if (kDebugMode) {
            SyncLogger.log('Updated $tableName last_received_ts to: $shadowTs');
          }
        }
      }
    });

    // Step 9: Drop shadow tables
    await _dropShadowTables(db, shadowTables);

    // Step 10: Call full resync
    if (kDebugMode) {
      SyncLogger.log('Shadow sync complete, adding fullSync to queue');
    }
    _addToSyncQueue(SyncQueueItem(method: 'fullSync'));
  }

  Future<void> _dropShadowTables(SqliteDatabase db, List<Map<String, dynamic>> shadowTables) async {
    await db.writeTransaction((tx) async {
      // Drop entity shadow tables
      for (final shadowEntry in shadowTables) {
        final tableName = shadowEntry['entity_name'] as String;
        await tx.execute('DROP TABLE IF EXISTS "${tableName}_shadow"');
      }
      // Drop shadow syncing_table
      await tx.execute('DROP TABLE IF EXISTS syncing_table_shadow');
    });
  }

  Future<bool> _sendUnsyncedForTable(String tableName) async {
    final db = _db!;
    final rows = await db.getAll(
      'select ${abstractMetaEntity.syncableColumnsString[tableName]} from $tableName where is_unsynced = 1',
    );
    
    if (rows.isEmpty) return true; // Nothing to send, success
    
    final uri = Uri.parse('$_serverUrl/data');
    final headers = {
      'Content-Type': 'application/json',
      'appid': abstractSyncConstants.appId,
    };
    if (_authToken != null) {
      headers['authorization'] = _authToken!;
    }

    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'name': tableName,
        'data': jsonEncode(rows),
      }),
    );
    
    if (res.statusCode != 200) {
      SyncLogger.log('Failed to send unsynced for $tableName: ${res.statusCode}');
      return false;
    }
    
    // Check if data changed during send and mark as synced if not
    final success = await db.writeTransaction((tx) async {
      final rows2 = await tx.getAll(
        'select ${abstractMetaEntity.syncableColumnsString[tableName]} from $tableName where is_unsynced = 1',
      );
      
      if (DeepCollectionEquality().equals(rows, rows2)) {
        await tx.execute(
          'update $tableName set is_unsynced = 0 where is_unsynced = 1',
        );
        return true;
      } else {
        SyncLogger.log('Data changed during send for $tableName, needs retry');
        return false;
      }
    });
    
    return success;
  }

  Future<void> _startSyncer() async {
    if (_sseConnected) return;
    final uri = Uri.parse('$_serverUrl/events');
    final client = http.Client();
    void handleError() {
      _sseConnected = false;
      _eventSubscription?.cancel();
      Future.delayed(const Duration(seconds: 5), _startSyncer);
    }

    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream'
        ..headers['appid'] = abstractSyncConstants.appId;
      if (_authToken != null) {
        request.headers['authorization'] = _authToken!;
      }
      final res = await client.send(request);
      if (res.statusCode == 200) {
        _sseConnected = true;
        _addToSyncQueue(SyncQueueItem(method: 'fullSync'));
        _eventSubscription = res.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (e) {
                //todo: performance improvement, maybe we do not need full here
                if (e.startsWith('data:')) _addToSyncQueue(SyncQueueItem(method: 'fullSync'));
              },
              onError: (e) {
                if (kDebugMode) {
                  SyncLogger.log('SSE error: $e', error: e);
                  handleError();
                }
              },
            );
      } else {
        handleError();
      }
    } catch (e) {
      if (kDebugMode) {
        SyncLogger.log('Error starting SSE: $e', error: e);
      }
      handleError();
    }
  }
  
  @override
  void dispose() {
    isProcessingQueue.dispose();
    _eventSubscription?.cancel();
    _syncQueue.clear();
    isProcessingQueue.value = false;
    _db?.close();
    super.dispose();
  }
}

class BackendWrapper extends InheritedNotifier<BackendNotifier> {
  const BackendWrapper({
    super.key,
    required super.notifier,
    required super.child,
  });

  static BackendNotifier? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackendWrapper>()?.notifier;
}

class _TimestampResult {
  final bool hasError;
  final String? timestamp;
  final String? error;

  _TimestampResult({
    required this.hasError,
    this.timestamp,
    this.error,
  });
}
