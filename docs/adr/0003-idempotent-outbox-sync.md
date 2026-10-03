# 3. Sync through a transactional outbox with idempotency keys

- Status: accepted

## Context

On a mobile network, a request can succeed on the server while its response
is lost (timeout, app killed, network switch). A naive retry then creates the
same payment twice, which is the most damaging bug a wallet can have.

## Decision

**Outbox.** Each local write inserts its domain rows *and* an `outbox` entry in
the **same database transaction**, so the two can never diverge: either both
exist, or neither does.

**Idempotency keys.** Each outbox entry gets a UUID once, at creation. It is
sent as the `Idempotency-Key` header on every attempt. The server stores the
first response per key and replays it for retries, without executing the
request again.

**Ordered draining.** `SyncEngine` sends entries in insertion order and stops
at the first transient failure, so a delete can never overtake the create it
depends on.

**Failure classes.**

| Response | Meaning | Action |
|---|---|---|
| 2xx | delivered | mark records `synced`, delete entry |
| 4xx (except 401/429) | permanent | mark records `failed`, keep entry with `last_error`, continue |
| 401 / 429 / 5xx / no response | transient | exponential backoff with jitter (2s → 5 min), stop the pass |

**Attempt bookkeeping.** `attempts` is incremented *before* a request is sent.
Deleting a record whose create has `attempts == 0` drops the entry, because the
server provably never saw it. Otherwise a delete is queued behind it.

**Triggers.** A pass runs after every local write, when connectivity returns,
and on a periodic timer. Concurrent triggers share one in-flight pass.

## Consequences

- Retries are always safe, and the tests prove it: with the response dropped
  100% of the time, the server still ends up with exactly one record.
- Background sync while the app is suspended (WorkManager / BGTaskScheduler)
  is not implemented. The queue survives restarts and drains on next launch.
- Requires server support for idempotency keys. This is standard for payment
  APIs (Stripe, Adyen) and is implemented by the bundled fake server.
