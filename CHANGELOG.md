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
