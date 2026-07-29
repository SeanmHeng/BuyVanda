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
maker buys postage himself. In v1, `SHIPPED` is a maker-entered transition with an optional tracking
number, not an integration.

- [ ] **DECIDE:** store a tracking number and carrier on the order and surface it in the portal?
      One field, meaningful reduction in "where is it" messages. Recommendation: yes.

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
  Fit & Alterations policy ([[12-admin-review-and-quoting]] §7) carries even more weight here.

Recommendation: **disabled at launch**, enabled deliberately once domestic flow is proven.

## 7. Testing

- Each zone prices correctly (part of the pricing golden table, [[04-pricing-engine]] §6.1).
- An address matching no zone falls back to the default zone, never $0.
- Shipping lands in the balance, never the deposit.
- A zone rate edited after quoting leaves the order's `shipping_amount` unchanged.

## 8. Definition of done

- [ ] Zones editable in admin, with a default zone that cannot be deleted
- [ ] Zero-rate impossible for any address, proven by test
- [ ] `shipping_amount` snapshotted at quote and included in the balance
- [ ] Tax present as a line that evaluates to zero until the nexus question is answered
</content>
