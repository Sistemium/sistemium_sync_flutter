import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:objectid/objectid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistemium_sync_flutter/sync_abstract.dart';
import 'package:sqlite_async/sqlite3.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

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

  BackendNotifier({
    required this.abstractPregeneratedMigrations,
    required this.abstractSyncConstants,
    required this.abstractMetaEntity,
  });

  SqliteDatabase? get db => _db;

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

      final latestTs = await _requestLatestTableTs(tableName);
      if (latestTs == null) {
        throw Exception('Failed to get $tableName timestamp');
      }

      await db.execute(
        'INSERT INTO syncing_table (_id, entity_name, last_received_ts) VALUES (?, ?, ?)',
        [ObjectId().hexString, tableName, latestTs],
      );
    } catch (e, st) {
      if (kDebugMode) {
        print('Error ensuring $tableName registration: $e');
        print(st);
      }
      _scheduleTableRetry(db, tableName);
    }
  }


  Future<String?> _requestLatestTableTs(String tableName) async {
    if (_serverUrl == null) return null;
    try {
      final uri = Uri.parse('$_serverUrl/latest-ts').replace(queryParameters: {'name': tableName});
      final headers = {'appid': abstractSyncConstants.appId};
      if (_authToken != null) {
        headers['authorization'] = _authToken!;
      }

      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['ts'] as String?;
      }
    } catch (e) {
      if (kDebugMode) print('$tableName TS request failed: $e');
    }
    return null;
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
      fullSync();
    }
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

    await fullSync();
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
      final data = jsonDecode(res.body);
      await onData(data);
    } else {
      throw Exception('Failed to fetch data');
    }
  }

  var fullSyncStarted = false;
  bool repeat = false;

  //todo: sometimes we need to sync only one table, not all
  Future<void> fullSync() async {
    if (fullSyncStarted) {
      repeat = true;
      return;
    }
    fullSyncStarted = true;
    try {
      final tables = await _db!.getAll('select * from syncing_table');
      await _sendUnsynced(syncingTables: tables);
      for (var table in tables) {
        int page = 1000;
        bool more = true;
        String? ts = table['last_received_ts']?.toString() ?? '';
        while (more && _db != null) {
          await _fetchData(
            name: table['entity_name'],
            lastReceivedTs: ts,
            pageSize: page,
            onData: (resp) async {
              await _db!.writeTransaction((tx) async {
                final unsynced = await tx.getAll(
                  'select * from ${table['entity_name']} where is_unsynced = 1',
                );
                if (unsynced.isNotEmpty) {
                  more = false;
                  //todo: might there be infinite loop, perhaps we need to log something to sentry for debug purposes
                  repeat = true;
                  return;
                }
                if (kDebugMode) {
                  print('Syncing ${table['entity_name']}');
                  print('Last received TS: $ts');
                  print('Received ${resp['data']?.length ?? 0} rows');
                }
                if ((resp['data']?.length ?? 0) == 0) {
                  more = false;
                  return;
                }
                final name = table['entity_name'];
                final pk = '_id';
                final cols = abstractMetaEntity
                    .syncableColumnsList[table['entity_name']]!;
                final placeholders = List.filled(cols.length, '?').join(', ');
                final updates = cols
                    .where((c) => c != pk)
                    .map((c) => '$c = excluded.$c')
                    .join(', ');
                final sql =
                    '''
INSERT INTO $name (${cols.join(', ')}) VALUES ($placeholders)
ON CONFLICT($pk) DO UPDATE SET $updates;
''';
                final data = List<Map<String, dynamic>>.from(resp['data']);
                if (kDebugMode) {
                  print('Last ts in response: ${data.last['ts']}');
                }
                final batch = data
                    .map<List<Object?>>(
                      (e) => cols.map<Object?>((c) => e[c]).toList(),
                    )
                    .toList();
                await tx.executeBatch(sql, batch);
                await tx.execute(
                  'UPDATE syncing_table SET last_received_ts = ? WHERE entity_name = ?',
                  [data.last['ts'], name],
                );
                if (data.length < page) {
                  more = false;
                } else {
                  ts = data.last['ts'];
                }
              });
            },
          );
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        print('Error during full sync: $e');
        print(stackTrace);
      }
    }

    fullSyncStarted = false;

    if (repeat) {
      repeat = false;
      await fullSync();
    }

    // After regular sync flow, process Archive entries first, then RulesBoard.
    await _processArchive();
    await _processRulesBoard();
  }

  // -----------------------------------------------------------------------
  // Archive handling
  // -----------------------------------------------------------------------

  Future<void> _processArchive() async {
    // Ensure DB is available
    final dbLocal = _db;
    if (dbLocal == null) return;

    if (kDebugMode) {
      print('[Archive] Starting processing...');
    }

    bool needRepeat = false;

    await dbLocal.writeTransaction((tx) async {
      // 1. Early exit if any unsynced Archive data exists
      final unsyncedArchive = await tx.getAll(
        'select 1 from Archive where is_unsynced = 1 limit 1',
      );

      if (unsyncedArchive.isNotEmpty) {
        if (kDebugMode) {
          print('[Archive] Unsynced Archive data exists, aborting processing.');
        }
        needRepeat = true;
        return; // abort processing
      }

      // 2. Get all Archive entries
      final archiveEntries = await tx.getAll(
        'select * from Archive order by ts asc',
      );
      if (kDebugMode) {
        print('[Archive] Found ${archiveEntries.length} entries.');
      }
      if (archiveEntries.isEmpty) return; // nothing to process

      // Process each Archive entry
      for (var entry in archiveEntries) {
        if (kDebugMode) {
          print('[Archive] Processing entry: ${entry['_id']}');
        }

        final entityName = entry['name'];
        final entityId = entry['id'];

        if (entityName == null || entityId == null) {
          if (kDebugMode) {
            print('[Archive] Skipping malformed entry: missing name or id');
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
            print('[Archive] Skipping delete for $entityName - table not in syncing_table');
          }
          continue;
        }

        if (kDebugMode) {
          print('[Archive] Deleting $entityId from $entityName');
        }

        // Delete the referenced document if it exists
        await tx.execute('DELETE FROM "$entityName" WHERE id = ?', [entityId]);
      }

      // After processing all entries, clear the Archive table
      if (archiveEntries.isNotEmpty) {
        if (kDebugMode) {
          print('[Archive] Clearing local Archive table.');
        }
        await tx.execute('DELETE FROM Archive');
      }
    });

    if (needRepeat) {
      if (kDebugMode) {
        print('[Archive] Processing aborted due to unsynced data, triggering another sync.');
      }
      await fullSync();
    } else if (kDebugMode) {
      print('[Archive] Processing complete.');
    }
  }

  // -----------------------------------------------------------------------
  // RulesBoard handling
  // -----------------------------------------------------------------------

  Future<void> _processRulesBoard() async {
    // Ensure DB is available
    final dbLocal = _db;
    if (dbLocal == null) return;

    if (kDebugMode) {
      print('[RulesBoard] Starting processing...');
    }

    // Step 1-2: Ensure everything is synced before processing
    final hasUnsyncedData = await _hasAnyUnsyncedData(dbLocal);
    if (hasUnsyncedData) {
      if (kDebugMode) {
        print('[RulesBoard] Unsynced data exists, triggering sync first.');
      }
      await fullSync();
      return;
    }

    // Step 3: Check if shadow syncing_table exists (indicates resuming)
    final shadowSyncingExists = await dbLocal.getAll(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='syncing_table_shadow'",
    );

    if (shadowSyncingExists.isNotEmpty) {
      if (kDebugMode) {
        print('[RulesBoard] Found existing shadow tables, resuming resync...');
      }
      // Jump to step 6 - process shadow syncing table
      await _processShadowSync(dbLocal);
      return;
    }

    // Fetch RulesBoard entries to process
    final rulesEntries = await dbLocal.getAll(
      'SELECT * FROM RulesBoard ORDER BY ts ASC',
    );

    if (rulesEntries.isEmpty) {
      if (kDebugMode) {
        print('[RulesBoard] No entries to process.');
      }
      return;
    }

    // Process each RulesBoard entry
    for (final entry in rulesEntries) {
      await _processRulesBoardEntry(dbLocal, entry);
    }
  }

  Future<bool> _hasAnyUnsyncedData(SqliteDatabase db) async {
    final tables = await db.getAll('SELECT entity_name FROM syncing_table');
    for (final table in tables) {
      final tableName = table['entity_name'] as String;
      final unsynced = await db.getAll(
        'SELECT 1 FROM "$tableName" WHERE is_unsynced = 1 LIMIT 1',
      );
      if (unsynced.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _processRulesBoardEntry(SqliteDatabase db, Map<String, dynamic> entry) async {
    if (kDebugMode) {
      print('[RulesBoard] Processing entry: $entry');
    }

    final jsonStr = entry['fullResyncCollections'];
    if (jsonStr == null) return;

    List<String> tablesToResync;
    try {
      final decoded = jsonDecode(jsonStr);
      tablesToResync = (decoded as List).whereType<String>().toList();
    } catch (_) {
      if (kDebugMode) {
        print('[RulesBoard] Failed to parse fullResyncCollections');
      }
      return;
    }

    // Filter out system tables
    tablesToResync = tablesToResync.where((tbl) => 
      tbl != 'RulesBoard' && tbl != 'Archive' && tbl != 'syncing_table'
    ).toList();

    if (tablesToResync.isEmpty) {
      if (kDebugMode) {
        print('[RulesBoard] No user tables to resync');
      }
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
      print('[RulesBoard] Processing shadow sync...');
    }

    // Get tables to sync from shadow syncing_table
    final shadowTables = await db.getAll('SELECT * FROM syncing_table_shadow');

    for (final shadowEntry in shadowTables) {
      final tableName = shadowEntry['entity_name'] as String;
      final lastTs = shadowEntry['last_received_ts'] as String?;

      if (kDebugMode) {
        print('[RulesBoard] Syncing shadow table: $tableName from ts: $lastTs');
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
    String? currentTs = initialTs;

    while (hasMore && _db != null) {
      try {
        await _fetchData(
          name: tableName,
          lastReceivedTs: currentTs,
          pageSize: pageSize,
          onData: (resp) async {
            await db.writeTransaction((tx) async {
              final data = List<Map<String, dynamic>>.from(resp['data'] ?? []);
              
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
          print('[RulesBoard] Error syncing shadow table $tableName: $e');
        }
        rethrow;
      }
    }
  }

  Future<void> _compareAndCleanup(SqliteDatabase db, List<Map<String, dynamic>> shadowTables) async {
    // First check for any new unsynced data
    final hasNewUnsyncedData = await _hasAnyUnsyncedData(db);
    if (hasNewUnsyncedData) {
      if (kDebugMode) {
        print('[RulesBoard] New unsynced data appeared during shadow sync, dropping shadow tables and doing full sync');
      }
      // Drop all shadow tables
      await _dropShadowTables(db, shadowTables);
      await fullSync();
      return;
    }

    // Compare and delete unauthorized records
    await db.writeTransaction((tx) async {
      for (final shadowEntry in shadowTables) {
        final tableName = shadowEntry['entity_name'] as String;

        // Find records that exist in original but not in shadow (and are synced)
        final toDelete = await tx.getAll('''
          SELECT _id FROM "$tableName" 
          WHERE _id NOT IN (SELECT _id FROM "${tableName}_shadow")
          AND is_unsynced = 0
        ''');

        if (kDebugMode && toDelete.isNotEmpty) {
          print('[RulesBoard] Deleting ${toDelete.length} unauthorized records from $tableName');
        }

        // Delete unauthorized records
        for (final record in toDelete) {
          await tx.execute('DELETE FROM "$tableName" WHERE _id = ?', [record['_id']]);
        }

        // Step 8: Reset last_received_ts in original syncing_table
        await tx.execute(
          'UPDATE syncing_table SET last_received_ts = NULL WHERE entity_name = ?',
          [tableName],
        );
      }
    });

    // Step 9: Drop shadow tables
    await _dropShadowTables(db, shadowTables);

    // Step 10: Call full resync
    if (kDebugMode) {
      print('[RulesBoard] Shadow sync complete, triggering full sync');
    }
    await fullSync();
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

  Future<void> _sendUnsynced({required ResultSet syncingTables}) async {
    final db = _db!;
    bool retry = false;
    for (var table in syncingTables) {
      final rows = await db.getAll(
        'select ${abstractMetaEntity.syncableColumnsString[table['entity_name']]} from ${table['entity_name']} where is_unsynced = 1',
      );
      if (rows.isEmpty) continue;
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
          'name': table['entity_name'],
          'data': jsonEncode(rows),
        }),
      );
      if (res.statusCode != 200) {
        //todo: not sure, may be infinite loop
        retry = true;
        break;
      }
      await db.writeTransaction((tx) async {
        //todo: not sure if this most efficient way
        final rows2 = await tx.getAll(
          'select ${abstractMetaEntity.syncableColumnsString[table['entity_name']]} from ${table['entity_name']} where is_unsynced = 1',
        );
        if (DeepCollectionEquality().equals(rows, rows2)) {
          await tx.execute(
            'update ${table['entity_name']} set is_unsynced = 0 where is_unsynced = 1',
          );
        } else {
          retry = true;
        }
      });
      if (retry) {
        await _sendUnsynced(syncingTables: syncingTables);
        break;
      }
    }
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
        await fullSync();
        _eventSubscription = res.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (e) {
                //todo: performance improvement, maybe we do not need full here
                if (e.startsWith('data:')) fullSync();
              },
              onError: (e) {
                if (kDebugMode) {
                  print('SSE error: $e');
                  handleError();
                }
              },
            );
      } else {
        handleError();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error starting SSE: $e');
      }
      handleError();
    }
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
