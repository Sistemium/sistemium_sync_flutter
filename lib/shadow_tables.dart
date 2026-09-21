import 'package:sistemium_sync_flutter/sync_logger.dart';
import 'package:sqlite_async/sqlite_async.dart';

/// Shadow tables of a RulesBoard resync job.
///
/// A job downloads every table it resyncs into `<Table>_shadow` and swaps the
/// shadows in once all of them are complete. `syncing_table_shadow` lists the
/// job's tables with their download cursors. Both live in the database, so an
/// interrupted job is resumed on the next start — also after an app update
/// whose migrations changed a table the job had already made a shadow of.
class ShadowTables {
  /// Creates an empty shadow with the table's current structure.
  static Future<void> create(SqliteWriteContext tx, String table) async {
    final tableInfo = await tx.getAll('PRAGMA table_info("$table")');
    final columns = tableInfo
        .map((col) {
          final name = col['name'];
          final type = col['type'];
          final notNull = col['notnull'] == 1 ? 'NOT NULL' : '';
          final pk = col['pk'] == 1 ? 'PRIMARY KEY' : '';
          return '"$name" $type $notNull $pk';
        })
        .join(', ');

    await tx.execute('DROP TABLE IF EXISTS "${table}_shadow"');
    await tx.execute('CREATE TABLE "${table}_shadow" ($columns)');
  }

  /// Brings the shadows of a resumed job in line with the current schema.
  ///
  /// Migrations alter the table but not its shadow. A shadow made before a
  /// column was added rejects every insert, which names the current columns,
  /// so the job fails on each resume and never completes — and a pending job
  /// is always resumed before any newer RulesBoard entry is looked at.
  ///
  /// Such a shadow is rebuilt empty and downloaded again from the start: the
  /// rows it holds were fetched without the new columns. A table that has left
  /// the schema is taken out of the job.
  static Future<void> repair(
    SqliteWriteContext tx, {
    required bool Function(String table) isSyncable,
  }) async {
    final entries = await tx.getAll('SELECT entity_name FROM syncing_table_shadow');

    for (final entry in entries) {
      final table = entry['entity_name'] as String;
      final columns = await _columnNames(tx, table);

      if (columns.isEmpty || !isSyncable(table)) {
        SyncLogger.log('$table is no longer synced, removing it from the pending resync');
        await tx.execute('DROP TABLE IF EXISTS "${table}_shadow"');
        await tx.execute(
          'DELETE FROM syncing_table_shadow WHERE entity_name = ?',
          [table],
        );
        continue;
      }

      final shadowColumns = await _columnNames(tx, '${table}_shadow');
      final missing = columns.difference(shadowColumns);
      final extra = shadowColumns.difference(columns);
      if (missing.isEmpty && extra.isEmpty) continue;

      final difference = [
        if (missing.isNotEmpty) 'missing ${missing.join(', ')}',
        if (extra.isNotEmpty) 'extra ${extra.join(', ')}',
      ].join('; ');
      SyncLogger.log(
        'Shadow table ${table}_shadow does not match $table after a schema migration '
        '($difference), rebuilding it and restarting its resync',
      );
      await create(tx, table);
      await tx.execute(
        'UPDATE syncing_table_shadow SET last_received_ts = NULL WHERE entity_name = ?',
        [table],
      );
    }
  }

  static Future<Set<String>> _columnNames(SqliteReadContext tx, String table) async {
    final tableInfo = await tx.getAll('PRAGMA table_info("$table")');
    return tableInfo.map((col) => col['name'] as String).toSet();
  }
}
