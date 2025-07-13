# Gemini Project Knowledge Base

## Project Overview

`sistemium_sync_flutter` is a Flutter library responsible for providing data synchronization capabilities between a Flutter application and the `sistemium_sync_service` backend. It manages a local SQLite database, handles fetching and sending data, and provides reactive streams for UI updates.

## Key Components

- **`BackendNotifier`**: The central class that orchestrates all synchronization logic, database interactions, and server communication.
- **`sqlite_async`**: The underlying package used for all local SQLite database operations.
- **`syncing_table`**: A special table in the local SQLite database that tracks the `last_received_lts` (timestamp) for every other syncable table, enabling efficient delta-syncing.

## Core Workflows

### 1. Data Synchronization (`fullSync`)

This is the main process for getting data from the server.

1.  **Send Unsynced Data**: First, it sends any locally created or modified data that is marked as `is_unsynced` to the server.
2.  **Fetch Remote Changes**: For each table listed in the `syncing_table`, it makes a request to the server's `/data` endpoint. It includes the `last_received_lts` for that table in the request, so the server only returns documents that are newer.
3.  **Upsert Data**: It takes the data received from the server and upserts it into the local SQLite database, updating existing records or inserting new ones.
4.  **Update Timestamp**: After successfully processing a batch of data, it updates the `last_received_lts` for that table in the `syncing_table` to the `lts` of the last record it received.

### 2. Real-time Updates (SSE)

- The library connects to the server's `/events` endpoint using Server-Sent Events (SSE).
- When the server sends a message (e.g., `data: ServiceTask`), it indicates that the `ServiceTask` collection has changed.
- Upon receiving any such event, the library triggers a `fullSync()` to fetch the latest updates.

### 3. Permission Handling (`_processRulesBoard`)

This is a critical mechanism for handling changes in user permissions that require a full data reset for certain tables.

1.  **Sync `RulesBoard`**: The `RulesBoard` table is treated like any other syncable table, so the client first downloads any new entries from the server.
2.  **Check for Instructions**: After a `fullSync`, the `_processRulesBoard` function runs. It queries the local `RulesBoard` table.
3.  **Process Entries**: If it finds any entries, it iterates through them. For each entry, it reads the `fullResyncCollections` field, which contains a list of table names (e.g., `['ServiceTask']`).
4.  **Truncate and Reset**: For each table name in the list, it performs two actions:
    - It completely wipes the local table using `delete from "ServiceTask" where 1=1`.
    - It sets the `last_received_lts` for that table in `syncing_table` to `NULL`.
5.  **Trigger Full Resync**: This process ensures that on the next `fullSync`, the client will download a fresh, complete copy of the data for the truncated tables, reflecting the user's new permissions.

**Bug Workaround**:
- The `DELETE` statement uses `where 1=1` because we discovered a bug in `sqlite_async: 0.11.7` where a `DELETE` statement without a `WHERE` clause does not correctly trigger the `watch` stream, preventing the UI from updating.

### 4. UI Reactivity (`watch`)

- The library exposes a `watch` method that takes a SQL query and a list of tables to `triggerOnTables`.
- This method returns a `Stream` that automatically emits a new set of data whenever any of the specified tables are changed (inserted, updated, or deleted).
- This is the primary mechanism used by the UI to react to data changes in the local database.
