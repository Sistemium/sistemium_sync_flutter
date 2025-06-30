import 'package:sqlite_async/sqlite_async.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:sistemium_sync_flutter/sync_abstract.dart';

class SyncConstants extends AbstractSyncConstants {
  @override
  final String appId = 'com.sistemium.vfs_master';
  @override
  final String serverUrl = 'http://localhost:3000';
}

class PregeneratedMigrations extends AbstractPregeneratedMigrations {
  @override
  final SqliteMigrations migrations = SqliteMigrations()
    ..add(SqliteMigration(
      1,
      (tx) async {
        await tx.execute(r'''CREATE TABLE "ServiceTask" (
  "_id" TEXT PRIMARY KEY,
  "lts" INTEGER,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "assigneeId" TEXT,
  "cts" INTEGER,
  "date" INTEGER,
  "description" TEXT,
  "processing" TEXT,
  "servicePointId" TEXT,
  "siteId" TEXT,
  "services" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "Settings" (
  "_id" TEXT PRIMARY KEY,
  "lts" INTEGER,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "userId" TEXT UNIQUE,
  "sortingOption" TEXT,
  "showCompleteTasks" INTEGER,
  "selectedDate" INTEGER,
  "selectedWarehouseMode" TEXT,
  "filterMasterId" TEXT,
  "filterSiteId" TEXT,
  "preferredNavigationApp" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "Employee" (
  "_id" TEXT PRIMARY KEY,
  "lts" INTEGER,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "name" TEXT,
  "siteId" TEXT,
  "personId" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "Site" (
  "_id" TEXT PRIMARY KEY,
  "lts" INTEGER,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "code" TEXT,
  "name" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "Person" (
  "_id" TEXT PRIMARY KEY,
  "lts" INTEGER,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "firstName" TEXT,
  "lastName" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "syncing_table" (
  "_id" TEXT PRIMARY KEY,
  "entity_name" TEXT,
  "last_received_lts" INTEGER
);''');
        await tx.executeBatch(r'''INSERT INTO "syncing_table" (_id, entity_name) VALUES(?,?) ON CONFLICT(_id) DO NOTHING;''', [["ServiceTask","ServiceTask"],["Employee","Employee"],["Site","Site"],["Person","Person"]]);
      },
    ))
    ..add(SqliteMigration(
      2,
      (tx) async {
        await tx.execute(r'''CREATE TABLE "LegalEntity" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "name" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "ServicePoint" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "address" TEXT
);''');
        await tx.executeBatch(r'''INSERT INTO "syncing_table" (_id, entity_name) VALUES(?,?) ON CONFLICT(_id) DO NOTHING;''', [["LegalEntity","LegalEntity"],["ServicePoint","ServicePoint"]]);
      },
    ))
    ..add(SqliteMigration(
      3,
      (tx) async {
        await tx.execute(r'''CREATE TABLE "ServiceContract" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "customerPersonId" TEXT,
  "customerLegalEntityId" TEXT
);''');
        await tx.executeBatch(r'''INSERT INTO "syncing_table" (_id, entity_name) VALUES(?,?) ON CONFLICT(_id) DO NOTHING;''', [["ServiceContract","ServiceContract"]]);
      },
    ))
    ..add(SqliteMigration(
      4,
      (tx) async {
        await tx.execute(r'''ALTER TABLE "ServicePoint" ADD COLUMN "currentServiceContractId" TEXT;''');
      },
    ))
    ..add(SqliteMigration(
      5,
      (tx) async {
        await tx.execute(r'''CREATE TABLE "ServiceTaskHistory" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "assigneeId" TEXT,
  "authId" TEXT,
  "comment" TEXT,
  "cts" INTEGER,
  "processing" TEXT,
  "serviceTaskId" TEXT,
  "timestamp" INTEGER,
  "type" TEXT
);''');
        await tx.executeBatch(r'''INSERT INTO "syncing_table" (_id, entity_name) VALUES(?,?) ON CONFLICT(_id) DO NOTHING;''', [["ServiceTaskHistory","ServiceTaskHistory"]]);
      },
    ))
    ..add(SqliteMigration(
      6,
      (tx) async {
        await tx.execute(r'''CREATE TABLE "User" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "email" TEXT,
  "name" TEXT,
  "phone" TEXT
);''');
        await tx.executeBatch(r'''INSERT INTO "syncing_table" (_id, entity_name) VALUES(?,?) ON CONFLICT(_id) DO NOTHING;''', [["User","User"]]);
      },
    ))
    ..createDatabase = SqliteMigration(
      6,
      (tx) async {
        await tx.execute(r'''CREATE TABLE "ServiceTask" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "assigneeId" TEXT,
  "cts" INTEGER,
  "date" INTEGER,
  "description" TEXT,
  "processing" TEXT,
  "servicePointId" TEXT,
  "siteId" TEXT,
  "services" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "Settings" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "userId" TEXT UNIQUE,
  "sortingOption" TEXT,
  "showCompleteTasks" INTEGER,
  "selectedDate" INTEGER,
  "selectedWarehouseMode" TEXT,
  "filterMasterId" TEXT,
  "filterSiteId" TEXT,
  "preferredNavigationApp" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "Employee" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "name" TEXT,
  "siteId" TEXT,
  "personId" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "Site" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "code" TEXT,
  "name" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "Person" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "firstName" TEXT,
  "lastName" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "LegalEntity" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "name" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "ServicePoint" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "address" TEXT,
  "currentServiceContractId" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "ServiceContract" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "customerPersonId" TEXT,
  "customerLegalEntityId" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "ServiceTaskHistory" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "assigneeId" TEXT,
  "authId" TEXT,
  "comment" TEXT,
  "cts" INTEGER,
  "processing" TEXT,
  "serviceTaskId" TEXT,
  "timestamp" INTEGER,
  "type" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "User" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "id" TEXT,
  "email" TEXT,
  "name" TEXT,
  "phone" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "syncing_table" (
  "_id" TEXT PRIMARY KEY,
  "entity_name" TEXT,
  "last_received_lts" TIMESTAMP
);''');
        await tx.executeBatch(r'''INSERT INTO "syncing_table" (_id, entity_name) VALUES(?, ?) ON CONFLICT(_id) DO NOTHING;''', [["ServiceTask","ServiceTask"],["Employee","Employee"],["Site","Site"],["Person","Person"],["LegalEntity","LegalEntity"],["ServicePoint","ServicePoint"],["ServiceContract","ServiceContract"],["ServiceTaskHistory","ServiceTaskHistory"],["User","User"]]);
      },
    );
}

class Servicetask {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? assigneeId;
  final DateTime? cts;
  final DateTime? date;
  final String? description;
  final String? processing;
  final String? servicePointId;
  final String? siteId;
  final String? services;

  Servicetask({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.assigneeId,
    this.cts,
    this.date,
    this.description,
    this.processing,
    this.servicePointId,
    this.siteId,
    this.services,
  }) : _id = internal_id;

  factory Servicetask.fromMap(Map<String, dynamic> map) {
    return Servicetask(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      assigneeId: map['assigneeId']?.toString(),
      cts: map['cts'] != null ? DateTime.tryParse(map['cts'].toString()) : null,
      date: map['date'] != null ? DateTime.tryParse(map['date'].toString()) : null,
      description: map['description']?.toString(),
      processing: map['processing']?.toString(),
      servicePointId: map['servicePointId']?.toString(),
      siteId: map['siteId']?.toString(),
      services: map['services']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'assigneeId': assigneeId,
      'cts': cts?.toIso8601String(),
      'date': date?.toIso8601String(),
      'description': description,
      'processing': processing,
      'servicePointId': servicePointId,
      'siteId': siteId,
      'services': services,
    };
  }
}

class Settings {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? userId;
  final String? sortingOption;
  final bool? showCompleteTasks;
  final DateTime? selectedDate;
  final String? selectedWarehouseMode;
  final String? filterMasterId;
  final String? filterSiteId;
  final String? preferredNavigationApp;

  Settings({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.userId,
    this.sortingOption,
    this.showCompleteTasks,
    this.selectedDate,
    this.selectedWarehouseMode,
    this.filterMasterId,
    this.filterSiteId,
    this.preferredNavigationApp,
  }) : _id = internal_id;

  factory Settings.fromMap(Map<String, dynamic> map) {
    return Settings(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      userId: map['userId']?.toString(),
      sortingOption: map['sortingOption']?.toString(),
      showCompleteTasks: map['showCompleteTasks'] == true || map['showCompleteTasks'] == 1,
      selectedDate: map['selectedDate'] != null ? DateTime.tryParse(map['selectedDate'].toString()) : null,
      selectedWarehouseMode: map['selectedWarehouseMode']?.toString(),
      filterMasterId: map['filterMasterId']?.toString(),
      filterSiteId: map['filterSiteId']?.toString(),
      preferredNavigationApp: map['preferredNavigationApp']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'userId': userId,
      'sortingOption': sortingOption,
      'showCompleteTasks': showCompleteTasks == true ? 1 : 0,
      'selectedDate': selectedDate?.toIso8601String(),
      'selectedWarehouseMode': selectedWarehouseMode,
      'filterMasterId': filterMasterId,
      'filterSiteId': filterSiteId,
      'preferredNavigationApp': preferredNavigationApp,
    };
  }
}

class Employee {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? name;
  final String? siteId;
  final String? personId;

  Employee({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.name,
    this.siteId,
    this.personId,
  }) : _id = internal_id;

  factory Employee.fromMap(Map<String, dynamic> map) {
    return Employee(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      name: map['name']?.toString(),
      siteId: map['siteId']?.toString(),
      personId: map['personId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'name': name,
      'siteId': siteId,
      'personId': personId,
    };
  }
}

class Site {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? code;
  final String? name;

  Site({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.code,
    this.name,
  }) : _id = internal_id;

  factory Site.fromMap(Map<String, dynamic> map) {
    return Site(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      code: map['code']?.toString(),
      name: map['name']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'code': code,
      'name': name,
    };
  }
}

class Person {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? firstName;
  final String? lastName;

  Person({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.firstName,
    this.lastName,
  }) : _id = internal_id;

  factory Person.fromMap(Map<String, dynamic> map) {
    return Person(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      firstName: map['firstName']?.toString(),
      lastName: map['lastName']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
    };
  }
}

class Legalentity {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? name;

  Legalentity({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.name,
  }) : _id = internal_id;

  factory Legalentity.fromMap(Map<String, dynamic> map) {
    return Legalentity(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      name: map['name']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'name': name,
    };
  }
}

class Servicepoint {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? address;
  final String? currentServiceContractId;

  Servicepoint({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.address,
    this.currentServiceContractId,
  }) : _id = internal_id;

  factory Servicepoint.fromMap(Map<String, dynamic> map) {
    return Servicepoint(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      address: map['address']?.toString(),
      currentServiceContractId: map['currentServiceContractId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'address': address,
      'currentServiceContractId': currentServiceContractId,
    };
  }
}

class Servicecontract {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? customerPersonId;
  final String? customerLegalEntityId;

  Servicecontract({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.customerPersonId,
    this.customerLegalEntityId,
  }) : _id = internal_id;

  factory Servicecontract.fromMap(Map<String, dynamic> map) {
    return Servicecontract(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      customerPersonId: map['customerPersonId']?.toString(),
      customerLegalEntityId: map['customerLegalEntityId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'customerPersonId': customerPersonId,
      'customerLegalEntityId': customerLegalEntityId,
    };
  }
}

class Servicetaskhistory {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? assigneeId;
  final String? authId;
  final String? comment;
  final DateTime? cts;
  final String? processing;
  final String? serviceTaskId;
  final DateTime? timestamp;
  final String? type;

  Servicetaskhistory({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.assigneeId,
    this.authId,
    this.comment,
    this.cts,
    this.processing,
    this.serviceTaskId,
    this.timestamp,
    this.type,
  }) : _id = internal_id;

  factory Servicetaskhistory.fromMap(Map<String, dynamic> map) {
    return Servicetaskhistory(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      assigneeId: map['assigneeId']?.toString(),
      authId: map['authId']?.toString(),
      comment: map['comment']?.toString(),
      cts: map['cts'] != null ? DateTime.tryParse(map['cts'].toString()) : null,
      processing: map['processing']?.toString(),
      serviceTaskId: map['serviceTaskId']?.toString(),
      timestamp: map['timestamp'] != null ? DateTime.tryParse(map['timestamp'].toString()) : null,
      type: map['type']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'assigneeId': assigneeId,
      'authId': authId,
      'comment': comment,
      'cts': cts?.toIso8601String(),
      'processing': processing,
      'serviceTaskId': serviceTaskId,
      'timestamp': timestamp?.toIso8601String(),
      'type': type,
    };
  }
}

class User {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? id;
  final String? email;
  final String? name;
  final String? phone;

  User({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.email,
    this.name,
    this.phone,
  }) : _id = internal_id;

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      id: map['id']?.toString(),
      email: map['email']?.toString(),
      name: map['name']?.toString(),
      phone: map['phone']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
    };
  }
}

class SyncingTable {
  final String? _id;
  final String? entity_name;
  final String? last_received_lts;

  SyncingTable({
    String? internal_id,
    this.entity_name,
    this.last_received_lts,
  }) : _id = internal_id;

  factory SyncingTable.fromMap(Map<String, dynamic> map) {
    return SyncingTable(
      internal_id: map['_id']?.toString(),
      entity_name: map['entity_name']?.toString(),
      last_received_lts: map['last_received_lts']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'entity_name': entity_name,
      'last_received_lts': last_received_lts,
    };
  }
}

class MetaEntity extends AbstractMetaEntity {
  @override
  final Map<String, String> syncableColumnsString = {
    'ServiceTask': '_id, lts, is_deleted, id, assigneeId, cts, date, description, processing, servicePointId, siteId, services',
    'Settings': '_id, lts, is_deleted, userId, sortingOption, showCompleteTasks, selectedDate, selectedWarehouseMode, filterMasterId, filterSiteId, preferredNavigationApp',
    'Employee': '_id, lts, is_deleted, id, name, siteId, personId',
    'Site': '_id, lts, is_deleted, id, code, name',
    'Person': '_id, lts, is_deleted, id, firstName, lastName',
    'LegalEntity': '_id, lts, is_deleted, id, name',
    'ServicePoint': '_id, lts, is_deleted, id, address, currentServiceContractId',
    'ServiceContract': '_id, lts, is_deleted, id, customerPersonId, customerLegalEntityId',
    'ServiceTaskHistory': '_id, lts, is_deleted, id, assigneeId, authId, comment, cts, processing, serviceTaskId, timestamp, type',
    'User': '_id, lts, is_deleted, id, email, name, phone',
    'syncing_table': '_id, entity_name, last_received_lts',
  };
  @override
  final Map<String, List> syncableColumnsList = {
    'ServiceTask': ["_id","lts","is_deleted","id","assigneeId","cts","date","description","processing","servicePointId","siteId","services"],
    'Settings': ["_id","lts","is_deleted","userId","sortingOption","showCompleteTasks","selectedDate","selectedWarehouseMode","filterMasterId","filterSiteId","preferredNavigationApp"],
    'Employee': ["_id","lts","is_deleted","id","name","siteId","personId"],
    'Site': ["_id","lts","is_deleted","id","code","name"],
    'Person': ["_id","lts","is_deleted","id","firstName","lastName"],
    'LegalEntity': ["_id","lts","is_deleted","id","name"],
    'ServicePoint': ["_id","lts","is_deleted","id","address","currentServiceContractId"],
    'ServiceContract': ["_id","lts","is_deleted","id","customerPersonId","customerLegalEntityId"],
    'ServiceTaskHistory': ["_id","lts","is_deleted","id","assigneeId","authId","comment","cts","processing","serviceTaskId","timestamp","type"],
    'User': ["_id","lts","is_deleted","id","email","name","phone"],
    'syncing_table': ["_id","entity_name","last_received_lts"],
  };
}

