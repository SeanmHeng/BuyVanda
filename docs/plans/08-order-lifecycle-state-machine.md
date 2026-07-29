# 08 — Order Lifecycle & State Machine

**Status:** Scaffold — not started
**Build step:** §14 step 4 · **Owner:** [P]
**Depends on:** [[01-data-model-and-migrations]], [[07-configurator-and-submission]]
**Unblocks:** [[09-capacity-slots-and-drops]], [[10-queue-and-production-tracking]],
[[11-background-jobs-and-outbox]], [[12-admin-review-and-quoting]], [[13-payments-and-stripe]]
**Source:** PRD §7, §7.1

---

## 1. Purpose

Every meaningful thing in this product is a state change on an order. Centralizing them makes illegal
states impossible rather than merely unlikely, and makes the audit trail impossible to forget.

## 2. The lifecycle

```
DRAFT → SUBMITTED → QUOTED → DEPOSIT_PAID → IN_PRODUCTION → READY → BALANCE_PAID → SHIPPED → COMPLETED
          │           │
          ↓           ↓
      DECLINED   SLOT_FORFEITED (72h unpaid) / EXPIRED (14d price)
                        ↘ CANCELLED (admin, any pre-READY state)
```

`IN_PRODUCTION` carries a **sub-stage** for customer display: `awaiting_denim`, `cutting`, `sewing`,
`finishing`.

## 3. What each transition means

| Transition | Trigger | Side effects |
| --- | --- | --- |
| `DRAFT → SUBMITTED` | Customer submits | Claims a slot; snapshots measurements + estimate; enqueues price refresh |
| `SUBMITTED → QUOTED` | Maker approves | Sets `final_total`, `quote_valid_until` (+14d), `slot_hold_expires_at` (+72h); snapshots the breakdown; emails the customer |
| `SUBMITTED → DECLINED` | Maker declines | Releases slot; emails the customer |
| `QUOTED → DEPOSIT_PAID` | **Stripe webhook only** | Sets `deposit_paid_at` — the place in line; emails receipt; maker orders fabric |
| `QUOTED → SLOT_FORFEITED` | 72h job | Releases slot; keeps the configuration as a saved configuration; emails the customer |
| `QUOTED → EXPIRED` | 14d job | Price no longer honored; re-quote reprices against current cost |
| `DEPOSIT_PAID → IN_PRODUCTION` | Maker | Sub-stage starts at `awaiting_denim` |
| `IN_PRODUCTION → READY` | Maker | **Releases the slot** — the bench is free; asks for the balance |
| `READY → BALANCE_PAID` | **Stripe webhook only** | Emails receipt |
| `BALANCE_PAID → SHIPPED` | Maker | Carrier + tracking number, both **required** ([[16-shipping-and-tax]] §4); emails the customer the link |
| `SHIPPED → COMPLETED` | Maker or time | Terminal |
| `* (pre-READY) → CANCELLED` | Admin | Releases slot; refund handled manually |

## 4. Implementation: the state machine is data

Transitions live in **one table in code**, not as `if` statements spread across handlers:

```python
TRANSITIONS: dict[Status, set[Status]] = {
    Status.SUBMITTED: {Status.QUOTED, Status.DECLINED, Status.CANCELLED},
    Status.QUOTED:    {Status.DEPOSIT_PAID, Status.SLOT_FORFEITED, Status.EXPIRED, Status.CANCELLED},
    ...
}
```

One function performs every change:

```python
def transition(order, to: Status, actor: User, note: str | None = None) -> None:
    # rejects illegal transitions, writes the order_event, releases/claims slots
```

> **Nothing else may assign `order.status`.**

Three things fall out for free:

1. Illegal states become **impossible**, not merely unlikely.
2. The audit trail **cannot be forgotten**, because it is written in the same place as the change.
3. Slot accounting happens **exactly once** per transition instead of being recomputed by whoever
   remembers ([[09-capacity-slots-and-drops]]).

Side effects that must reach the outside world — emails, notifications — are **enqueued through the
outbox inside the same transaction** ([[11-background-jobs-and-outbox]]).

- [ ] **DECIDE:** enforce "nothing else assigns status" with a lint rule, a SQLAlchemy event hook that
      raises outside the transition function, or code review. A hook is the only one that survives a
      tired evening.

## 5. The event log

Every transition writes an `order_event`: actor, from, to, note, timestamp. It is both the audit trail
and the **source of the customer-visible timeline** ([[10-queue-and-production-tracking]]).

Two consumers with different needs:
- **Customer** sees a friendly subset — no internal notes, no admin priority changes.
- **Maker/dispute defense** sees everything, in order, with actors.

## 6. Idempotency

Transitions are driven by webhooks and scheduled jobs, both of which fire more than once by design
([[13-payments-and-stripe]], [[11-background-jobs-and-outbox]]). A transition to a state the order is
already in must be a **no-op that writes no event and sends no email**, not an error and not a
duplicate.

## 7. Testing

- Every legal transition succeeds and writes exactly one event.
- Every illegal transition raises, including the tempting ones (`SUBMITTED → SHIPPED`,
  `SLOT_FORFEITED → DEPOSIT_PAID`).
- Slot claim/release asserted per transition against the occupancy rules in
  [[09-capacity-slots-and-drops]].
- Replaying the same transition twice produces one event and one email.
- A full lifecycle test from `DRAFT` to `COMPLETED` using `MockPaymentProvider`.

## 8. Open questions

1. Does `SHIPPED → COMPLETED` happen on a timer (e.g. 14 days) or only by hand? Timer, assumed, so
   completed orders do not accumulate in the maker's list.
2. Is there a path back from `EXPIRED` to `QUOTED` on re-quote, or does a re-quote create a new order?
   **New order** keeps the audit clean but loses the thread. Decide at step 7.

## 9. Definition of done

- [ ] `TRANSITIONS` table exists and is the only source of legality
- [ ] `transition()` is the only writer of `order.status`, enforced mechanically
- [ ] Every transition writes an `order_event` in the same transaction
- [ ] Double-fire produces no duplicate events or emails
</content>
