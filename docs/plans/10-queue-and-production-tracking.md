# 10 — Queue & Production Tracking

**Status:** Scaffold — not started
**Build step:** §14 step 7 (computation) / step 8 (display) · **Owner:** [J]
**Depends on:** [[08-order-lifecycle-state-machine]], [[09-capacity-slots-and-drops]]
**Unblocks:** [[14-customer-portal]]
**Source:** PRD §5.6, §6.2, §6.3

---

## 1. Purpose

The customer's experience after paying is entirely "where am I, and when will it arrive." An honest
answer to both is a feature; a vague one generates messages the maker has to answer by hand.

## 2. The queue

> **The queue is the order garments get made in.** Position = your rank among unfinished orders that
> have a paid deposit, ordered by `deposit_paid_at ASC`.

First deposit paid is first made, then the next, and so on.

- **The deposit buys the place in line.** Submitting does not; an unpaid `QUOTED` order holds a slot
  but has **no position**.
- Position is displayed as **"2 of 5"** alongside the production stage.
- Position **never changes** except by orders ahead completing.
- `awaiting_denim` orders **keep their place** — waiting on a supplier does not cost the customer
  their spot.

### 2.1 Position is derived, never stored

Computed server-side for the caller's own order. **There is no endpoint that takes an arbitrary
`order_id` and returns its position or status** ([[02-identity-and-authorization]] §5.4).

`deposit_paid_at` is set **only** by the verified Stripe webhook, so line order cannot be manipulated
client-side ([[13-payments-and-stripe]]). This is also the answer to a position dispute: the timestamp
came from the payment processor, and every reorder writes an `order_event`.

### 2.2 Admin priority

The admin-only `priority` field can override sequencing for a genuinely blocked order. Every use
writes an `order_event`. It is **never sold** ([[09-capacity-slots-and-drops]] §7).

- [ ] **DECIDE:** does a `priority` override change the customer-visible position number, or only the
      maker's internal work order? Showing a customer their position moved *backwards* is worse than
      not showing movement. Recommendation: `priority` reorders the maker's list; the customer-visible
      number is recomputed from it, and a customer whose position worsens gets a message from the
      maker rather than a silent number change.

## 3. Production stages

`IN_PRODUCTION` sub-stages, in order: `awaiting_denim` → `cutting` → `sewing` → `finishing`.

Advanced by the maker, each writing an `order_event`. The customer timeline is built from those
events ([[08-order-lifecycle-state-machine]] §5), so it is a record rather than a rendering of the
current status alone.

## 4. Turnaround

Because the maker orders fabric as soon as the deposit clears — not when the garment reaches the
front — **supplier wait and queue wait overlap**:

```
turnaround ≈ max(supplier_lead_time, queue_wait) + build_time(silhouette) + shipping_transit
```

- With at most 5 slots, `queue_wait` is bounded and predictable: `position × build_time`.
- **`supplier_lead_time` lives on the supplier, not the fabric** — one supplier's whole range shares a
  lead time, and duplicating it per fabric guarantees drift. Store `lead_time_typical_days` and
  `lead_time_worst_days`; **quote the range, not the median**.
- Customers see a range ("typically 4–6 weeks") plus their live stage and position. **A hard date only
  appears if the maker sets one** on that specific order.

## 5. What the customer sees

| Element | Source |
| --- | --- |
| Status + sub-stage | `orders.status`, `orders.sub_stage` |
| Position "2 of 5" | Derived rank by `deposit_paid_at` |
| Estimated window | §4 formula, expressed as a range |
| Timeline | Customer-safe subset of `order_events` |
| Balance due prompt | On `READY` ([[13-payments-and-stripe]]) |

Rendered in [[14-customer-portal]].

## 6. Testing

- Position derived correctly with mixed states — unpaid `QUOTED` orders excluded.
- Order ahead reaching `READY` moves everyone behind up by one.
- `awaiting_denim` order retains position across a stage advance elsewhere.
- Requesting another customer's order position returns **404**.
- Turnaround range uses supplier worst-case, not median, for the upper bound.

## 7. Open questions

1. Priority vs. displayed position (§2.2).
2. Does position stay visible after `READY` (slot released, garment not shipped)? Recommendation:
   replace it with "ready — balance due", since the queue no longer applies.

## 8. Definition of done

- [ ] Position derived, never stored, never exposed for someone else's order
- [ ] Sub-stage advancement writes events and updates the customer timeline
- [ ] Turnaround shown as a range built from supplier typical/worst-case
- [ ] `awaiting_denim` proven not to cost a customer their place
</content>
