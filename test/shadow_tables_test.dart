import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistemium_sync_flutter/shadow_tables.dart';
import 'package:sqlite_async/sqlite_async.dart';

/// The insert the sync makes into a shadow: it names the CURRENT columns.
const _insertPicture =
    'INSERT INTO "Picture_shadow" (_id, ts, href, creatorId) VALUES (?, ?, ?, ?)';

void main() {
  late Directory dir;
  late SqliteDatabase db;

  Future<void> startJob(List<String> tables) => db.writeTransaction((tx) async {
    await tx.execute('''
      CREATE TABLE syncing_table_shadow (
        _id TEXT PRIMARY KEY, entity_name TEXT UNIQUE, last_received_ts TEXT
      )''');
    for (final table in tables) {
      await tx.execute(
        'INSERT INTO syncing_table_shadow (_id, entity_name, last_received_ts) VALUES (?, ?, NULL)',
        [table, table],
      );
      await ShadowTables.create(tx, table);
    }
  });

  Future<void> repair({bool Function(String)? isSyncable}) => db.writeTransaction(
    (tx) => ShadowTables.repair(tx, isSyncable: isSyncable ?? (_) => true),
  );

  Future<Object?> cursorOf(String table) async => (await db.get(
    'SELECT last_received_ts FROM syncing_table_shadow WHERE entity_name = ?',
    [table],
  ))['last_received_ts'];

  Future<int> count(String table) async =>
      (await db.get('SELECT COUNT(*) AS n FROM "$table"'))['n'] as int;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shadow_tables_test');
    db = SqliteDatabase(path: '${dir.path}/sync.db');
    await db.initialize();
    await db.execute(
      'CREATE TABLE "Picture" ("_id" TEXT PRIMARY KEY, "ts" TIMESTAMP, "is_unsynced" INTEGER, "href" TEXT)',
    );
    await db.execute(
      'CREATE TABLE "Person" ("_id" TEXT PRIMARY KEY, "ts" TIMESTAMP, "is_unsynced" INTEGER, "name" TEXT)',
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('a shadow made before a migration added a column is rebuilt and restarted', () async {
    await startJob(['Person', 'Picture']);
    await db.execute('INSERT INTO "Picture_shadow" (_id, ts, href) VALUES (?, ?, ?)', ['p1', 'ts1', 'a.jpg']);
    await db.execute(
      "UPDATE syncing_table_shadow SET last_received_ts = 'ts1' WHERE entity_name = 'Picture'",
    );

    // the app is updated while the job is pending
    await db.execute('ALTER TABLE "Picture" ADD COLUMN "creatorId" TEXT');
    await expectLater(
      db.execute(_insertPicture, ['p2', 'ts2', 'b.jpg', 'u1']),
      throwsA(predicate((e) => '$e'.contains('no column named creatorId'))),
    );

    await repair();

    await db.execute(_insertPicture, ['p2', 'ts2', 'b.jpg', 'u1']);
    expect(await count('Picture_shadow'), 1, reason: 'rows fetched without the new column are dropped');
    expect(await cursorOf('Picture'), isNull, reason: 'the table is downloaded again from the start');
  });

  test('a shadow that still matches keeps its rows and its cursor', () async {
    await startJob(['Person', 'Picture']);
    await db.execute('INSERT INTO "Person_shadow" (_id, ts, name) VALUES (?, ?, ?)', ['n1', 'ts1', 'Jonas']);
    await db.execute(
      "UPDATE syncing_table_shadow SET last_received_ts = 'ts1' WHERE entity_name = 'Person'",
    );
    await db.execute('ALTER TABLE "Picture" ADD COLUMN "creatorId" TEXT');

    await repair();

    expect(await count('Person_shadow'), 1);
    expect(await cursorOf('Person'), 'ts1');
  });

  test('a shadow with a column the table no longer has is rebuilt too', () async {
    await startJob(['Person']);
    await db.execute('ALTER TABLE "Person" DROP COLUMN "name"');

    await repair();

    final columns = await db.getAll('PRAGMA table_info("Person_shadow")');
    expect(columns.map((c) => c['name']), ['_id', 'ts', 'is_unsynced']);
  });

  test('a lost shadow is made again', () async {
    await startJob(['Person']);
    await db.execute('DROP TABLE "Person_shadow"');

    await repair();

    expect(await count('Person_shadow'), 0);
  });

  test('a table that left the schema is taken out of the job', () async {
    await startJob(['Person', 'Picture']);
    await db.execute('DROP TABLE "Person"');

    await repair(isSyncable: (table) => table != 'Picture');

    expect(await db.getAll('SELECT entity_name FROM syncing_table_shadow'), isEmpty);
    final shadows = await db.getAll(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('Person_shadow', 'Picture_shadow')",
    );
    expect(shadows, isEmpty);
  });
}
