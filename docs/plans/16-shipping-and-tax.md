# 16 — Shipping & Tax

**Status:** Scaffold — not started
**Build step:** §14 step 10 (zones) · **Owner:** [J]
**Depends on:** [[04-pricing-engine]], [[15-admin-catalog-and-price-list]]
**Unblocks:** [[13-payments-and-stripe]] (balance amount is not final without this)
**Source:** PRD §5.7, §9.1, §13.3, §13.8

---

## 1. Purpose

Small surface, real consequences: shipping is a pricing input, part of the balance, and the one place
a misconfiguration produces a **$0 charge** rather than an error.

## 2. Flat rate by zone

A zone is a band of distance from the maker's location.

| Zone | Definition | Rate |
| --- | --- | --- |
| Local | Maker's own state | maker-set |
| Domestic near | Named adjacent states | maker-set |
| Domestic far | Rest of country | maker-set |
| International | Everything else (**may be disabled at launch**) | maker-set |

Zones are **state lists with a flat dollar rate**, both editable in the admin panel rather than
hardcoded. True distance banding would need geocoding every address — more machinery than it is worth
at this volume.

> **A default fallback zone ensures an unmatched address never produces a $0 rate.**
> `shipping_zones.is_default` exists for exactly this. A test asserts that an address matching no
> `region_codes[]` still prices.

## 3. When shipping is applied

Shipping is added **at quote time** and is part of the **balance**, not the deposit
([[13-payments-and-stripe]] §3). `shipping_zone_id` and `shipping_amount` are snapshotted onto the
order at approval, so a later rate change never moves an existing quote.

The configurator's estimate includes shipping once an address (or at minimum a state) is known;
before that it must be shown as excluded rather than silently zero.

- [ ] **DECIDE:** does the configurator collect the shipping address, or only a state, before quote?
      A state alone is enough to price and less friction pre-purchase. Recommendation: **state at
      estimate, full address at quote acceptance.**

## 4. Fulfillment

**Accepted tradeoff of not using Shopify:** no built-in shipping labels or fulfillment tooling — the
maker buys postage himself. `SHIPPED` is a maker-entered transition, not an integration.

**DECIDED:** store the carrier and tracking number, render a link, integrate nothing.

`orders.tracking_carrier` (enum — USPS, UPS, FedEx, other) and `orders.tracking_number`, both entered
by hand on the `BALANCE_PAID → SHIPPED` transition ([[08-order-lifecycle-state-machine]] §3). The
portal renders them as a link to the carrier's own tracking page
([[14-customer-portal]]), and the outbox sends the number with the shipped
notification ([[18-messaging-and-notifications]]).

Two things this deliberately does **not** do:

- **No carrier API.** No live status, no delivery date pulled from the carrier. The link is the
  carrier's page, which is better at this than we would be.
- **No label purchasing.** Buying postage through the app means a label API (EasyPost, Shippo): an
  account, a funded postage balance, label printing, per-label fees, and another dependency that can
  fail on a shipping day. At five concurrent orders, typing a tracking number takes ten seconds.

The customer's delivery expectation does not come from the carrier anyway — it is the turnaround
range in [[10-queue-and-production-tracking]] §4, where `shipping_transit` is a property of the zone.
The tracking link answers "where is it *now*", which is a different question and only exists once the
parcel does.

Revisit if the maker ships enough that buying postage by hand becomes the annoying part of his week.
A label API replaces this cleanly and changes nothing the customer sees.

## 5. Tax

- [ ] **BLOCKED (PRD §13.8):** whether the maker has sales-tax nexus obligations.

Until answered, `tax` is a line in the pricing formula that evaluates to zero. If nexus exists,
**Stripe Tax** is the intended mechanism — it is already in the payment path and avoids building a
rate table.

Design implication either way: `total = subtotal + shipping + tax` keeps tax as its own line in the
`Breakdown` from day one ([[04-pricing-engine]] §2), so enabling it later is a configuration change
rather than a formula change. The golden test table includes a zero-tax and a non-zero-tax case.

## 6. International

May be disabled at launch. If enabled, two things that are not shipping-rate problems:

- Customs declarations and duties are the customer's, and must be said so on the acceptance screen.
- Return of an unwearable made-to-measure garment across a border is not a thing that happens; the
  Fit & Alterations policy ([[12-admin-review-and-quoting]] §8) carries even more weight here.

Recommendation: **disabled at launch**, enabled deliberately once domestic flow is proven.

## 7. Testing

- Each zone prices correctly (part of the pricing golden table, [[04-pricing-engine]] §6.1).
- An address matching no zone falls back to the default zone, never $0.
- Shipping lands in the balance, never the deposit.
- A zone rate edited after quoting leaves the order's `shipping_amount` unchanged.
- `SHIPPED` requires a carrier and tracking number, and the portal renders a working carrier link.

## 8. Definition of done

- [ ] Zones editable in admin, with a default zone that cannot be deleted
- [ ] Zero-rate impossible for any address, proven by test
- [ ] `shipping_amount` snapshotted at quote and included in the balance
- [ ] Tax present as a line that evaluates to zero until the nexus question is answered
- [ ] Carrier and tracking number captured at `SHIPPED` and surfaced as a link in the portal
</content>
