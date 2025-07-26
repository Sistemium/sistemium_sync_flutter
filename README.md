# Sistemium Sync Flutter: Project Knowledge Base

## 1. Project Overview

`sistemium_sync_flutter` is a Flutter library responsible for providing data synchronization capabilities between a Flutter application and the `sistemium_sync_service` backend. It manages a local SQLite database, handles fetching and sending data, and provides reactive streams for UI updates.

## 2. Key Components

- **`BackendNotifier`**: The central class that orchestrates all synchronization logic, database interactions, and server communication.
- **`sqlite_async`**: The underlying package used for all local SQLite database operations.
- **`syncing_table`**: A special table in the local SQLite database that tracks the `last_received_ts` (timestamp) for every other syncable table, enabling efficient delta-syncing.

## 3. Core Workflows

### 3.1. Data Synchronization (`fullSync`)

This is the main process for getting data from the server.

1.  **Send Unsynced Data**: First, it sends any locally created or modified data that is marked as `is_unsynced` to the server.
2.  **Fetch Remote Changes**: For each table listed in the `syncing_table`, it makes a request to the server's `/data` endpoint. It includes the `last_received_ts` for that table, so the server only returns documents that are newer.
3.  **Upsert Data**: It takes the data received from the server and upserts it into the local SQLite database.
4.  **Update Timestamp**: After successfully processing a batch of data, it updates the `last_received_ts` for that table in the `syncing_table`.

### 3.2. Real-time Updates (SSE)

- The library connects to the server's `/events` endpoint using Server-Sent Events (SSE).
- When the server sends a message (e.g., `data: ServiceTask`), it indicates that the `ServiceTask` collection has changed.
- Upon receiving any such event, the library triggers a `fullSync()` to fetch the latest updates.

### 3.3. Permission Resync Handling (`_processRulesBoard`)

This is the critical client-side mechanism for handling data resets when a user's permissions change. The client's role in this process is intentionally simple.

1.  **Sync `RulesBoard`**: The `RulesBoard` table is treated like any other syncable table. During a `fullSync`, the client asks the server for new `RulesBoard` entries.
2.  **Receive Filtered Entries**: The `sistemium_sync_service` has a built-in rule that **only sends the client the `RulesBoard` entries relevant to them**. The client does not need to perform any specific filtering itself; it trusts that any entry it receives is intended for it.
3.  **Process Local Entries**: After syncing, the `_processRulesBoard` function runs. It reads **all** entries from its local `RulesBoard` table.
4.  **Truncate and Reset**: For each entry, it reads the `fullResyncCollections` field (a list of table names) and performs two actions for each table in the list:
    - It completely wipes the local table (e.g., `delete from "ServiceTask"`).
    - It sets the `last_received_ts` for that table in the `syncing_table` to `NULL`.
5.  **Trigger Full Resync**: This process ensures that on the next `fullSync`, the client will download a fresh, complete copy of the data for the truncated tables, reflecting the user's new permissions.

### 3.4. UI Reactivity (`watch`)

- The library exposes a `watch` method that takes a SQL query and a list of `triggerOnTables`.
- This method returns a `Stream` that automatically emits a new set of data whenever any of the specified tables are changed, which is the primary mechanism used by the UI to react to data changes.