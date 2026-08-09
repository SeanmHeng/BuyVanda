# 11 — Background Jobs & the Transactional Outbox

**Status:** Scaffold — not started
**Build step:** §14 step 6 · **Owner:** [L]
**Depends on:** [[08-order-lifecycle-state-machine]], [[09-capacity-slots-and-drops]]
**Unblocks:** [[13-payments-and-stripe]], [[17-sourcing-and-scraper-intake]],
[[18-messaging-and-notifications]]
**Source:** PRD §9.4

---

## 1. Purpose

Two things in this design cannot live inside a web request: **timed transitions** and **outbound
email**. Both have direct commercial consequences when they fail silently.

## 2. Scheduled work

| Job | Cadence | Consequence of not running |
| --- | --- | --- |
| 72-hour slot-hold expiry → `SLOT_FORFEITED` | frequent (≤5 min) | **The slot silently stays occupied and the shop never reopens** |
| 14-day quote price expiry → `EXPIRED` | daily | Stale prices honored past their validity |
| Scraper price-refresh scheduling + staleness flags | daily | Quotes priced against old `cost_per_yard` |
| Balance-due reminder on `READY` | daily | Garments sit finished and unpaid |
| Drop announcement send | on trigger | Marketing missed |

Nothing in a web request will ever fire the first one. That is the whole argument for this document
existing before the payment integration rather than after.

## 3. The outbox pattern for email

Sending inline from a request means the send can **fail after the database commits**, or **succeed
before a transaction that then rolls back** — either way state and notification disagree.

Instead:

1. The state change and an `outbox` row are written in the **same transaction**.
2. A worker polls `outbox`, sends, marks `sent_at`, and **retries with backoff** on failure.

This matters commercially, not just technically: **"your slot expires in 24 hours"** and **"your
garment is ready, balance due"** are the emails whose loss turns into a forfeited slot or a chargeback
from a customer who was never told.

`outbox` columns: `id`, `kind` (`email`/`webhook_followup`/…), `payload` (jsonb), `status`,
`attempts`, `next_attempt_at`, `created_at`, `sent_at`.

## 4. Idempotency

**Jobs must be idempotent.** A scheduler that fires twice must not send two emails or double-release a
slot.

- Transitions are no-ops when the order is already in the target state
  ([[08-order-lifecycle-state-machine]] §6).
- Outbox rows are claimed with a conditional update (`WHERE status = 'pending'`), not read-then-write.
- Slot release happens inside `transition()` only, so it happens exactly once per state change
  ([[09-capacity-slots-and-drops]]).

## 5. Dead letters

Failed sends need a **visible dead-letter state**, surfaced on the ops page
([[20-observability-and-ops]]). **A silently stuck outbox is the same as no email at all** — and it
fails in the direction of the customer never learning their slot is about to lapse.

Alert threshold on outbox depth and on any row exceeding max attempts.

## 6. Implementation

**DECIDED: EventBridge Scheduler → a single Lambda, once a minute. No queue, no Redis, no
long-running process.**

The worker is one handler in `api/` that wakes, does the work in §2, and exits:

```
EventBridge Scheduler  ──every minute──▶  worker Lambda
                                              ├── expire slot holds past 72h
                                              ├── expire quotes past 14 days
                                              └── drain outbox rows that are due
```

The queue this design seemed to need turned out not to exist. **The `outbox` table is the queue** —
it has a status, an attempt count, and a `next_attempt_at`, which is every primitive a job queue
provides. Adding RQ or Celery would have meant a second store holding a copy of what Postgres
already holds authoritatively, plus the reconciliation problem that follows from two sources of
truth about whether an email was sent.

Why this shape:

- **Nothing runs when nothing is happening.** Five commissions a year does not justify a process
  that is awake 24/7, and Lambda's free tier makes a per-minute invocation cost nothing.
- **Ops visibility is a SQL query.** Queue depth is `select count(*) from outbox where status =
  'pending'` — no broker to inspect ([[20-observability-and-ops]]).
- **The cadence is set by the tightest job.** Slot-hold expiry needs ≤5 minutes; one minute is well
  inside that and makes the daily jobs trivially cheap to co-schedule.

Two consequences to design for rather than discover:

- **A minute-cadence Lambda can overlap itself** if one run is slow. Every job must be safe to run
  concurrently with itself — which §4 already requires, but for a different reason. The conditional
  claim on outbox rows (`WHERE status = 'pending'`) is what makes it true.
- **Daily jobs need their own guard.** A job that should run once a day but is invoked 1,440 times
  needs a last-run timestamp, not a hope that the cadence matches.

Locally the same handler runs on a timer under `npm run worker`, so scheduled behaviour is
exercised without AWS ([[00-development-environment]]).

## 7. Testing

- Slot-hold expiry fires, forfeits, releases the slot, preserves the saved configuration, sends one
  email.
- The same job run twice produces one transition and one email.
- An outbox send that raises leaves the row retryable with backoff, then dead-letters after max
  attempts.
- A transaction that rolls back leaves **no** outbox row — the core property the pattern exists for.
- Clock-dependent tests inject the clock; jobs never call `Date.now()` directly at the logic layer
  ([[04-pricing-engine]] is pure for the same reason).
- Two overlapping invocations of the worker produce one transition and one email — the concurrency
  case the per-minute cadence makes real (§6).

## 8. Open questions

1. Email provider — SES, Postmark, Resend. Deliverability matters more than API ergonomics here,
   because the slot-expiry email landing in spam costs a sale. SES is the cheapest and the same
   account as everything else, but its sandbox and reputation setup are real work. Decide before
   step 13 ([[18-messaging-and-notifications]]).
2. Whether the slot-expiry warning is at T−24h only, or T−48h and T−12h. More reminders, fewer
   forfeits, more noise.

## 9. Definition of done

- [ ] Worker handler runs locally on a timer and deployed on EventBridge Scheduler
- [ ] All five jobs in §2 implemented and idempotent
- [ ] Daily jobs guarded by a last-run timestamp, not by cadence
- [ ] Outbox rows written in the same transaction as the state change, proven by a rollback test
- [ ] Dead-letter state visible on the ops page with an alert threshold
</content>
