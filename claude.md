# Sistemium Sync Flutter - Project Documentation

## Project Overview

**sistemium_sync_flutter** is a sophisticated Flutter/Dart library (v2.5.0) that provides offline-first data synchronization between Flutter applications and the Sistemium backend ecosystem. It manages local SQLite databases, orchestrates bidirectional sync, and provides reactive streams for real-time UI updates.

**Package Type:** Flutter library
**Version:** 2.5.0
**Minimum Dart:** >=3.9.2
**Minimum Flutter:** >=3.35.5

## Core Purpose

This library serves as a complete synchronization engine that:
- Manages local SQLite databases for offline-first data storage
- Syncs data bidirectionally with `sistemium_sync_service` backend
- Provides real-time updates through Server-Sent Events (SSE)
- Implements permission-based data reset mechanisms (RulesBoard)
- Exposes reactive streams for UI components to observe data changes

## Architecture Overview

```
┌─────────────────────────────────────┐
│   Flutter UI Layer (ChangeNotifier) │
│   - watch() returns reactive Stream │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   BackendNotifier (Orchestrator)    │
│   - Sync Queue Management           │
│   - Database Transactions           │
│   - SSE Event Handling              │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   SQLite Database Layer             │
│   - sqlite_async package            │
│   - Local data persistence          │
└──────────────┬──────────────────────┘
               │
┌──────────────▼──────────────────────┐
│   HTTP/SSE Communication Layer      │
│   - Backend API endpoints           │
│   - Event streaming                 │
└─────────────────────────────────────┘
```

## How It Works

### 1. Database Initialization

The library uses `sqlite_async` for local data storage:

```dart
// Initialize database with server URL and credentials
await backend.initDb(
  serverUrl: 'https://api.example.com',
  userId: userId,
  authToken: authToken,
);
```

**Database Location:** `{documentsDirectory}/{userId}/sync.db`

**System Tables:**
- `syncing_table` - Tracks sync progress per entity (last_received_ts)
- `RulesBoard` - Handles permission changes and full resyncs
- `Archive` - Tracks deleted records for sync propagation

### 2. Data Synchronization Mechanism

#### Delta Sync with Timestamps

The library implements efficient delta-syncing:

```
Client: GET /data?name=ServiceTask&ts=2025-01-15T10:30:00.000Z
Server: Returns only documents with ts > provided timestamp
Client: Upserts received data into local SQLite
Client: Updates last_received_ts in syncing_table
```

**Benefits:**
- Minimal bandwidth usage (only changed data)
- Handles offline periods gracefully
- Pagination support (10,000 records per page)
- Resumable sync after interruptions

#### Bidirectional Sync

**Downstream (Server → Client):**
```dart
Future<void> syncTable(String tableName) async {
  // 1. Get last sync timestamp from syncing_table
  String? ts = table['last_received_ts'];

  // 2. Fetch remote changes with pagination
  while (more && _db != null) {
    await _fetchData(
      name: tableName,
      lastReceivedTs: ts,
      pageSize: 10000,
      onData: (resp) async {
        // 3. Upsert data into local DB
        await _upsertReceivedData(resp['data']);
        // 4. Update last_received_ts
        ts = resp['lastTs'];
      }
    );
  }
}
```

**Upstream (Client → Server):**
```dart
Future<bool> _sendUnsyncedForTable(String tableName) async {
  // 1. Get all is_unsynced = 1 records
  final rows = await db.getAll(
    'SELECT * FROM $tableName WHERE is_unsynced = 1'
  );

  // 2. POST to /data endpoint
  final res = await http.post(uri, body: jsonEncode({
    'name': tableName,
    'data': jsonEncode(rows)
  }));

  // 3. Mark as synced only if data hasn't changed
  // (handles race conditions)
}
```

### 3. Real-Time Updates via SSE

Maintains persistent Server-Sent Events connection:

```dart
// Connect to /events endpoint
final uri = Uri.parse('$_serverUrl/events');
final request = http.Request('GET', uri)
  ..headers['Accept'] = 'text/event-stream';

// Listen for table change notifications
_eventSubscription = res.stream
  .transform(utf8.decoder)
  .transform(const LineSplitter())
  .listen((event) {
    if (event.startsWith('data:')) {
      final tableName = event.substring(5).trim();
      // Queue sync for updated table
      _addToSyncQueue(SyncQueueItem(
        method: 'syncTable',
        arguments: {'tableName': tableName},
      ));
    }
  });
```

**Event Format:** `data: TableName`

### 4. Queue System

Operations are processed sequentially to prevent conflicts:

```dart
final List<SyncQueueItem> _syncQueue = [];
final ValueNotifier<bool> isProcessingQueue = ValueNotifier<bool>(false);

void _addToSyncQueue(SyncQueueItem item) {
  if (_syncQueue.contains(item)) return;  // Deduplicate
  _syncQueue.add(item);
  if (!isProcessingQueue.value) _processQueue();
}

Future<void> _processQueue() async {
  isProcessingQueue.value = true;
  while (_syncQueue.isNotEmpty && _db != null) {
    final item = _syncQueue.removeAt(0);
    await _executeQueueItem(item);
  }
  isProcessingQueue.value = false;
}
```

### 5. Permission-Based Resync (RulesBoard)

The most sophisticated feature:

**When Backend Permissions Change:**
```
1. Server sends SSE event: "data: RulesBoard"
2. Client syncs RulesBoard table
3. Client reads fullResyncCollections field
4. For each table needing resync:
   - Create shadow table
   - Download fresh data with permissions
   - Replace original table
   - Delete shadow table
5. User now sees data they're permitted to see
```

**Example RulesBoard Entry:**
```json
{
  "_id": "...",
  "fullResyncCollections": "[\"ServiceTask\", \"ServicePoint\"]",
  "ts": "2025-01-15T12:00:00.000Z",
  "userIds": ["user123"]
}
```

### 6. Reactive UI Integration

The library exposes reactive streams via `watch()`:

```dart
// Watch returns Stream that emits on table changes
Stream<List> dataStream = backend.watch(
  sql: 'SELECT * FROM Users WHERE department = ?',
  triggerOnTables: ['Users', 'Departments'],
);

// Use in UI with StreamBuilder
StreamBuilder<List>(
  stream: dataStream,
  builder: (context, snapshot) {
    if (snapshot.hasData) {
      return ListView(children: ...);
    }
    return CircularProgressIndicator();
  },
)
```

### 7. Code Generation

The `sync_generator.dart` tool generates database schema from backend:

```bash
dart sync_generator.dart <server_url> <app_id> [auth_token] [output_path]
```

**Generated Code:**
```dart
class SyncConstants extends AbstractSyncConstants {
  final String appId = 'my-app-id';
}

class PregeneratedMigrations extends AbstractPregeneratedMigrations {
  final SqliteMigrations migrations = SqliteMigrations()
    ..add(SqliteMigration(1, (tx) async {
      await tx.execute(r'''CREATE TABLE Users (...)''');
    }));
}

class MetaEntity extends AbstractMetaEntity {
  final Map<String, String> syncableColumnsString = {
    'Users': '_id, name, email, ts',
  };
}
```

## Integration with Other Projects

### Integration with `sistemium_sync_service`

This library is **tightly coupled** with `sistemium_sync_service` backend:

**Endpoints Used:**
- `GET /models` - Fetch schema definitions (for code generation)
- `GET /latest-ts?name=Table` - Get latest sync timestamp
- `GET /data?name=Table&ts=...&pageSize=10000` - Fetch data delta
- `POST /data` - Send local changes
- `GET /events` (SSE) - Real-time change notifications

**Authentication:**
All requests include:
```
headers: {
  'appid': 'com.sistemium.vfs_master',
  'authorization': authToken
}
```

**Data Flow:**
```
sistemium_sync_flutter ←→ sistemium_sync_service
         ↓                           ↓
    SQLite DB                   MongoDB
```

### Integration with `vfs_master`

The `vfs_master` Flutter app uses this library for all data operations:

**1. App Initialization:**
```dart
// In vfs_master's main.dart or auth_view.dart
final backend = BackendNotifier(
  abstractPregeneratedMigrations: PregeneratedMigrations(),
  abstractSyncConstants: SyncConstants(),
  abstractMetaEntity: MetaEntity(),
);

await backend.initDb(
  serverUrl: 'https://vfs.sistemium.com/api-v2/',
  userId: userId,
  authToken: accessToken,
);
```

**2. Widget Tree Wrapping:**
```dart
BackendWrapper(
  notifier: backend,
  child: MaterialApp(...)
)
```

**3. Data Access in UI:**
```dart
// vfs_master screens use watch() for reactive data
final backend = BackendWrapper.of(context);
final taskStream = backend.watch(
  sql: '''
    SELECT st.*, sp.address, le.name as customerName
    FROM ServiceTask st
    LEFT JOIN ServicePoint sp ON st.servicePointId = sp.id
    WHERE st.assigneeId = ?
  ''',
  triggerOnTables: ['ServiceTask', 'ServicePoint'],
);
```

**4. Data Modification:**
```dart
// When user updates task status
await backend.write(
  tableName: 'ServiceTask',
  data: {
    '_id': taskId,
    'processing': 'finished'
  },
);
// Automatically marks is_unsynced=1 and queues sync
```

**Integration Points:**
- `vfs_master` depends on `sistemium_sync_flutter` via Git reference
- Uses `pregenerated.dart` generated by sync_generator
- All database operations go through BackendNotifier
- UI reactivity powered by watch() streams
- No direct HTTP calls to backend (all via this library)

## Key Features

### 1. Offline-First Architecture
- Full CRUD operations work offline
- Local SQLite database with `is_unsynced` flags
- Automatic sync when connection restored
- Queue-based sync prevents conflicts

### 2. Optimistic Concurrency Control
- Timestamp-based conflict detection
- Race condition handling in send operations
- Transaction-based atomic updates

### 3. Sophisticated Permission System
- Server-side permission changes trigger client resync
- RulesBoard mechanism ensures data consistency
- Shadow table strategy prevents data loss during resync

### 4. Real-Time Synchronization
- Server-Sent Events for instant notifications
- Automatic reconnection with 5-second retry
- Heartbeat monitoring

### 5. Cross-Platform Support
- Flutter Web support via WASM
- iOS, Android, Desktop (macOS, Windows, Linux)
- Unified API across platforms

## File Structure

```
sistemium_sync_flutter/
├── lib/
│   ├── backend_wrapper.dart      # Core sync engine (1,126 lines)
│   ├── sync_abstract.dart        # Abstract base classes
│   └── sync_logger.dart          # Debug logging
├── bin/
│   └── sync_generator.dart       # Schema code generator (236 lines)
├── pubspec.yaml                  # Package definition
└── README.md                     # Documentation
```

## Dependencies

**Core:**
- `flutter` - Flutter framework
- `http: 1.5.0` - HTTP client
- `sqlite_async: 0.12.1` - Async SQLite database
- `path_provider: 2.1.5` - Platform file paths
- `objectid: 4.0.1` - MongoDB ObjectId generation
- `collection: 1.19.1` - Collection utilities

**Dev:**
- `flutter_lints: 6.0.0` - Code quality

## Usage Example

```dart
// 1. Generate schema
$ dart sync_generator.dart https://api.example.com my-app-id token

// 2. Initialize in app
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

// 3. Watch data
backend.watch(
  sql: 'SELECT * FROM Users',
  triggerOnTables: ['Users'],
).listen((data) => updateUI(data));

// 4. Write data
await backend.write(
  tableName: 'Users',
  data: {'_id': 'id', 'name': 'John'},
);

// 5. Query data
List<Map> results = await backend.getAll(
  sql: 'SELECT * FROM Users WHERE name = ?',
  params: ['John'],
);

// 6. Cleanup
await backend.deinitDb();
```

## Error Handling & Resilience

**Retry Mechanisms:**
- Table registration: 30-second retry
- Unsynced send: 3 retry attempts
- SSE connection: 5-second reconnect delay

**Data Integrity:**
- Transaction-based operations
- Race condition detection
- Deep equality checks before marking synced

## Known Limitations

1. No test suite (no test/ directory)
2. Single database per userId
3. No explicit offline/online detection
4. Fixed page size (10,000 records)
5. RulesBoard resync always replaces entire tables

## Development Notes

**Logging:**
- Debug-only logging via `SyncLogger`
- Timestamps and caller info included
- Format: `[HH:MM:SS.mmm] [file:line] message`

**Performance:**
- 32 indexes in typical vfs_master usage
- Efficient delta sync minimizes bandwidth
- SQLite for fast local queries

## Version History

**v2.5.0** (Current) - Active development
**v2.3.1** - Fixed sync_generator to filter is_syncable entities
**v2.0.2** - Fixed RulesBoard empty collection handling
**v1.6.0** (BREAKING) - Renamed `lts` → `ts` throughout

## Summary

`sistemium_sync_flutter` is the critical middleware that powers offline-first Flutter applications in the Sistemium ecosystem. It abstracts away the complexity of data synchronization, permission management, and real-time updates, allowing app developers to focus on business logic and UI. The library is production-ready, handling edge cases like race conditions, permission changes, and network failures with sophisticated retry and queue mechanisms.
