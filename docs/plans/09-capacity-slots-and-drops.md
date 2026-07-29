# 09 — Capacity, Slots & Drops

**Status:** Scaffold — not started
**Build step:** §14 step 5 · **Owner:** [L]
**Depends on:** [[08-order-lifecycle-state-machine]], [[03-security-baseline]]
**Unblocks:** [[10-queue-and-production-tracking]], [[11-background-jobs-and-outbox]],
[[19-storefront-and-public-content]]
**Source:** PRD §6, §6.1, §6.3, §6.4, §11.8

---

## 1. Purpose

Capacity is the defining constraint of the business: **five commissions at a time, no more.** Orders
open as a **drop**, slots fill, the shop closes. That scarcity is intentional and part of the
product's appeal — which means the system, not the maker's memory, has to enforce it.

## 2. Two concepts, easily conflated

- **Slots** — *how many* commissions exist at once. Hard cap of **5**. Controls whether the shop is
  open. **This document.**
- **Queue** — *the order they get made in*. Determined by `deposit_paid_at`.
  [[10-queue-and-production-tracking]].

## 3. Slot occupancy

`MAX_SLOTS = 5`, configurable in admin (`shop_settings.max_slots`).

A slot is **occupied** by any order in `SUBMITTED`, `QUOTED`, `DEPOSIT_PAID`, or `IN_PRODUCTION`.

A slot is **released** when the order reaches:
- `READY` — the maker's bench is free even though payment and shipping are outstanding
- `DECLINED`, `CANCELLED`, `EXPIRED`, or `SLOT_FORFEITED`

Slots are held **from `SUBMITTED`, not from deposit** — otherwise the maker would quote a dozen people
for five places and spend his time producing disappointment.

### 3.1 The 72-hour hold

> A `QUOTED` order must be paid within **72 hours** (`slot_hold_expires_at`). If it lapses, the order
> moves to `SLOT_FORFEITED`, its configuration is kept as a saved configuration the customer can
> resubmit at the next drop, and the slot returns to the pool.

**Two clocks, two jobs:** 14 days is how long the *price* is honored ([[04-pricing-engine]] §3);
72 hours is how long the *slot* is held. They are independent and must not be collapsed into one
field. Both are fired by scheduled jobs ([[11-background-jobs-and-outbox]]) — nothing in a web request
will ever fire them, and without the scheduler a forfeited slot silently stays occupied and **the
shop never reopens**.

## 4. The slot race — correctness and fairness

Two people submitting simultaneously for one remaining slot is **the normal case at a drop, not an
edge case**.

The cap is enforced **server-side at submission, inside a transaction** that counts occupied slots:

- `SELECT ... FOR UPDATE` on a capacity row, or a **Postgres advisory lock keyed on the drop**.
- Application-level counting outside a transaction **will oversell** during a drop — the exact moment
  when concurrency is guaranteed.
- Hiding the submit button is not enforcement.

- [ ] **DECIDE:** advisory lock vs. `FOR UPDATE` on `shop_settings`. Advisory lock keyed on `drop_id`
      is cleaner (no row contention outside the drop) but less obvious to a reader. Recommendation:
      advisory lock, with a comment explaining why.

Tested with a **concurrent submission test** — N simultaneous requests for the last slot, assert
exactly one succeeds. This test is the point of the section; without it the code is a hypothesis.

## 5. Shop state

Computed, with a manual override (`shop_settings.override_state`):

| State | Meaning |
| --- | --- |
| `OPEN` | Slots free and the maker has opened a drop. Submissions accepted. |
| `CLOSED_FULL` | All 5 slots occupied. Automatic. |
| `FORCE_CLOSED` | Maker closed manually (vacation, catch-up) even with slots free. |
| `FORCE_OPEN` | Maker accepts a submission beyond the cap deliberately. **Logged.** |

**Auto-close, manual re-open.** Hitting 5 closes the shop automatically. Reopening is a deliberate act
by the maker — that is what makes it a drop rather than a slot trickling back open at random hours.
Drops can be **scheduled** with an announced open time (`shop_settings.next_drop_at`).

## 6. Drops

A `drops` row records `opened_at`, `closed_at`, `slots_offered`, `opened_by`. Orders carry `drop_id`,
which is what makes "one active order per customer per drop" enforceable.

- [ ] **DECIDE (PRD §13.7):** drop cadence — reopen as each slot frees, or batch to 5 and open all at
      once? **Batching is the stronger drop; trickling keeps him busier.** Maker's call. The system
      supports both; only the habit differs.

## 7. No queue-jumping

With five orders, reordering is visible to everyone in it — a customer who paid a deposit would watch
a later order pass them. So there is **no rush fee and no paid priority**.

An admin-only `orders.priority` field exists for the maker's own sequencing (a genuinely blocked
order, a fabric that never arrived). Every use writes an `order_event`. **It is never sold.**

## 8. Ordering while closed

No waitlist, by decision ([[07-configurator-and-submission]] §5). Instead:

- Visitors see the state plainly: **"Orders closed — 5 of 5 in production"**, with the next drop time
  if one is scheduled ([[19-storefront-and-public-content]]).
- Saved configurations let a customer submit in one click at open, conferring nothing else.
- Customers may opt into a **drop announcement notification** (email). Everyone is notified at the
  same time; it is marketing, not a queue ([[18-messaging-and-notifications]]).

**Accepted consequence:** a drop is first-come-first-served, so some people who want a slot will not
get one, and fast submission is an advantage. That exclusivity is the intent.

## 9. Abuse control

Scarcity attracts abuse. Required, not optional:

- **Verified email** before submitting ([[02-identity-and-authorization]] §3)
- **Per-account and per-IP rate limits**, account-scoped doing the real work
  ([[03-security-baseline]] §6)
- **One active order per customer per drop**, enforced in the same transaction as the slot claim

## 10. Testing

- Concurrent submission for the last slot — exactly one wins (§4).
- Occupancy asserted for every status in the lifecycle table.
- `READY` releases a slot while payment is still outstanding.
- Slot-hold expiry job releases the slot and preserves the saved configuration.
- Job firing twice does not double-release.
- `FORCE_OPEN` submission beyond the cap succeeds and writes an event.

## 11. Definition of done

- [ ] Slot count enforced in a locked transaction, proven by a concurrency test
- [ ] All four shop states reachable and rendered on the storefront
- [ ] 72h and 14d clocks stored and fired independently
- [ ] One-active-order-per-drop enforced server-side
- [ ] Every `FORCE_OPEN` and every `priority` change writes an `order_event`
</content>
