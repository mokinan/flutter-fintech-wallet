# 4. Bloc, and Clean Architecture without ceremony

- Status: accepted

## Context

The app has several stateful flows with real concurrency concerns: debounced
search, pagination, auth and lock lifecycle, and live sync status. The
architecture needs clear boundaries without generating boilerplate that adds
no information.

## Decision

**Feature-first folders**, each split into `domain / data / presentation`:

- `domain` holds entities and repository *interfaces*. It is pure Dart with no
  Flutter or Drift imports in entities.
- `data` holds the implementations (Drift and Dio). It is the only layer that
  knows about SQL or HTTP.
- `presentation` holds Blocs/Cubits and widgets.

**Bloc / Cubit** for state:

- Cubits for form-like state (add transaction, transfer, session).
- A full `Bloc` where event concurrency matters. In `HistoryBloc`, search is
  debounced and `restartable`, so stale results are dropped, and pagination is
  `droppable`, so a fast scroll cannot load a page twice.

**No pass-through use cases.** A `GetTransactionsUseCase` that just calls
`repository.page()` adds a file without adding behaviour. Business rules live
in the repository implementation, or in a use case only once logic spans
several repositories.

**`get_it` as a composition root only.** `app/di.dart` is the one place that
knows concrete types. Widgets receive dependencies through `BlocProvider`, and
cubits receive them through constructors, which keeps every class testable
with plain constructor injection.

**Routing derives from state.** `go_router`'s `redirect` maps `SessionState`
to the reachable part of the app. No screen navigates to login or lock by
itself.

## Consequences

- Tests construct classes directly with fakes. No DI container is needed in
  tests.
- If business logic grows (for example fees or limits), use cases can be
  introduced where they earn their place.
