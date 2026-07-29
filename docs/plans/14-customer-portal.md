# 14 — Customer Portal

**Status:** Scaffold — not started
**Build step:** §14 step 8 · **Owner:** [J]
**Depends on:** [[10-queue-and-production-tracking]], [[12-admin-review-and-quoting]],
[[13-payments-and-stripe]]
**Unblocks:** [[18-messaging-and-notifications]]
**Source:** PRD §3, §4.1, §6.2, §6.4

---

## 1. Purpose

Everything the customer does after they stop configuring: accept a quote, pay, watch the garment get
made, pay the balance, and ask the maker a question. Its job is to answer "where is my order" well
enough that the maker is not answering it by hand.

## 2. Surfaces

| Screen | Contents |
| --- | --- |
| **Order list** | All orders, current status, the one action each needs |
| **Order detail** | Status + sub-stage, **queue position ("2 of 5")**, estimated window, timeline, full price breakdown, message thread |
| **Quote acceptance** | Final price, both clocks, deposit condition, Fit & Alterations checkbox, pay button |
| **Balance due** | Triggered at `READY`, with the remaining amount |
| **Measurement profiles** | Create, edit, label; editing never touches a placed order |
| **Saved configurations** | Indicative price, "prices re-quoted at submission", one-click submit at open |
| **Account** | Contact preference (`in_app`/`email`/`phone`), phone, drop-notification opt-in |

## 3. The timeline

Built from `order_events` ([[08-order-lifecycle-state-machine]] §5), filtered to a
**customer-safe subset** — no internal notes, no admin `priority` changes, no decline reasoning the
maker did not intend to share. It is a record, not a rendering of the current status alone, which is
what makes it useful in a dispute.

## 4. Honest waiting

- Position and stage shown together; position derived server-side for the caller's own order only
  ([[10-queue-and-production-tracking]] §2.1).
- Turnaround as a **range**, built from supplier typical/worst-case. A hard date only if the maker set
  one on that order.
- `awaiting_denim` explained in plain language — the customer keeps their place while fabric ships.

## 5. Actions and their guardrails

| Action | Guardrail |
| --- | --- |
| Accept quote | Requires the policy checkbox; expires with `slot_hold_expires_at` |
| Pay deposit | Hosted Checkout; status advances only on the webhook |
| Pay balance | Only reachable from `READY` |
| Edit profile | Never mutates `measurement_snapshot` on an existing order |
| Message the maker | Ownership checked on the order **and** the thread |
| Cancel | **Not a customer action in v1** — pre-`READY` cancellation is admin-only, via a message |

Every route is `/api/me/*`, scoped by session, and **never takes a `user_id`**
([[05-api-contract-and-typed-client]] §3).

## 6. Empty and closed states

- Shop closed: **"Orders closed — 5 of 5 in production"**, next drop time if scheduled, and a prompt
  to save a configuration ([[09-capacity-slots-and-drops]] §8).
- No orders yet: route to the configurator, not a blank page.
- `SLOT_FORFEITED`: explain what happened, show the preserved configuration, and offer to resubmit at
  the next drop. This screen exists to keep a disappointed customer, so the copy matters.

## 7. Testing

- Every screen renders from seeded orders in each state ([[00-development-environment]] §5).
- Requesting another customer's order returns **404** on every route (authorization matrix).
- Timeline excludes admin-only events.
- Profile edit leaves a placed order's snapshot byte-identical.
- Quote acceptance is refused once `slot_hold_expires_at` has passed.

## 8. Open questions

1. Should the customer see the **full breakdown** post-quote, or only totals plus deposit/balance?
   Recommendation: full breakdown — it is the same data on the acceptance screen, and hiding it later
   invites "what am I paying for" messages.
2. Order cancellation by the customer before deposit: currently not offered. A `QUOTED` order the
   customer no longer wants just lapses at 72h, holding a scarce slot for up to three days. Worth
   allowing an explicit "release my slot" action — cheap, and it hands a slot back to the drop.

## 9. Definition of done

- [ ] All seven surfaces in §2 built against seeded data
- [ ] Position, stage, and range shown together on order detail
- [ ] Acceptance flow enforces policy checkbox and slot-hold expiry
- [ ] Authorization matrix green across every portal route
</content>
