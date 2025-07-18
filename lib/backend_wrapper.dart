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

  Timer? _rulesBoardRetryTimer;
  bool _rulesBoardSetupComplete = false;

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

    // Ensure RulesBoard row inside syncing_table before exposing DB
    await _ensureRulesBoardRegistration(tempDb);

    _db = tempDb;
    _startSyncer();
    notifyListeners();
  }

  Future<void> deinitDb() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _sseConnected = false;

    _rulesBoardRetryTimer?.cancel();
    _rulesBoardRetryTimer = null;

    if (_db != null) await _db!.close();
    _db = null;
    notifyListeners();
  }

  // -----------------------------------------------------------------------
  // RulesBoard syncing_table bootstrap
  // -----------------------------------------------------------------------

  Future<void> _ensureRulesBoardRegistration(SqliteDatabase db) async {
    if (_rulesBoardSetupComplete) return;

    try {
      final existing = await db.getAll(
        'SELECT 1 FROM syncing_table WHERE entity_name = ? LIMIT 1',
        ['RulesBoard'],
      );
      if (existing.isNotEmpty) {
        _rulesBoardSetupComplete = true;
        return;
      }

      final latestLts = await _requestLatestRulesBoardLts();

      if (latestLts == null) {
        _scheduleRulesBoardRetry(db);
        return;
      }

      await db.execute(
        'INSERT INTO syncing_table (_id, entity_name, last_received_lts) VALUES (?, ?, ?)',
        [ObjectId().hexString, 'RulesBoard', latestLts],
      );
      _rulesBoardSetupComplete = true;
    } catch (e, st) {
      if (kDebugMode) {
        print('Error ensuring RulesBoard registration: $e');
        print(st);
      }
      _scheduleRulesBoardRetry(db);
    }
  }

  Future<String?> _requestLatestRulesBoardLts() async {
    if (_serverUrl == null) return null;
    try {
      final uri = Uri.parse('$_serverUrl/rules-lts');
      final headers = {
        'appid': abstractSyncConstants.appId,
      };
      if (_authToken != null) {
        headers['authorization'] = _authToken!;
      }

      final res = await http.get(uri, headers: headers);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        return body['lts'] as String?;
      }
    } catch (e) {
      if (kDebugMode) print('RulesBoard LTS request failed: $e');
    }
    return null;
  }

  void _scheduleRulesBoardRetry(SqliteDatabase db) {
    _rulesBoardRetryTimer?.cancel();
    _rulesBoardRetryTimer = Timer(const Duration(seconds: 30), () async {
      await _ensureRulesBoardRegistration(db);
    });
  }

  Stream<List> watch({
    required String sql,
    required List<String> tables,
    String where = '',
    String order = '',
  }) {
    final defaultWhere = ' where (is_deleted != 1 OR is_deleted IS NULL) ';
    final _where = where.isNotEmpty ? ' AND ($where)' : '';
    final _order = order.isNotEmpty ? ' ORDER BY $order' : '';
    return _db!.watch(
      sql + defaultWhere + _where + _order,
      triggerOnTables: tables,
    );
  }

  Future<ResultSet> getAll({
    required String sql,
    String where = '',
    String order = '',
  }) {
    final defaultWhere = ' where (is_deleted != 1 OR is_deleted IS NULL) ';
    final _where = where.isNotEmpty ? ' AND ($where)' : '';
    final _order = order.isNotEmpty ? ' ORDER BY $order' : '';
    return _db!.getAll(sql + defaultWhere + _where + _order);
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
    await _db!.execute(
      'UPDATE $tableName SET is_unsynced = 1, is_deleted = 1 WHERE _id = ?',
      [id],
    );
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
    String? lastReceivedLts,
    required int pageSize,
    required Future<void> Function(Map<String, dynamic>) onData,
  }) async {
    final q = {'name': name, 'pageSize': pageSize.toString()};
    if (lastReceivedLts != null) q['lts'] = lastReceivedLts;
    final uri = Uri.parse('$_serverUrl/data').replace(queryParameters: q);
    final headers = {
      'appid': abstractSyncConstants.appId,
    };
    if (_authToken != null) {
      headers['authorization'] = _authToken!;
    }

    final res = await http.get(
      uri,
      headers: headers,
    );
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
        String? lts = table['last_received_lts']?.toString() ?? '';
        while (more && _db != null) {
          await _fetchData(
            name: table['entity_name'],
            lastReceivedLts: lts,
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
                  print('Last received LTS: $lts');
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
                  print('Last lts in response: ${data.last['lts']}');
                }
                final batch = data
                    .map<List<Object?>>(
                      (e) => cols.map<Object?>((c) => e[c]).toList(),
                    )
                    .toList();
                await tx.executeBatch(sql, batch);
                await tx.execute(
                  'UPDATE syncing_table SET last_received_lts = ? WHERE entity_name = ?',
                  [data.last['lts'], name],
                );
                if (data.length < page) {
                  more = false;
                } else {
                  lts = data.last['lts'];
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

    // After regular sync flow, process any RulesBoard instructions.
    await _processRulesBoard();
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

    bool needRepeat = false;

    await dbLocal.writeTransaction((tx) async {
      // 1. Early exit if any unsynced data exists
      final unsyncedAny = await tx.getAll(
        'select entity_name from syncing_table',
      ).then((tables) async {
        for (var t in tables) {
          final rows = await tx.getAll(
              'select 1 from ${t['entity_name']} where is_unsynced = 1 limit 1');
          if (rows.isNotEmpty) return true;
        }
        return false;
      });

      if (unsyncedAny) {
        if (kDebugMode) {
          print('[RulesBoard] Unsynced data exists, aborting.');
        }
        needRepeat = true;
        return; // abort processing rules
      }

      // 2. Fetch RulesBoard entries (ascending by lts)
      final rulesEntries = await tx.getAll('select * from RulesBoard order by lts asc');
      if (kDebugMode) {
        print('[RulesBoard] Found ${rulesEntries.length} entries.');
      }
      if (rulesEntries.isEmpty) return; // nothing to process

      // 3. For each entry, parse list of tables and reset them
      for (var entry in rulesEntries) {
        if (kDebugMode) {
          print('[RulesBoard] Processing entry: $entry');
        }
        final jsonStr = entry['fullResyncCollections'];
        if (jsonStr == null) continue;
        List<dynamic> list;
        try {
          list = jsonDecode(jsonStr);
        } catch (_) {
          continue; // skip malformed
        }
        for (var tbl in list) {
          if (tbl is! String) continue;
          if (kDebugMode) {
            print('[RulesBoard] Truncating table: $tbl');
          }
          // Truncate table
          // TODO: This is a workaround for a bug in sqlite_async <= 0.11.7 where
          // a DELETE statement without a WHERE clause does not trigger the watch stream.
          await tx.execute('delete from "$tbl" where 1=1');
          // Reset lts in syncing_table
          await tx.execute(
            'update syncing_table set last_received_lts = NULL where entity_name = ?',
            [tbl],
          );
        }
      }

      // 4. Capture latest lts and clear RulesBoard
      final lastLts = rulesEntries.last['lts'];
      if (kDebugMode) {
        print('[RulesBoard] Clearing local RulesBoard table.');
        print('[RulesBoard] Setting last_received_lts for RulesBoard to: $lastLts');
      }
      await tx.execute('delete from RulesBoard');
      await tx.execute(
        'update syncing_table set last_received_lts = ? where entity_name = ?',
        [lastLts, 'RulesBoard'],
      );

      needRepeat = true; // after processing, run another full sync
    });

    if (needRepeat) {
      if (kDebugMode) {
        print('[RulesBoard] Processing complete, triggering another sync.');
      }
      await fullSync();
    }
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
            'delete from ${table['entity_name']} where is_unsynced = 1 and is_deleted = 1',
          );
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
    Key? key,
    required BackendNotifier notifier,
    required Widget child,
  }) : super(key: key, notifier: notifier, child: child);

  static BackendNotifier? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackendWrapper>()?.notifier;
}
