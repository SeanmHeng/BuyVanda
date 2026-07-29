# 20 — Observability & Ops

**Status:** Scaffold — not started
**Build step:** §14 step 14 · **Owner:** [P]
**Depends on:** [[09-capacity-slots-and-drops]], [[11-background-jobs-and-outbox]],
[[13-payments-and-stripe]], [[17-sourcing-and-scraper-intake]]
**Unblocks:** launch
**Source:** PRD §12.4, §11.12

---

## 1. Purpose

> A drop is a concentrated traffic event with a fixed capacity. Discovering the next morning that
> submissions were failing means **the drop is simply gone.**

There is no second chance at a drop and no "we'll catch it next week" — five slots is the whole
inventory for that cycle.

## 2. Error tracking

Sentry or equivalent, on **both API and frontend**.

- **PII scrubbing configured before launch.** Measurements, addresses, phone numbers, and tokens must
  never appear in an error payload ([[03-security-baseline]] §9). Configure it first, then verify by
  deliberately triggering an error carrying a measurement payload and checking what arrived.
- Release tagging so a spike maps to a deploy.

## 3. Structured logs

JSON logs with a **request id propagated end to end** — browser → API → worker → outbox row. Without
it, "the customer says their deposit didn't register" is an afternoon of guessing.

Never logged: measurements, addresses, tokens, full webhook payloads.

## 4. The ops page

An admin page showing **what the maker and developer actually need at 8pm during a drop**:

| Panel | Why |
| --- | --- |
| **Shop state and slot count** | The single number the whole business runs on |
| **Outbox depth and dead-lettered sends** | A stuck outbox is silently no email at all ([[11-background-jobs-and-outbox]] §5) |
| **Last successful scraper run + stale-price count** | Whether quoting is pricing against fresh data |
| **Recent failed payments** | Money that did not arrive, before the customer writes in |

Add, because they are cheap and answer the next question:
- oldest pending outbox row age
- count of orders with a slot hold expiring in the next 12 hours
- last scheduled-job run per job

- [ ] **DECIDE:** alerting channel. Email to the maker is not it — he is the one who cannot fix it.
      Recommendation: push/SMS to the developer for outbox dead letters, failed webhook processing,
      and any 5xx spike during an open drop.

## 5. What to watch during a drop

A short runbook, written before the first drop rather than during it:

1. Submissions succeeding (count vs. 5xx rate)
2. Slot count decrementing correctly and exactly once per submission
3. Checkout sessions created vs. webhooks received
4. Outbox draining

## 6. Health checks

Liveness and readiness endpoints covering database, Redis, and the worker's last heartbeat. A worker
that has silently died is indistinguishable from a quiet week — until a slot hold never expires and
the shop never reopens.

## 7. Testing

- PII scrubbing verified with a deliberately triggered error carrying a measurement payload.
- Request id present and identical across API log, worker log, and outbox row for one flow.
- Ops page renders correct numbers against seeded data, including a dead-lettered outbox row.
- Health check fails when the worker heartbeat is stale.

## 8. Definition of done

- [ ] Error tracking live on both tiers with verified PII scrubbing
- [ ] Request id propagated end to end
- [ ] Ops page with all four required panels plus the three additions in §4
- [ ] Alerting to the developer, not the maker
- [ ] Drop runbook written and rehearsed once against seeded data
</content>
