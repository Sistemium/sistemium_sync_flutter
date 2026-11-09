## 2.11.0

* FIX: a row's next send no longer clears what the server filled on insert. The POST /data reply's ts used to go into the local row alone, so the copy held the server's version with a hook's document number (INC, TASK) still empty, and its next save cleared the number on the server. Rows now take the reply's `stored` row with the ts (servers from 2026-11 send it; older ones work as before).
* FIX: a row edited while its send was on the way keeps the edit, takes the server's ts and stored values for the columns it didn't edit, and goes next as an update. Before, the whole batch was left without its ts, so the edit went as a second insert, which the server refuses.
* Each sent row is settled on its own; a row written during the send waits for the next one.

## 2.5.9

* FIX: Add onDone handler to SSE stream listener for proper disconnect detection
* FIX: Store and properly close http.Client to prevent memory leaks
* FIX: Close http.Client in handleError, deinitDb, and dispose
* FIX: Add cancelOnError: false to stream listener for better error recovery
* Log when SSE stream is closed by server

## 2.5.8

* Add comprehensive SSE connection logging
* Log when SSE connects successfully
* Log when SSE connection fails with status code
* Log when SSE connection is lost and retrying
* Remove debug-only check from catch block for better error visibility

## 2.5.7

* Add complete sqlite_async API wrappers for all query and transaction methods
* Add executeBatch() for batch SQL execution
* Add get() and getOptional() for single row queries
* Add readTransaction() for read-only transactions
* All methods now exposed through BackendNotifier wrapper

## 2.5.6

* Simplify wrapper methods to directly passthrough to sqlite_async
* Remove unnecessary conditional logic in getAll(), watch(), and execute()
* Methods now match sqlite_async API signatures exactly

## 2.5.5

* Add isInitialized getter to check if database is ready
* Use backend.isInitialized instead of backend.db != null
* Provides clean API without accessing deprecated db getter

## 2.5.4

* Add complete wrapper methods for database access
* Add execute() method for raw SQL execution with parameter binding
* Update getAll() to support optional parameter binding
* Update watch() to support optional parameter binding
* Deprecate direct db access - all operations should use wrapper methods
* Improves API safety and encapsulation

## 2.5.3

* SECURITY: Remove ts field from user-provided data in write() method
* Users can no longer override ts timestamps - only server controls ts values
* Prevents potential timestamp manipulation and ensures data integrity

## 2.5.2

* Update local ts values from server POST responses
* Client now extracts ts values from successful sync operations
* Improves optimistic concurrency control by keeping local timestamps in sync
* Gracefully handles old server versions that don't return ts
* Skips ts updates for conflict responses (ignored: true)
* Reduces need to re-download data just to get timestamps

## 2.3.1

* Fixed sync_generator to only include entities marked as `is_syncable: true`
* This prevents local-only tables (like Settings) from being added to syncable collections
* Resolves server errors for non-syncable entities

## 2.0.2

* Fixed RulesBoard registration for empty collections
* Improved error handling to distinguish between server errors and empty collections
* Empty collections now register with null timestamp instead of throwing exception
* Added retry logic only for actual server/network errors

## 1.6.0

* **BREAKING CHANGE**: Renamed timestamp field from `lts` to `ts`
* Updated API endpoints: `/rules-lts` → `/rules-ts`
* Updated database schema: `last_received_lts` → `last_received_ts`
* Updated all field references and variable names for consistency
* Requires server version with `ts` field support

## 1.5.3

* Previous stable release

## 0.0.1

* TODO: Describe initial release.
