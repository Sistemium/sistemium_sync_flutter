import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

void main(List<String> args) async {
  if (args.length < 2 || args.length > 4) {
    print('Usage: dart sync_generator.dart <server_url> <app_id> [auth_token] [output_path]');
    exit(1);
  }

  String serverUrl = args[0];
  final targetAppId = args[1];
  final authToken = args.length > 2 ? args[2] : null;
  final outputFilePath = args.length > 3 ? args[3] : 'pregenerated.dart';

  if (serverUrl.endsWith('/')) {
    serverUrl = serverUrl.substring(0, serverUrl.length - 1);
  }
  final modelsUrl = Uri.parse('$serverUrl/models');
  final constantsServerUrl = args[0];

  try {
    print(modelsUrl);
    print(authToken != null ? {'Authorization': authToken} : null);
    final headers = <String, String>{'appid': targetAppId};
    if (authToken != null) headers['Authorization'] = authToken;

    final response = await http.get(
      modelsUrl,
      headers: headers,
    );
    if (response.statusCode != 200) {
      print('Error fetching data from $modelsUrl: ${response.statusCode}');
      print('Response body: ${response.body}');
      exit(1);
    }

    final List<dynamic> allModels = jsonDecode(response.body);
    final List<dynamic> appModels = allModels
        .where((m) => m['app_id'] == targetAppId && m['version'] is int)
        .toList();
    if (appModels.isEmpty) {
      print('Error: No valid models found for app_id "$targetAppId".');
      exit(1);
    }

    appModels.sort(
      (a, b) => (a['version'] as int).compareTo(b['version'] as int),
    );
    final latestModel = appModels.last;
    final int latestVersion = latestModel['version'];

    final List<dynamic> latestClientCreateDdls =
        latestModel['client_create'] is List
        ? List<dynamic>.from(latestModel['client_create'])
        : [];
    if (latestClientCreateDdls.isEmpty) {
      print(
        'Error: client_create is null or empty for the latest version ($latestVersion) of app_id "$targetAppId".',
      );
      exit(1);
    }

    final modelDefaults = latestModel['model_with_client_defaults'];
    if (modelDefaults == null || modelDefaults is! Map<String, dynamic>) {
      print(
        'Error: "model_with_client_defaults" is missing or invalid in the latest version ($latestVersion) for app_id "$targetAppId".',
      );
      exit(1);
    }

    final List<dynamic> entities = modelDefaults['entities'] is List
        ? List<dynamic>.from(modelDefaults['entities'])
        : [];
    final List<dynamic> syncableEntities = entities
        .whereType<Map<String, dynamic>>()
        .where((entity) => entity['is_syncable'] == true)
        .toList();

    final buffer = StringBuffer();

    buffer.writeln("import 'package:sqlite_async/sqlite_async.dart';");
    buffer.writeln(
      "import 'package:sistemium_sync_flutter/sync_abstract.dart';",
    );
    buffer.writeln();

    buffer.writeln('class SyncConstants extends AbstractSyncConstants {');
    buffer.writeln("  @override");
    buffer.writeln("  final String appId = '$targetAppId';");
    buffer.writeln("  @override");
    buffer.writeln("  final String serverUrl = '$constantsServerUrl';");
    buffer.writeln('}');
    buffer.writeln();

    buffer.writeln(
      'class PregeneratedMigrations extends AbstractPregeneratedMigrations {',
    );
    buffer.writeln('  @override');
    buffer.writeln('  final SqliteMigrations migrations = SqliteMigrations()');
    for (final modelData in appModels) {
      final int currentVersion = modelData['version'];
      final List<dynamic> clientMigrationDdls =
          modelData['client_migration'] is List
          ? List<dynamic>.from(modelData['client_migration'])
          : [];
      buffer.writeln('    ..add(SqliteMigration(');
      buffer.writeln('      $currentVersion,');
      buffer.writeln('      (tx) async {');
      generateSqlExecutionCode(
        clientMigrationDdls,
        buffer,
        8,
        "client_migration",
        currentVersion,
      );
      buffer.writeln('      },');
      buffer.writeln('    ))');
    }
    buffer.writeln('    ..createDatabase = SqliteMigration(');
    buffer.writeln('      $latestVersion,');
    buffer.writeln('      (tx) async {');
    generateSqlExecutionCode(
      latestClientCreateDdls,
      buffer,
      8,
      "client_create",
      latestVersion,
    );
    buffer.writeln('      },');
    buffer.writeln('    );');
    buffer.writeln('}');
    buffer.writeln();

    buffer.writeln('class MetaEntity extends AbstractMetaEntity {');
    buffer.writeln('  @override');
    buffer.writeln('  final Map<String, String> syncableColumnsString = {');
    for (final entityData in syncableEntities) {
      if (entityData is! Map<String, dynamic>) continue;
      final tableName = entityData['name'] as String?;
      final fields = entityData['fields'] is List
          ? List<dynamic>.from(entityData['fields'])
          : [];
      if (tableName == null || tableName.isEmpty || fields.isEmpty) continue;

      final columnNames = fields
          .map((f) => f is Map<String, dynamic> ? f['name'] as String? : null)
          .where(
            (name) => name != null && name.isNotEmpty && name != 'is_unsynced',
          )
          .toList();
      buffer.writeln("    '$tableName': '${columnNames.join(', ')}',");
    }
    buffer.writeln('  };');
    buffer.writeln('  @override');
    buffer.writeln('  final Map<String, List> syncableColumnsList = {');
    for (final entityData in syncableEntities) {
      if (entityData is! Map<String, dynamic>) continue;
      final tableName = entityData['name'] as String?;
      final fields = entityData['fields'] is List
          ? List<dynamic>.from(entityData['fields'])
          : [];
      if (tableName == null || tableName.isEmpty || fields.isEmpty) continue;

      final columnNames = fields
          .map((f) => f is Map<String, dynamic> ? f['name'] as String? : null)
          .where(
            (name) => name != null && name.isNotEmpty && name != 'is_unsynced',
          )
          .toList();
      buffer.writeln("    '$tableName': ${jsonEncode(columnNames)},");
    }
    buffer.writeln('  };');
    buffer.writeln('}');
    buffer.writeln();

    final outputFile = File(outputFilePath);
    await outputFile.writeAsString(buffer.toString());
    print('Successfully generated $outputFilePath');
  } catch (e, s) {
    print('An error occurred: $e');
    print('Stack trace:\n$s');
    exit(1);
  }
}

void generateSqlExecutionCode(
  List<dynamic> ddlObjects,
  StringBuffer buffer,
  int indentLevel,
  String context,
  int version,
) {
  final indent = ' ' * indentLevel;
  if (ddlObjects.isEmpty) return;
  for (final ddlObject in ddlObjects) {
    if (ddlObject is! Map<String, dynamic>) {
      print(
        'Warning: Invalid DDL object format in $context for version $version: $ddlObject',
      );
      continue;
    }
    final type = ddlObject['type'] as String?;
    final sql = ddlObject['sql'] as String?;
    if (sql == null || sql.trim().isEmpty) {
      if (ddlObjects.length == 1) continue;
      print(
        'Warning: Missing or empty SQL for DDL object in $context for version $version: $ddlObject',
      );
      continue;
    }
    final escapedSql = escapeSqlString(sql.trim());
    if (type == 'execute') {
      buffer.writeln("${indent}await tx.execute(r'''$escapedSql''');");
    } else if (type == 'batch') {
      final params = ddlObject['params'];
      if (params is List && params.isNotEmpty) {
        final paramsLiteral = jsonEncode(params);
        buffer.writeln(
          "${indent}await tx.executeBatch(r'''$escapedSql''', $paramsLiteral);",
        );
      } else {
        print(
          'Warning: Missing, invalid, or empty "params" for batch operation in $context for version $version: $ddlObject. Falling back to tx.execute.',
        );
        buffer.writeln("${indent}await tx.execute(r'''$escapedSql''');");
      }
    } else {
      print(
        'Warning: Unknown DDL type "$type" in $context for version $version: $ddlObject. Defaulting to tx.execute.',
      );
      buffer.writeln("${indent}await tx.execute(r'''$escapedSql''');");
    }
  }
}

String escapeSqlString(String sql) => sql.replaceAll("'''", "'''\"'\"'\"'''");
