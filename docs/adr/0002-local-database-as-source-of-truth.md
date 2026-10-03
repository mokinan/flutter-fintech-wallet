# 2. The local database is the source of truth

- Status: accepted

## Context

Users open a wallet app in elevators, on flights and on weak mobile data. If a
write must reach the server before the UI updates, the app feels broken
exactly when people need it.

## Decision

- All screens read from SQLite (Drift) through reactive queries
  (`watch()` / `tableUpdates`). They never read from the network directly.
- Writes commit locally first and are visible immediately, marked with a
  `sync_status` of `pending`.
- Balances are **derived** (`opening balance + SUM(amount_minor)`), never stored,
  so they cannot drift from the transactions they summarize.
- The network layer only moves data between the database and the server
  (see [ADR 3](0003-idempotent-outbox-sync.md)).

## Consequences

- The app is fully usable offline, and the UI tells the user what has and has
  not reached the server.
- Screens get live updates for free: a sync status change re-renders the
  history list without extra wiring.
- Conflict handling is required in principle. This app only creates and
  deletes (it never edits shared records concurrently), which keeps it simple.
  Editing would need server-side versioning, and that is deliberately out of
  scope.
- An explicit logout wipes the database. An *expired* session keeps it, so
  unsynced writes are not lost.
