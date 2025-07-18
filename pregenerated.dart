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
      12,
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
  "phone" TEXT,
  "isAdmin" INTEGER
);''');
        await tx.execute(r'''CREATE TABLE "RulesBoard" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "userId" TEXT,
  "cts" INTEGER,
  "fullResyncCollections" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "syncing_table" (
  "_id" TEXT PRIMARY KEY,
  "entity_name" TEXT,
  "last_received_lts" TIMESTAMP
);''');
        await tx.executeBatch(r'''INSERT INTO "syncing_table" (_id, entity_name) VALUES(?,?) ON CONFLICT(_id) DO NOTHING;''', [["eeda4a6faa72cf687f6e3eb1","ServiceTask"],["70ef1c79e5a39a8cf086856a","Employee"],["8c7f45b71325562874bb404e","Site"],["5c7fc216f6714b6a74cf8ade","Person"],["a0b5e2706a8f4aea0c1d90f0","LegalEntity"],["fc18b9b0b20ec9df3ce841ac","ServicePoint"],["7e38810eb09957175458e843","ServiceContract"],["c56e4257144a6287c0116259","ServiceTaskHistory"],["b39f1d3c806e05bd1a54d25a","User"],["d1add9b6c3ce12ebdb6a52b3","RulesBoard"]]);
      },
    ))
    ..createDatabase = SqliteMigration(
      12,
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
  "phone" TEXT,
  "isAdmin" INTEGER
);''');
        await tx.execute(r'''CREATE TABLE "RulesBoard" (
  "_id" TEXT PRIMARY KEY,
  "lts" TIMESTAMP,
  "is_deleted" INTEGER,
  "is_unsynced" INTEGER,
  "userId" TEXT,
  "cts" INTEGER,
  "fullResyncCollections" TEXT
);''');
        await tx.execute(r'''CREATE TABLE "syncing_table" (
  "_id" TEXT PRIMARY KEY,
  "entity_name" TEXT,
  "last_received_lts" TIMESTAMP
);''');
        await tx.executeBatch(r'''INSERT INTO "syncing_table" (_id, entity_name) VALUES(?, ?) ON CONFLICT(_id) DO NOTHING;''', [["bd3fd09007f291515831103e","ServiceTask"],["cc7cb62726f63cad97ac5840","Employee"],["8887bd4f97baac4de5f762aa","Site"],["467dbda4e58c8615f028611e","Person"],["cbc570abc322356f28900d07","LegalEntity"],["1b270a2ca608502a872a6d08","ServicePoint"],["55902e2675e03fcdcf2c9411","ServiceContract"],["f525afe885c4dd06b7c1d0eb","ServiceTaskHistory"],["d10ac7231f475439105476de","User"],["5747c60767b921e91e7e59ac","RulesBoard"]]);
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
  final bool? isAdmin;

  User({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.id,
    this.email,
    this.name,
    this.phone,
    this.isAdmin,
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
      isAdmin: map['isAdmin'] == true || map['isAdmin'] == 1,
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
      'isAdmin': isAdmin == true ? 1 : 0,
    };
  }
}

class Rulesboard {
  final String? _id;
  final String? lts;
  final int? is_deleted;
  final int? is_unsynced;
  final String? userId;
  final DateTime? cts;
  final String? fullResyncCollections;

  Rulesboard({
    String? internal_id,
    this.lts,
    this.is_deleted,
    this.is_unsynced,
    this.userId,
    this.cts,
    this.fullResyncCollections,
  }) : _id = internal_id;

  factory Rulesboard.fromMap(Map<String, dynamic> map) {
    return Rulesboard(
      internal_id: map['_id']?.toString(),
      lts: map['lts']?.toString(),
      is_deleted: map['is_deleted'] != null ? (int.tryParse(map['is_deleted'].toString()) ?? (map['is_deleted'] is num ? map['is_deleted'].toint() : null)) : null,
      is_unsynced: map['is_unsynced'] != null ? (int.tryParse(map['is_unsynced'].toString()) ?? (map['is_unsynced'] is num ? map['is_unsynced'].toint() : null)) : null,
      userId: map['userId']?.toString(),
      cts: map['cts'] != null ? DateTime.tryParse(map['cts'].toString()) : null,
      fullResyncCollections: map['fullResyncCollections']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      '_id': _id,
      'lts': lts,
      'is_deleted': is_deleted,
      'is_unsynced': is_unsynced,
      'userId': userId,
      'cts': cts?.toIso8601String(),
      'fullResyncCollections': fullResyncCollections,
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
    'User': '_id, lts, is_deleted, id, email, name, phone, isAdmin',
    'RulesBoard': '_id, lts, is_deleted, userId, cts, fullResyncCollections',
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
    'User': ["_id","lts","is_deleted","id","email","name","phone","isAdmin"],
    'RulesBoard': ["_id","lts","is_deleted","userId","cts","fullResyncCollections"],
    'syncing_table': ["_id","entity_name","last_received_lts"],
  };
}

