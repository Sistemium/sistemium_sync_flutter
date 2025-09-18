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
