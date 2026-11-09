import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistemium_sync_flutter/sent_rows.dart';
import 'package:sqlite_async/sqlite_async.dart';

/// The reply to a send, and what it does to the rows that were sent. The case
/// behind it: a bug report inserted, then its screenshot saved seconds later.
/// With only the ts from the reply, the copy held "this version" with the number
/// the server gave it still empty, and the screenshot's save cleared the number.
const _columns = ['_id', 'ts', 'id', 'ndoc', 'title', 'screenshotUrl'];

const _serverTs = '2026-10-21T06:42:43.000Z-0000000002';

void main() {
  late Directory dir;
  late SqliteDatabase db;

  Future<Map<String, Object?>> row(String id) async =>
      Map<String, Object?>.from(await db.get('SELECT * FROM "Issue" WHERE _id = ?', [id]));

  Future<List<Map<String, Object?>>> readForSend() async => [
        for (final r in await db.getAll(
          'SELECT ${_columns.join(', ')} FROM "Issue" WHERE is_unsynced = 1',
        ))
          Map<String, Object?>.from(r),
      ];

  Future<bool> apply(List<Map<String, Object?>> sent, Map<String, SentRowReply> replies) =>
      db.writeTransaction(
        (tx) => SentRows.apply(
          tx,
          tableName: 'Issue',
          columns: _columns,
          sent: sent,
          replies: replies,
        ),
      );

  // The app's write: a new report, ts still empty, waiting to be sent.
  Future<void> newReport(String id) => db.execute(
        'INSERT INTO "Issue" (_id, ts, id, ndoc, title, screenshotUrl, is_unsynced) VALUES (?, NULL, ?, NULL, ?, NULL, 1)',
        [id, 'issue-$id', 'Mobile report'],
      );

  Map<String, dynamic> storedOf(String id, {String? screenshotUrl}) => {
        '_id': id,
        'ts': _serverTs,
        'id': 'issue-$id',
        'ndoc': 'INC-0372',
        'title': 'Mobile report',
        'screenshotUrl': screenshotUrl,
      };

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sent_rows_test');
    db = SqliteDatabase(path: '${dir.path}/sync.db');
    await db.initialize();
    await db.execute(
      'CREATE TABLE "Issue" ("_id" TEXT PRIMARY KEY, "ts" TIMESTAMP, "is_unsynced" INTEGER, '
      '"id" TEXT, "ndoc" TEXT, "title" TEXT, "screenshotUrl" TEXT, "localOnly" TEXT)',
    );
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  group('parseReplies', () {
    test('reads ts, the stored row and refusals, by _id', () {
      final replies = SentRows.parseReplies(jsonEncode({
        'resuts': [
          {'message': 'Document inserted', '_id': 'a', 'ts': _serverTs, 'stored': {'ndoc': 'INC-0372'}},
          {'message': 'Conflict: Document already exists', '_id': 'b', 'ignored': true},
          {'message': 'Document updated', '_id': 'c', 'ts': _serverTs},
          {'error': 'Invalid ts format.', 'doc': {}},
        ],
      }));

      expect(replies.keys, ['a', 'b', 'c']);
      expect(replies['a']!.ts, _serverTs);
      expect(replies['a']!.stored, {'ndoc': 'INC-0372'});
      expect(replies['b']!.ignored, isTrue);
      expect(replies['c']!.stored, isNull);
    });

    test('a body it cannot read gives no replies', () {
      expect(SentRows.parseReplies('Bad Gateway'), isEmpty);
      expect(SentRows.parseReplies('{"resuts": "no"}'), isEmpty);
    });
  });

  group('apply', () {
    test('a row unchanged since the send takes what the server stored, number included', () async {
      await newReport('r1');
      final sent = await readForSend();

      final synced = await apply(sent, {'r1': SentRowReply(ts: _serverTs, stored: storedOf('r1'))});

      expect(synced, isTrue);
      final r = await row('r1');
      expect(r['ndoc'], 'INC-0372');
      expect(r['ts'], _serverTs);
      expect(r['is_unsynced'], 0);
    });

    test('a row edited during the send keeps the edit, takes the number and ts, and stays unsynced', () async {
      await newReport('r1');
      final sent = await readForSend();
      // The screenshot's save lands while the insert is on its way.
      await db.execute('UPDATE "Issue" SET screenshotUrl = ?, is_unsynced = 1 WHERE _id = ?', ['https://s3/shot.png', 'r1']);

      final synced = await apply(sent, {'r1': SentRowReply(ts: _serverTs, stored: storedOf('r1'))});

      expect(synced, isFalse);
      final r = await row('r1');
      expect(r['screenshotUrl'], 'https://s3/shot.png');
      expect(r['ndoc'], 'INC-0372');
      // With the server's ts the next send is an update the server accepts,
      // and it carries the number rather than clearing it.
      expect(r['ts'], _serverTs);
      expect(r['is_unsynced'], 1);
      final next = (await readForSend()).single;
      expect(next['ts'], _serverTs);
      expect(next['ndoc'], 'INC-0372');
    });

    test('an old server, ts only: the row takes the ts as before', () async {
      await newReport('r1');
      final sent = await readForSend();

      final synced = await apply(sent, {'r1': const SentRowReply(ts: _serverTs)});

      expect(synced, isTrue);
      final r = await row('r1');
      expect(r['ts'], _serverTs);
      expect(r['ndoc'], isNull);
      expect(r['is_unsynced'], 0);
    });

    test('an old server and an edit during the send: the edit goes next as an update, not a refused second insert', () async {
      await newReport('r1');
      final sent = await readForSend();
      await db.execute('UPDATE "Issue" SET screenshotUrl = ?, is_unsynced = 1 WHERE _id = ?', ['https://s3/shot.png', 'r1']);

      final synced = await apply(sent, {'r1': const SentRowReply(ts: _serverTs)});

      expect(synced, isFalse);
      final r = await row('r1');
      expect(r['ts'], _serverTs);
      expect(r['screenshotUrl'], 'https://s3/shot.png');
      expect(r['is_unsynced'], 1);
    });

    test('a refused row is let go if unchanged, and kept for the next send if edited', () async {
      await newReport('r1');
      await newReport('r2');
      final sent = await readForSend();
      await db.execute('UPDATE "Issue" SET title = ? WHERE _id = ?', ['Points tab', 'r2']);

      final synced = await apply(sent, {
        'r1': const SentRowReply(ignored: true),
        'r2': const SentRowReply(ignored: true),
      });

      expect(synced, isFalse);
      expect((await row('r1'))['is_unsynced'], 0);
      expect((await row('r1'))['ts'], isNull);
      expect((await row('r2'))['is_unsynced'], 1);
      expect((await row('r2'))['title'], 'Points tab');
    });

    test('a row written during the send waits for the next one', () async {
      await newReport('r1');
      final sent = await readForSend();
      await newReport('r2');

      final synced = await apply(sent, {'r1': SentRowReply(ts: _serverTs, stored: storedOf('r1'))});

      expect(synced, isFalse);
      expect((await row('r1'))['is_unsynced'], 0);
      expect((await row('r2'))['is_unsynced'], 1);
      expect((await row('r2'))['ts'], isNull);
    });

    test('a column the server did not send, or a local-only one, stays as it is', () async {
      await newReport('r1');
      await db.execute('UPDATE "Issue" SET localOnly = ? WHERE _id = ?', ['draft', 'r1']);
      final sent = await readForSend();
      final stored = storedOf('r1')..remove('title');

      await apply(sent, {'r1': SentRowReply(ts: _serverTs, stored: stored)});

      final r = await row('r1');
      expect(r['title'], 'Mobile report');
      expect(r['localOnly'], 'draft');
      expect(r['ndoc'], 'INC-0372');
    });

    test('a row deleted during the send is left alone', () async {
      await newReport('r1');
      final sent = await readForSend();
      await db.execute('DELETE FROM "Issue" WHERE _id = ?', ['r1']);

      final synced = await apply(sent, {'r1': SentRowReply(ts: _serverTs, stored: storedOf('r1'))});

      expect(synced, isTrue);
      expect(await db.getAll('SELECT * FROM "Issue"'), isEmpty);
    });
  });
}
