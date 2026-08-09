# 13 — Payments (Stripe)

**Status:** Scaffold — not started
**Build step:** §14 step 7 (`MockPaymentProvider`) → step 11 (`StripePaymentProvider`) · **Owner:** [L]
**Depends on:** [[08-order-lifecycle-state-machine]], [[11-background-jobs-and-outbox]],
[[12-admin-review-and-quoting]]
**Unblocks:** [[10-queue-and-production-tracking]] (real `deposit_paid_at`), [[14-customer-portal]]
**Source:** PRD §5.5, §9.1, §11.9

---

## 1. Purpose

Money movement and queue position both flow through this integration. It is deliberately the last
thing built and the one with the most safety machinery.

## 2. Decision: Stripe, via Checkout Sessions

Both the deposit and the balance are hosted Checkout Sessions.

> **Webhooks are the single source of payment truth.** The API never marks an order paid from a
> client callback. `deposit_paid_at` — which sets queue position — is set **from the webhook**, so
> the line order cannot be manipulated client-side.

### 2.1 Why not Shopify

- Every garment is a **backend-computed price**, which means bypassing Shopify's product/variant model
  via draft orders.
- Everything is **made to measure** — no stock, no variants.
- Accounts, admin, and revenue are built here; Shopify's would duplicate and disagree.
- Shipping is **flat-rate**, removing the main thing Shopify automates.
- The deposit/balance split becomes **two Shopify orders per garment**.

That is a subscription fee to fight the data model.

**Accepted tradeoff:** no built-in shipping labels or fulfillment tooling — the maker buys postage
himself ([[16-shipping-and-tax]]).

## 3. Payment schedule

| Stage | Amount | Trigger |
| --- | --- | --- |
| **Deposit** | `denim_cost` incl. buffer, rounded up | Customer accepts quote. **Buys their place in line — no deposit, no position.** |
| **Balance** | `total − deposit − true_up_credit` | Order reaches `READY` **and** the actual denim cost is recorded |

The deposit becomes **non-refundable once the denim is purchased or cut** — stated on the
quote-acceptance screen, not buried in terms ([[12-admin-review-and-quoting]] §5). Since nothing is
held in stock, the deposit is what funds the fabric purchase; **the maker should not buy denim before
it clears.**

Shipping and tax are part of the **balance**, not the deposit.

### 3.1 The true-up

The balance settles the denim buffer against what the fabric actually cost
([[04-pricing-engine]] §3.2). It moves in one direction only:

- Denim came in **under** the buffered figure → the difference is **credited**, shown as its own
  named line. Not a discount; nothing was marked down.
- Denim came in **over** → **the maker absorbs it.** The customer's total never rises above the
  figure they accepted.

Two consequences for this integration. The balance amount is computed **server-side** at session
creation from the frozen quote plus the recorded actual — never passed in, and never recomputed from
live catalog rows ([[03-security-baseline]] §2). And **creating a balance Checkout Session is refused
while `actual_denim_cost` is null** ([[12-admin-review-and-quoting]] §6), because the correct amount
is not yet knowable.

## 4. Provider interface

Kept provider-agnostic so the lifecycle is testable without Stripe keys:

```ts
interface PaymentProvider {
  createDepositCharge(order: Order, amountCents: number): Promise<ProviderRef>
  createBalanceCharge(order: Order, amountCents: number): Promise<ProviderRef>
  handleWebhook(rawBody: string, signature: string): Promise<PaymentEvent>  // idempotent
  refund(payment: Payment, amountCents: number): Promise<ProviderRef>
}
```

`handleWebhook` takes the **raw body**, not a parsed object: Stripe's signature is computed over the
exact bytes received, so anything that parses first has already destroyed the thing being verified.
In Hono that means reading the body as text on this route and never mounting a JSON parser ahead of
it — a mistake that produces a working integration in test mode and an unverifiable one in
production.

v1 develops against a **`MockPaymentProvider`** from step 7 so the full lifecycle — including queue
position and balance-due emails — is exercised long before Stripe is wired in.
`StripePaymentProvider` lands at step 11.

## 5. Webhook safety

- **Verify the signature on every event.** Reject unsigned or stale payloads.
- **Idempotent by Stripe event id**, enforced by a **unique constraint on
  `processed_webhooks.event_id`** — not a read-then-write check, which races under concurrent
  delivery. Webhooks are delivered more than once **by design**, and out of order.
- The handler is **small and fast**: record the event, transition the order
  ([[08-order-lifecycle-state-machine]]), enqueue any email via the outbox
  ([[11-background-jobs-and-outbox]]), return 200. Slow work in a webhook handler causes Stripe
  retries, which is how duplicate processing starts.
- **Confirm the paid amount matches** `orders.deposit_amount` / the balance before advancing state.
- Resolve the order via `provider_ref` from the **signed payload**, never via an id supplied by a
  client ([[02-identity-and-authorization]] §5.4).
- Out-of-order delivery: a balance event arriving before its deposit event must not skip a state.
  The transition table rejects it; the event is recorded and retried.

## 6. Card data

**No card data ever touches our server.** Checkout Sessions are hosted; only the publishable key
reaches the browser ([[03-security-baseline]] §9).

## 7. Refunds

Manual, maker-initiated, via the `refund()` interface. There is no automated refund flow in v1 —
`CANCELLED` releases a slot but the money decision is the maker's. The deposit's non-refundable
condition applies **only once denim is purchased or cut**; before that, a refund is the honest answer,
including the case where a curated fabric is discontinued mid-order.

## 8. Testing

- Full lifecycle `DRAFT → COMPLETED` against `MockPaymentProvider`, no network.
- The **same webhook event delivered three times** produces one payment row, one transition, one
  email.
- Events delivered **out of order** never produce an illegal state.
- An event whose amount does not match `deposit_amount` is rejected and alerted.
- A balance session cannot be created while `actual_denim_cost` is null.
- Balance amount reflects the true-up credit when the denim came in under, and is unchanged when it
  came in over.
- An unsigned or replayed-with-old-timestamp payload is rejected.
- `deposit_paid_at` is unwritable from any customer-facing route (part of the authorization matrix,
  [[02-identity-and-authorization]] §6).

## 9. Open questions

1. **Sales tax (PRD §13.8)** — whether the maker has nexus obligations; Stripe Tax if so.
   See [[16-shipping-and-tax]].
2. Whether an expiring slot hold should cancel the open Checkout Session, or leave it to expire. A
   customer paying 10 seconds after forfeiture, into a released slot, is the case to design for.
   Recommendation: set the session expiry to the slot hold, and reconcile any late payment as a
   refund with an apology email rather than an oversold slot.
3. Stripe Radar / fraud rules — likely unnecessary at this volume, revisit if disputes appear.

## 10. Definition of done

- [ ] `MockPaymentProvider` exercises the whole lifecycle in CI without keys
- [ ] Signature verification and `processed_webhooks` unique constraint in place
- [ ] Amount verified against the order before any state advance
- [ ] `deposit_paid_at` written **only** by the webhook handler, proven by test
- [ ] Triple-delivery and out-of-order tests green
</content>
