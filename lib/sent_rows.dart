import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:sqlite_async/sqlite_async.dart';

/// What the server answered about one row it was sent (POST /data).
class SentRowReply {
  const SentRowReply({this.ts, this.stored, this.ignored = false});

  /// The row's ts on the server after the write.
  final String? ts;

  /// The row as the server stored it, in the shape GET /data sends rows: what a
  /// hook or the server filled (a document number, cts) as well as what was
  /// sent. A server older than this field sends none.
  final Map<String, dynamic>? stored;

  /// The server refused the row (a conflict, no permission).
  final bool ignored;
}

/// Brings the rows a send posted in line with what the server stored.
///
/// The server may fill fields itself when it writes a row. A copy that takes
/// only the new ts holds that version with those fields still empty, and its
/// next save goes through the ts check and clears them on the server. So each
/// replied row takes the stored values with the ts.
class SentRows {
  SentRows._();

  static const _equality = DeepCollectionEquality();

  /// The replies in a POST /data response body, by `_id`. A body that can't be
  /// read gives none, as from an old server.
  static Map<String, SentRowReply> parseReplies(String body) {
    final replies = <String, SentRowReply>{};
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return replies;
    }
    if (decoded is! Map || decoded['resuts'] is! List) return replies;
    for (final result in decoded['resuts'] as List) {
      if (result is! Map || result['_id'] == null) continue;
      final stored = result['stored'];
      replies[result['_id'].toString()] = SentRowReply(
        ts: result['ts']?.toString(),
        stored: stored is Map ? Map<String, dynamic>.from(stored) : null,
        ignored: result['ignored'] == true,
      );
    }
    return replies;
  }

  /// Applies [replies] to the rows of [tableName] that were [sent].
  ///
  /// A row unchanged since it was read for the send takes the server's ts and
  /// stored values and is synced. A row edited during the send keeps those edits
  /// and stays unsynced, but takes the ts and the stored values of every column
  /// it didn't edit: its next send is then an update the server accepts, rather
  /// than a second insert it refuses. A refused or unanswered row is let go if
  /// unchanged, as before, and stays unsynced if edited.
  ///
  /// [columns] are the table's synced columns, `_id` and `ts` among them.
  /// Returns whether every unsynced row of the table is now synced.
  static Future<bool> apply(
    SqliteWriteContext tx, {
    required String tableName,
    required List<String> columns,
    required List<Map<String, Object?>> sent,
    required Map<String, SentRowReply> replies,
  }) async {
    final current = await tx.getAll(
      'select ${columns.map((c) => '"$c"').join(', ')} from "$tableName" where is_unsynced = 1',
    );
    final currentById = <String, Map<String, Object?>>{
      for (final row in current) row['_id'].toString(): Map<String, Object?>.from(row),
    };
    var stillUnsynced = currentById.length;

    for (final sentRow in sent) {
      final id = sentRow['_id'].toString();
      final now = currentById[id];
      if (now == null) continue; // deleted, or synced meanwhile
      final edited = !_equality.equals(sentRow, now);
      final reply = replies[id];

      final values = <String, Object?>{};
      if (reply != null && !reply.ignored) {
        final stored = reply.stored;
        if (stored != null) {
          for (final column in columns) {
            if (column == '_id' || !stored.containsKey(column)) continue;
            // Edited during the send: the edit wins, and goes next time.
            if (edited && !_equality.equals(sentRow[column], now[column])) continue;
            values[column] = stored[column];
          }
        }
        if (reply.ts != null) values['ts'] = reply.ts;
      }

      if (edited) {
        if (values.isNotEmpty) await _set(tx, tableName, id, values);
        continue;
      }
      values['is_unsynced'] = 0;
      await _set(tx, tableName, id, values);
      stillUnsynced--;
    }
    return stillUnsynced == 0;
  }

  static Future<void> _set(
    SqliteWriteContext tx,
    String tableName,
    String id,
    Map<String, Object?> values,
  ) =>
      tx.execute(
        'UPDATE "$tableName" SET ${values.keys.map((c) => '"$c" = ?').join(', ')} WHERE _id = ?',
        [...values.values, id],
      );
}
