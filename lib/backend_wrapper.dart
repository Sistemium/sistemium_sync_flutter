import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:objectid/objectid.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sistemium_sync_flutter/sync_abstract.dart';
import 'package:sqlite_async/sqlite3.dart';
import 'package:sqlite_async/sqlite3_common.dart';
import 'package:sqlite_async/sqlite_async.dart';

class BackendWrapper extends InheritedWidget {
  final ValueNotifier<SqliteDatabase?> db = ValueNotifier<SqliteDatabase?>(
    null,
  );
  final ValueNotifier _sseConnected = ValueNotifier(false);
  final ValueNotifier<StreamSubscription?> _eventSubscription = ValueNotifier(
    null,
  );
  final AbstractPregeneratedMigrations abstractPregeneratedMigrations;
  final AbstractSyncConstants abstractSyncConstants;
  final AbstractMetaEntity abstractMetaEntity;
  late final _serverUrl;
  late final userId;

  BackendWrapper({
    super.key,
    required super.child,
    required this.abstractPregeneratedMigrations,
    required this.abstractSyncConstants,
    required this.abstractMetaEntity,
  });

  static BackendWrapper? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackendWrapper>();

  @override
  bool updateShouldNotify(BackendWrapper oldWidget) => false;

  Future initDb({String? serverUrl, required String userId}) async {
    if (serverUrl != null) {
      _serverUrl = serverUrl;
    } else {
      _serverUrl = abstractSyncConstants.serverUrl;
    }
    this.userId = userId;
    final SqliteDatabase tempDb = await openDatabase();
    final migrations = abstractPregeneratedMigrations.migrations;
    await migrations.migrate(tempDb);
    db.value = tempDb;
    startSyncer();
    print('Database initialized');
  }

  Future deinitDb() async {
    print('Deinitializing database...');
    _eventSubscription.value?.cancel();
    _eventSubscription.value = null;
    _sseConnected.value = false;
    if (db.value != null) {
      await db.value!.close();
    }
    db.value = null;
    print('Database deinitialized');
  }

  Stream<List> watch({
    required String sql,
    required List<String> tables,
    String where = '',
    String order = '',
  }) {
    String defaultWhere = ' where (is_deleted != 1 OR is_deleted IS NULL) ';
    String _order = order.isNotEmpty ? ' ORDER BY $order' : '';
    return db.value!.watch(
      sql + defaultWhere + where + _order,
      triggerOnTables: tables,
    );
  }

  Future<ResultSet> getAll({
    required String sql,
    String where = '',
    String order = '',
  }) {
    String defaultWhere = ' where (is_deleted != 1 OR is_deleted IS NULL) ';
    String _order = order.isNotEmpty ? ' ORDER BY $order' : '';
    return db.value!.getAll(sql + defaultWhere + where + _order);
  }


  write({required String tableName, required Map data}) async {
    final database = db.value!;
    final columns = data.keys.toList();
    if (data['_id'] == null) {
      data['_id'] = ObjectId().hexString;
    }
    final values = data.values.toList();
    final placeholders = List.filled(columns.length, '?').join(', ');
    final updatePlaceholders = columns.map((col) => '$col = ?').join(', ');

    final sql = '''
      INSERT INTO $tableName (${columns.join(', ')}, is_unsynced)
      VALUES ($placeholders, 1)
      ON CONFLICT(_id) DO UPDATE SET
      $updatePlaceholders, is_unsynced = 1
    ''';

    await database.execute(sql, [...values, ...values]);
    fullSync();
    return;
  }

  delete({required String tableName, required String id}) async {
    final primaryKey = '_id';
    final database = db.value!;

    final sql = '''
      UPDATE $tableName SET is_unsynced = 1, is_deleted = 1 WHERE $primaryKey = ?
    ''';

    await database.execute(sql, [id]);
    fullSync();
    return;
  }

  Future<SqliteDatabase> openDatabase() async {
    final dbPath = await getDatabasePath('$userId/helper_sync.db');
    final db = SqliteDatabase(
      path: dbPath,
      options: SqliteOptions(
        webSqliteOptions: WebSqliteOptions(
          wasmUri: 'sqlite3.wasm',
          workerUri: 'db_worker.js',
        ),
      ),
    );
    return db;
  }

  Future<String> getDatabasePath(String dbName) async {
    String basePath = '';
    if (!kIsWeb) {
      final dir = await getApplicationDocumentsDirectory();
      basePath = dir.path;
    }
    final fullPath = p.join(basePath, dbName);
    final dirPath = p.dirname(fullPath);
    final dirToCreate = Directory(dirPath);
    if (!await dirToCreate.exists()) {
      await dirToCreate.create(recursive: true);
    }
    return fullPath;
  }

  Future<void> fetchData({
    required String name,
    String? lastReceivedLts,
    required int pageSize,
    required Function(Map<String, dynamic>) onDataReceived,
  }) async {
    final queryParams = {'name': name, 'pageSize': pageSize.toString()};
    if (lastReceivedLts != null) {
      queryParams['lts'] = lastReceivedLts;
    }
    final uri = Uri.parse(
      '$_serverUrl/data',
    ).replace(queryParameters: queryParams);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      onDataReceived(data);
    } else {
      throw Exception('Failed to fetch data');
    }
  }

  //todo: sometimes we need to sync only one table, not all
  fullSync() async {
    bool needRepeatFullSync = false;
    final ResultSet syncingTables = await db.value!.getAll(
      'select * from syncing_table',
    );

    await sendUnsynced(syncingTables: syncingTables);

    for (var table in syncingTables) {
      int pageSize = 1000;
      bool hasMoreData = true;
      String? lastReceivedLts = table['last_received_lts']?.toString() ?? '';

      while (hasMoreData) {
        await fetchData(
          name: table['entity_name'],
          lastReceivedLts: lastReceivedLts,
          pageSize: pageSize,
          onDataReceived: (Map<String, dynamic> response) async {
            await db.value!.writeTransaction((tx) async {
              final ResultSet result = await tx.getAll(
                'select * from ${table['entity_name']} where is_unsynced = 1',
              );
              if (result.isNotEmpty) {
                hasMoreData = false;
                //todo: might there be infinite loop, perhaps we need to log something to sentry for debug purposes
                needRepeatFullSync = true;
                return;
              }
              if (response['data']?.length > 0 == false) {
                hasMoreData = false;
                return;
              }
              final name = table['entity_name'];
              final primaryKey = '_id';
              final columns = response['data'][0].keys.toList();
              final placeholders = List.filled(columns.length, '?').join(', ');
              final columnsToUpdate = columns.where((k) => k != primaryKey);
              final updateAssignments = columnsToUpdate
                  .map((k) => "$k = excluded.$k")
                  .join(', ');
              final sql = '''
INSERT INTO $name (${columns.join(', ')}) VALUES ($placeholders)
ON CONFLICT($primaryKey) DO UPDATE SET $updateAssignments;
''';
              final List<Map<String, dynamic>> data =
                  List<Map<String, dynamic>>.from(response['data']);

              final List<List<Object?>> batchValues =
                  data.map<List<Object?>>((Map<String, dynamic> dataItem) {
                    return columns
                        .map<Object?>((k) => dataItem[k] as Object?)
                        .toList();
                  }).toList();
              await tx.executeBatch(sql, batchValues);

              if (data.length < pageSize) {
                hasMoreData = false;
                await tx.execute(
                  'UPDATE syncing_table SET last_received_lts = ? WHERE entity_name = ?',
                  [data.last["lts"], name],
                );
              } else {
                lastReceivedLts = data.last["lts"];
              }
            });
          },
        );
      }
    }
    if (needRepeatFullSync) {
      fullSync();
    }
  }

  sendUnsynced({required ResultSet syncingTables}) async {
    SqliteDatabase database = db.value!;
    bool shouldBreakAndRetry = false;
    for (var table in syncingTables) {
      final ResultSet result = await database.getAll(
        'select ${abstractMetaEntity.syncableColumns[table['_id']]} from ${table['_id']} where is_unsynced = 1',
      );
      if (result.isEmpty) {
        continue;
      }
      final uri = Uri.parse('$_serverUrl/data');
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': table['_id'], 'data': jsonEncode(result)}),
      );
      print('Response: ${response.body}');
      print('Response Code: ${response.statusCode}');
      if (response.statusCode != 200) {
        //todo: not sure, may be infinite loop
        shouldBreakAndRetry = true;
        break;
      }
      await database.writeTransaction((tx) async {
        //todo: not sure if this most efficient way
        final ResultSet result2 = await tx.getAll(
          'select ${abstractMetaEntity.syncableColumns[table['_id']]} from ${table['_id']} where is_unsynced = 1',
        );
        if (DeepCollectionEquality().equals(result, result2)) {
          await tx.execute(
            'delete from ${table['_id']} where is_unsynced = 1 and is_deleted = 1',
          );
          await tx.execute(
            'update ${table['_id']} set is_unsynced = 0 where is_unsynced = 1',
          );
        } else {
          shouldBreakAndRetry = true;
        }
      });
      if (shouldBreakAndRetry) {
        await sendUnsynced(syncingTables: syncingTables);
        break;
      }
    }
  }

  Future<void> startSyncer() async {
    if (_sseConnected.value) return;

    final uri = Uri.parse('$_serverUrl/events');
    final client = http.Client();

    try {
      final request = http.Request('GET', uri)
        ..headers['Accept'] = 'text/event-stream';
      final response = await client.send(request);

      if (response.statusCode == 200) {
        _sseConnected.value = true;
        fullSync();
        _eventSubscription.value = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              (event) {
                if (event.startsWith('data:')) {
                  final data = jsonDecode(event.substring(5));
                  print('Data Changed: $data');
                  //todo: performance improvement, maybe we do not need full here
                  fullSync();
                }
              },
              onError: (error) {
                print("Error in SSE connection: $error");
                _sseConnected.value = false;
                _eventSubscription.value?.cancel();
                Future.delayed(Duration(seconds: 5), startSyncer);
              },
              onDone: () {
                print("SSE connection closed");
                _sseConnected.value = false;
                _eventSubscription.value?.cancel();
                Future.delayed(Duration(seconds: 5), startSyncer);
              },
            );
      } else {
        print('Failed to connect to SSE: ${response.statusCode}');
        _sseConnected.value = false;
        Future.delayed(Duration(seconds: 5), startSyncer);
      }
    } catch (e) {
      print("Error connecting to SSE: $e");
      _sseConnected.value = false;
      Future.delayed(Duration(seconds: 5), startSyncer);
    }
  }
}
