# Sistemium Sync Flutter - Library Documentation

## Project Overview

**sistemium_sync_flutter** is a sophisticated Flutter/Dart library (v2.5.7) that provides offline-first data synchronization between Flutter applications and the Sistemium backend ecosystem. It manages local SQLite databases, orchestrates bidirectional sync, and provides reactive streams for real-time UI updates.

**Package Type:** Flutter library
**Version:** 2.5.7
**Minimum Dart:** >=3.9.2
**Minimum Flutter:** >=3.35.5

## Core Purpose

This library serves as a complete synchronization engine that:
- Manages local SQLite databases for offline-first data storage
- Syncs data bidirectionally with `sistemium_sync_service` backend
- Provides real-time updates through Server-Sent Events (SSE)
- Implements permission-based data reset mechanisms (RulesBoard)
- Exposes complete sqlite_async API through safe wrapper methods
- Protects server-controlled fields (ts) from client manipulation

## Architecture Overview

```
┌─────────────────────────────────────┐
│   Flutter UI Layer (ChangeNotifier) │
│   - watch() returns reactive Stream │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   BackendNotifier (Orchestrator)    │
│   - Wrapper for sqlite_async API    │
│   - Sync Queue Management           │
│   - SSE Event Handling              │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   SQLite Database (sqlite_async)    │
│   - Local data persistence          │
│   - Transaction support             │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   HTTP/SSE Communication Layer      │
│   - Backend API endpoints           │
│   - Event streaming                 │
└─────────────────────────────────────┘
```

## API Reference

### Database Initialization

```dart
final backend = BackendNotifier(
  abstractPregeneratedMigrations: PregeneratedMigrations(),
  abstractSyncConstants: SyncConstants(),
  abstractMetaEntity: MetaEntity(),
);

await backend.initDb(
  serverUrl: 'https://api.example.com',
  userId: userId,
  authToken: authToken,
);
```

### Query Methods

#### Get All Rows
```dart
// Without parameters
final rows = await backend.getAll('SELECT * FROM Article');

// With parameter binding (secure)
final rows = await backend.getAll(
  'SELECT * FROM Article WHERE id = ?',
  [articleId]
);
```

#### Get Single Row
```dart
// get() - throws if not found
final user = await backend.get(
  'SELECT * FROM User WHERE id = ?',
  [userId]
);

// getOptional() - returns null if not found
final settings = await backend.getOptional(
  'SELECT * FROM Settings WHERE userId = ?',
  [userId]
);
```

#### Watch (Reactive Queries)
```dart
// Watch without parameters
final stream = backend.watch(
  'SELECT * FROM Article',
  triggerOnTables: ['Article'],
);

// Watch with parameters
final stream = backend.watch(
  'SELECT * FROM Task WHERE userId = ?',
  parameters: [userId],
  triggerOnTables: ['Task'],
);

// Use in UI
StreamBuilder<List>(
  stream: stream,
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return ListView.builder(...);
    }
    return CircularProgressIndicator();
  },
)
```

### Write Methods

#### Execute Statement
```dart
// Without parameters
await backend.execute('DELETE FROM Cache');

// With parameters (secure)
await backend.execute(
  'DELETE FROM Task WHERE id = ?',
  [taskId]
);
```

#### Batch Execute
```dart
await backend.executeBatch(
  'INSERT INTO Article(name, price) VALUES (?, ?)',
  [
    ['Product 1', 10.99],
    ['Product 2', 15.49],
    ['Product 3', 8.99],
  ]
);
```

#### High-Level Write (with ts protection)
```dart
await backend.write(
  tableName: 'ServiceTask',
  data: {
    '_id': taskId,
    'processing': 'finished',
    'description': 'Task completed',
    'ts': 'ignored-value',  // ❌ Automatically removed!
  },
);
// Only server can set ts field
```

### Transaction Methods

#### Read Transaction
```dart
final result = await backend.readTransaction((tx) async {
  final user = await tx.get('SELECT * FROM User WHERE id = ?', [userId]);
  final tasks = await tx.getAll('SELECT * FROM Task WHERE userId = ?', [userId]);
  return {'user': user, 'tasks': tasks};
});
```

#### Write Transaction
```dart
await backend.writeTransaction(
  affectedTables: ['ServiceTask', 'ServiceTaskHistory'],
  callback: (tx) async {
    await tx.execute(
      'UPDATE ServiceTask SET processing = ? WHERE id = ?',
      ['finished', taskId]
    );
    await tx.execute(
      'INSERT INTO ServiceTaskHistory(taskId, action, ts) VALUES (?, ?, ?)',
      [taskId, 'completed', DateTime.now().toIso8601String()]
    );
  },
);
```

### Utility Methods

#### Check Initialization Status
```dart
if (backend.isInitialized) {
  // Database is ready
}
```

#### Cleanup
```dart
await backend.deinitDb();
```

## Security Features

### ts Field Protection

The `write()` method automatically removes the `ts` field from user data:

```dart
// User attempts to override ts
await backend.write(
  tableName: 'Task',
  data: {
    '_id': '123',
    'name': 'My Task',
    'ts': '2025-01-01T00:00:00.000Z',  // ❌ REMOVED automatically
  },
);

// Actual SQL executed:
// INSERT INTO Task (_id, name, is_unsynced) VALUES (?, ?, 1)
// Only server can assign ts via sync mechanism
```

**Note:** Raw SQL methods (`execute`, `executeBatch`, transactions) do NOT sanitize - users are responsible for their own SQL.

## Data Synchronization

### Delta Sync with Timestamps

```
1. Client: GET /data?name=Task&ts=2025-01-15T10:30:00.000Z
2. Server: Returns only documents with ts > provided timestamp
3. Client: Upserts received data into local SQLite
4. Client: Updates last_received_ts in syncing_table
```

**Benefits:**
- Minimal bandwidth (only changed data)
- Handles offline periods gracefully
- Pagination support (10,000 records per page)
- Resumable sync after interruptions

### Bidirectional Sync

**Downstream (Server → Client):**
- Automatic via SSE event notifications
- Client receives "data: TableName" event
- Triggers background sync for that table

**Upstream (Client → Server):**
- Triggered when `is_unsynced = 1` records exist
- POST to `/data` endpoint with changes
- Race condition protection via deep equality check
- Server returns new ts values for each record

### Real-Time Updates (SSE)

```dart
// Library maintains persistent connection
GET /events
Accept: text/event-stream

// Server sends:
data: ServiceTask
data: Article

// Client automatically queues sync for updated tables
```

### Permission-Based Resync (RulesBoard)

When backend permissions change:

```
1. Server sends SSE event: "data: RulesBoard"
2. Client syncs RulesBoard table
3. Client reads fullResyncCollections field
4. For each table needing resync:
   - Create shadow table
   - Download fresh data with current permissions
   - Replace original table atomically
   - Delete shadow table
5. User now sees only permitted data
```

## Code Generation

Generate database schema from backend:

```bash
dart run sistemium_sync_flutter:sync_generator <server_url> <app_id> [auth_token] [output_path]
```

**Generated Files:**
- `SyncConstants` - App ID configuration
- `PregeneratedMigrations` - SQLite schema migrations
- `MetaEntity` - Syncable column definitions

## Integration Guide

### 1. Add Dependency

```yaml
dependencies:
  sistemium_sync_flutter:
    git:
      url: https://github.com/Sistemium/sistemium_sync_flutter.git
      ref: 'latest-commit-hash'
```

### 2. Generate Schema

```bash
dart run sistemium_sync_flutter:sync_generator \
  https://your-server.com/api \
  com.yourcompany.yourapp \
  your-auth-token \
  lib/generated/pregenerated.dart
```

### 3. Initialize Backend

```dart
final backend = BackendNotifier(
  abstractPregeneratedMigrations: PregeneratedMigrations(),
  abstractSyncConstants: SyncConstants(),
  abstractMetaEntity: MetaEntity(),
);

await backend.initDb(
  serverUrl: serverUrl,
  userId: userId,
  authToken: authToken,
);
```

### 4. Wrap App
```dart
BackendWrapper(
  notifier: backend,
  child: MaterialApp(...)
)
```

### 5. Use in Widgets

```dart
final backend = BackendWrapper.of(context);

// Reactive data
Stream<List> dataStream = backend.watch(
  'SELECT * FROM Task WHERE userId = ?',
  parameters: [userId],
  triggerOnTables: ['Task'],
);

// Write data
await backend.write(
  tableName: 'Task',
  data: {'_id': taskId, 'name': 'New Task'},
);
```

## Backend Integration

### Required Endpoints

- `GET /models` - Schema definitions (for code generation)
- `GET /latest-ts?name=Table` - Latest sync timestamp
- `GET /data?name=Table&ts=...&pageSize=10000` - Fetch data delta
- `POST /data` - Send local changes
- `GET /events` (SSE) - Real-time change notifications

### Authentication Headers

```
appid: your-app-id
authorization: your-auth-token
```

### Response Format (POST /data)

```json
{
  "resuts": [
    {
      "message": "Document inserted",
      "_id": "507f1f77bcf86cd799439011",
      "ts": "2025-01-15T12:34:56.789Z-0000000001",
      "doc": {...}
    }
  ]
}
```

## Error Handling

**Retry Mechanisms:**
- Table registration: 30-second retry
- Unsynced send: 3 retry attempts
- SSE connection: 5-second reconnect delay

**Data Integrity:**
- Transaction-based operations
- Race condition detection
- Deep equality checks before marking synced

## Performance

**Optimizations:**
- Efficient delta sync minimizes bandwidth
- SQLite for fast local queries
- Background sync queue prevents UI blocking
- Pagination for large datasets

**Database Location:**
```
{documentsDirectory}/{userId}/sync.db
```

## Known Limitations

1. Single database per userId
2. Fixed page size (10,000 records)
3. RulesBoard resync replaces entire tables
4. No explicit offline/online detection

## Version History

**v2.5.7** - Complete sqlite_async API wrappers, ts field protection
**v2.5.6** - Simplified wrapper methods to match sqlite_async exactly
**v2.5.5** - Added isInitialized getter
**v2.5.4** - Added complete wrapper methods (execute, executeBatch, etc.)
**v2.5.3** - SECURITY: Remove ts field from user data in write()
**v2.5.2** - Update local ts values from server POST responses
**v2.3.1** - Fixed sync_generator to filter is_syncable entities
**v2.0.2** - Fixed RulesBoard empty collection handling
**v1.6.0** - BREAKING: Renamed `lts` → `ts` throughout

## Dependencies

- `flutter` - Flutter framework
- `http: 1.5.0` - HTTP client
- `sqlite_async: 0.12.1` - Async SQLite database
- `path_provider: 2.1.5` - Platform file paths
- `objectid: 4.0.1` - MongoDB ObjectId generation
- `collection: 1.19.1` - Collection utilities

## Summary

`sistemium_sync_flutter` provides a complete, production-ready synchronization engine for offline-first Flutter applications. It abstracts away the complexity of data synchronization, permission management, and real-time updates, exposing a clean, safe API that matches sqlite_async while adding essential features like automatic sync, conflict resolution, and permission-based resyncing.
