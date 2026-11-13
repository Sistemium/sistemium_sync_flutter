import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:objectid/objectid.dart';
// path_provider's own package, not a dependency named in pubspec.yaml: the only
// way to say where the documents directory is when there is no device.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sistemium_sync_flutter/backend_wrapper.dart';
import 'package:sistemium_sync_flutter/sync_abstract.dart';
import 'package:sqlite_async/sqlite_async.dart';

/// A row deleted elsewhere leaves this device through Archive: the server sends
/// an Archive row, the sync deletes the row it names and clears the Archive row.
/// It finds the row by `_id`: `Archive.id` has to be the `_id` of the deleted
/// row, and no other id of it does anything. A row deleted on this device waits
/// in Archive, unsynced, until the server has it.
///
/// Held here on the library as an app drives it: its database on disk, the sync
/// of a table as an app calls it, and a server that answers over HTTP with what
/// the test gave it.

class _Constants extends AbstractSyncConstants {
  @override
  String get appId => 'test.app';
}

/// One table of the app's own, and the tables every schema has.
class _Migrations extends AbstractPregeneratedMigrations {
  @override
  final SqliteMigrations migrations = SqliteMigrations()
    ..add(
      SqliteMigration(1, (tx) async {
        await tx.execute(
          'CREATE TABLE "Thing" ("_id" TEXT PRIMARY KEY, "ts" TIMESTAMP, "is_unsynced" INTEGER, "id" TEXT, "name" TEXT)',
        );
        await tx.execute(
          'CREATE TABLE "RulesBoard" ("_id" TEXT PRIMARY KEY, "ts" TIMESTAMP, "is_unsynced" INTEGER, "userIds" TEXT, "fullResyncCollections" TEXT, "note" TEXT)',
        );
        await tx.execute(
          'CREATE TABLE "Archive" ("_id" TEXT PRIMARY KEY, "ts" TIMESTAMP, "is_unsynced" INTEGER, "id" TEXT, "name" TEXT, "data" TEXT)',
        );
        await tx.execute(
          'CREATE TABLE "syncing_table" ("_id" TEXT PRIMARY KEY, "entity_name" TEXT, "last_received_ts" TIMESTAMP)',
        );
        await tx.execute('INSERT INTO "syncing_table" (_id, entity_name) VALUES (?, ?)', ['thing', 'Thing']);
      }),
    );
}

class _Meta extends AbstractMetaEntity {
  static const _columns = {
    'Thing': ['_id', 'ts', 'id', 'name'],
    'RulesBoard': ['_id', 'ts', 'userIds', 'fullResyncCollections', 'note'],
    'Archive': ['_id', 'ts', 'id', 'name', 'data'],
  };

  @override
  Map<String, List> get syncableColumnsList => _columns;

  @override
  Map<String, String> get syncableColumnsString => {
    for (final table in _columns.entries) table.key: table.value.join(', '),
  };
}

class _DocumentsAt extends PathProviderPlatform {
  _DocumentsAt(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

/// The sync server as the library asks it over HTTP: the rows it has for a table,
/// and whether it takes what is posted.
class _Server {
  final _rows = <String, List<Map<String, Object?>>>{};
  final _meanwhile = <String, Future<void> Function()>{};
  final refusedPosts = <String>[];
  bool takesPosts = true;
  Completer<void>? _postsHeld;
  int _ts = 0;

  String nextTs() => '2026-11-13T10:00:00.000Z-${(++_ts).toString().padLeft(10, '0')}';

  Map<String, Object?> thing() {
    final id = ObjectId().hexString;
    return {'_id': id, 'ts': nextTs(), 'id': 'thing-$id', 'name': 'a thing'};
  }

  /// The Archive row of a delete: `data` is never sent to a device.
  Map<String, Object?> archiveOf(Object? id, {String name = 'Thing'}) => {
    '_id': ObjectId().hexString,
    'ts': nextTs(),
    'id': id,
    'name': name,
  };

  void has(String table, List<Map<String, Object?>> rows) =>
      _rows.putIfAbsent(table, () => []).addAll(rows);

  /// What happens on the device while the server is answering its next read of [table].
  void whileFetching(String table, Future<void> Function() happens) => _meanwhile[table] = happens;

  /// The server leaves what is posted unanswered until [answerPosts].
  void holdPosts() => _postsHeld = Completer<void>();

  void answerPosts() {
    _postsHeld?.complete();
    _postsHeld = null;
  }

  http.Client get client => MockClient(_answer);

  Future<http.Response> _answer(http.Request request) async {
    http.Response json(Object? body) =>
        http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

    switch (request.url.pathSegments.last) {
      case 'events':
        // The live stream never opens, so nothing is synced but what a test asks for.
        return Completer<http.Response>().future;
      case 'latest-ts':
        return json({'ts': null});
      case 'data' when request.method == 'GET':
        final table = request.url.queryParameters['name']!;
        await _meanwhile.remove(table)?.call();
        return json({'data': _rows.remove(table) ?? const []});
      case 'data':
        final posted = jsonDecode(request.body) as Map<String, dynamic>;
        await _postsHeld?.future;
        if (!takesPosts) {
          refusedPosts.add(posted['name'] as String);
          return http.Response('not now', 500);
        }
        return json({
          'resuts': [
            for (final row in jsonDecode(posted['data'] as String) as List) {'_id': row['_id'], 'ts': nextTs()},
          ],
        });
    }
    return http.Response('no such route', 404);
  }
}

void main() {
  late Directory dir;
  late _Server server;
  late BackendNotifier phone;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('archive_test');
    PathProviderPlatform.instance = _DocumentsAt(dir.path);
    server = _Server();
    phone = BackendNotifier(
      abstractPregeneratedMigrations: _Migrations(),
      abstractSyncConstants: _Constants(),
      abstractMetaEntity: _Meta(),
    );
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// What the phone does unasked (a send after a delete, a table to sync again)
  /// has come to rest.
  Future<void> idle() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (phone.isProcessingQueue.value) {
      if (DateTime.now().isAfter(deadline)) fail('The sync queue never came to rest');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// [body] on a phone that is signed in. Everything the library asks over HTTP
  /// inside it goes to [server].
  void onAPhone(String description, Future<void> Function() body) {
    test(description, () {
      return http.runWithClient(() async {
        await phone.initDb(serverUrl: 'http://sync.test/api', userId: 'user-1', authToken: 'token');
        try {
          await body();
        } finally {
          server.answerPosts();
          await idle();
          await phone.deinitDb();
        }
      }, () => server.client);
    });
  }

  /// The server has [rows] of [table], and the phone syncs that table.
  Future<void> pulled(String table, List<Map<String, Object?>> rows) async {
    server.has(table, rows);
    await phone.syncTable(table);
  }

  Future<List<Object?>> things() async => [
    for (final row in await phone.getAll('SELECT _id FROM "Thing"')) row['_id'],
  ];

  Future<List<Map<String, Object?>>> archive() async => [
    for (final row in await phone.getAll('SELECT * FROM "Archive"')) Map<String, Object?>.from(row),
  ];

  onAPhone('an Archive row that names a row by its _id removes that row and is cleared', () async {
    final gone = server.thing();
    final stays = server.thing();
    await pulled('Thing', [gone, stays]);
    expect(await things(), unorderedEquals([gone['_id'], stays['_id']]));

    final row = server.archiveOf(gone['_id']);
    await pulled('Archive', [row]);

    expect(await things(), [stays['_id']]);
    expect(await archive(), isEmpty);
    // It was taken, so it is not asked for again.
    final cursor = await phone.get("SELECT last_received_ts FROM syncing_table WHERE entity_name = 'Archive'");
    expect(cursor?['last_received_ts'], row['ts']);
  });

  onAPhone('an Archive row that names anything else removes nothing, and is cleared', () async {
    final one = server.thing();
    final other = server.thing();
    await pulled('Thing', [one, other]);

    await pulled('Archive', [
      // Another id of a row here: what a backend that knows the row by `id` writes.
      server.archiveOf(one['id']),
      // An _id no row here has.
      server.archiveOf(ObjectId().hexString),
      // The _id of a row here, in a table this app does not sync.
      server.archiveOf(other['_id'], name: 'Elsewhere'),
    ]);

    expect(await things(), unorderedEquals([one['_id'], other['_id']]));
    expect(await archive(), isEmpty);
  });

  onAPhone('an Archive row waiting to be sent is left alone while the others are applied', () async {
    final goneElsewhere = server.thing();
    final deletedHere = server.thing();
    final stays = server.thing();
    await pulled('Thing', [goneElsewhere, deletedHere, stays]);

    // An Archive row that arrived and was not applied: the app was closed between the two.
    final arrived = server.archiveOf(goneElsewhere['_id']);
    await phone.execute('INSERT INTO "Archive" (_id, ts, id, name) VALUES (?, ?, ?, ?)', [
      arrived['_id'],
      arrived['ts'],
      arrived['id'],
      arrived['name'],
    ]);

    // While Archive is being fetched the user deletes a row, and the server is slow to take it.
    server.holdPosts();
    server.whileFetching('Archive', () => phone.delete(tableName: 'Thing', id: deletedHere['_id'] as String));
    await phone.syncTable('Archive');

    Future<void> expectTheDeleteStillWaits() async {
      expect(await things(), [stays['_id']]);
      final waiting = await archive();
      expect(waiting, hasLength(1));
      expect(waiting.single, containsPair('id', deletedHere['_id']));
      expect(waiting.single, containsPair('name', 'Thing'));
      expect(waiting.single, containsPair('is_unsynced', 1));
      expect(jsonDecode(waiting.single['data'] as String), containsPair('_id', deletedHere['_id']));
    }

    // The row that arrived did its work and is gone; the delete made here waits to be sent.
    await expectTheDeleteStillWaits();

    // The server does not take it in the end, and it goes on waiting.
    server.takesPosts = false;
    server.answerPosts();
    await idle();
    expect(server.refusedPosts, contains('Archive'));
    await expectTheDeleteStillWaits();
  });
}
