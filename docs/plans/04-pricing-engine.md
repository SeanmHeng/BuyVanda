# 04 — Pricing Engine

**Status:** Scaffold — not started
**Build step:** §14 step 2 · **Owner:** [J]
**Depends on:** [[01-data-model-and-migrations]]
**Unblocks:** [[07-configurator-and-submission]], [[12-admin-review-and-quoting]],
[[13-payments-and-stripe]], [[16-shipping-and-tax]]
**Source:** PRD §5, §5.1–§5.4, §5.10

---

## 1. Purpose

Pricing bugs are money bugs. The calculation is isolated from everything that makes code hard to
test, and every number the customer ever sees comes out of it.

## 2. The formula

```
labor_cost    = base_labor(silhouette)      # maker's time for the silhouette
denim_cost    = yards_billed × cost_per_yard × (1 + price_buffer_pct)
hardware_cost = Σ (qty × unit_cost)         # buttons, rivets, zipper, buckle…
feature_cost  = Σ feature_price(feature)    # back buckle, deep yoke, pocket variants, embroidery…

subtotal = labor_cost + denim_cost + hardware_cost + feature_cost
         + commission_fee                  # full-custom only
total    = subtotal + shipping + tax
```

### 2.1 Rules that are not obvious from the formula

- **`yards_billed` is a fixed figure per silhouette, not computed from measurements.** The customer
  pays for the full cut, so a 2.3-yard and a 2.7-yard garment in the same silhouette cost the same.
  Set it to the whole-yard purchase the maker actually makes; remnants are the maker's.
  Maker-overridable per order.
- **Oversize guard.** Because yardage is flat, an unusually tall or large customer can exceed the
  standard cut. Each silhouette carries an `oversize_threshold` (e.g. inseam > 36" or waist > 44")
  that adds `oversize_extra_yards` **at review**. The maker reviews every order anyway, so this is a
  prompt rather than an automatic charge ([[12-admin-review-and-quoting]]).
- **Margin lives in labor and features.** Denim carries only a volatility buffer, not profit, so
  `base_labor` has to carry the business. It must be a real hourly rate × hours, not a round number
  that feels about right — validated with the simulator in §6.
- **Features vs. hardware must not double-count.** A back buckle is both a feature (labor to attach)
  and hardware (the buckle itself). Rule: **`feature_price` is labor only; the physical part is
  always a `hardware` line.** A feature may declare `required_hardware[]` so the part is added
  automatically.
- The customer-facing number pre-approval is an **estimate** and must be labeled as such.
- The maker can override any line and the total during review; overrides are recorded.
- Every component cost is **snapshotted onto the order** at quote time
  ([[01-data-model-and-migrations]] §4.2).

## 3. Fabric price drift — DECIDED

The maker cannot carry denim inventory, so **every order is sourced-to-order** and the fabric is
bought as soon as the deposit clears. Two mitigations, on all orders:

- **Per-fabric buffer.** A flat multiplier on `cost_per_yard`, stored as `fabrics.price_buffer_pct`,
  set by how volatile that supplier actually is. Starting values: **10% default, 15–20% for
  imported/FX-exposed selvedge, 5% for a stable domestic supplier.** Maker-editable per fabric.
- **Quote expiry.** Every quote carries `quote_valid_until` (default **14 days**) for the *price*.
  Past it the order moves to `EXPIRED` and a re-quote reprices against current `cost_per_yard`. This
  is a **different clock** from the 72-hour slot hold ([[09-capacity-slots-and-drops]]).

The buffer is a **plain buffer, not a true-up** — unused buffer is retained, not credited back on the
balance invoice. The customer sees a single **final cost** per line, never the raw `cost_per_yard` or
the multiplier.

> Consequence, and it is not optional: **the site must never describe denim as sold at cost.**

Revisit only if the maker later wants the at-cost pitch, which requires the true-up variant.

## 4. Range-quoted features

Some features cannot be priced from a form. Embroidery is quoted by size **and** complexity, which
the maker judges from a reference photo.

- The customer picks a size tier and uploads a reference image
  ([[03-security-baseline]] §7 governs the upload).
- The configurator shows a **price range**, not a number, clearly marked as pending review.
- The maker sets the actual price during quote review; it lands in
  `order_features.labor_price_at_order`.

| Tier | Displayed range |
| --- | --- |
| Small | $10–20 |
| Medium | $15–25 |
| Large | $25–45 |

Mechanically this is a **general capability, not an embroidery special case**: any feature with
`requires_review = true` carries `price_min`/`price_max` for display and gets its real price at
review. Full-custom free-text requests use the same path with no range shown.

## 5. Price freshness at quote time

The deposit is only as good as `cost_per_yard`, and there is no inventory to fall back on.

- The scraper refreshes curated fabric prices on a schedule and stamps `last_price_checked_at`
  ([[17-sourcing-and-scraper-intake]]).
- **Quoting never blocks on a live scrape.** A synchronous fetch at quote time would make quoting
  fail whenever a supplier site is slow or has changed layout. Submission **enqueues** a refresh
  ([[11-background-jobs-and-outbox]]) and the maker sees the price age in the review screen.
- If a fabric's price is older than **7 days**, the admin review screen flags it and the maker
  confirms or corrects before approving.

## 6. Implementation: pricing is a pure function

```python
def price(config: PricingInput) -> Breakdown:  # no DB, no HTTP, no framework, no clock
    ...
```

`PricingInput` is plain values — silhouette, fabric cost, buffer, features, hardware, zone.
`Breakdown` returns **every line**, never a bare total. The API layer loads rows and calls it; the
function itself is deterministic and trivially testable.

Three things fall out:

1. **The quote snapshot is just its output persisted.** No second code path.
2. **The admin price simulator** is the same function with hand-entered inputs — the maker enters a
   hypothetical garment and sees the full breakdown **and his margin** before launch. This is how
   `base_labor` gets validated as a real hourly rate ([[15-admin-catalog-and-price-list]]).
3. The estimate and the final quote cannot drift apart, because they are the same call with
   different inputs.

### 6.1 Golden test table

A table-driven test covering, at minimum:

- plain preset
- multiple features
- oversize surcharge applied
- range-quoted embroidery (estimate shows range; quote shows a number)
- full custom with commission fee
- **each** shipping zone ([[16-shipping-and-tax]])
- rounding edges, including deposit rounding (§7)

Any change to the formula shows up as a **diff in expected numbers** rather than a surprise on an
invoice. Part of the CI gate ([[00-development-environment]]).

## 7. Deposit calculation

Deposit = `denim_cost` **including buffer**, rounded up. Balance = `total − deposit`. Shipping and tax
are part of the **balance**, not the deposit. Schedule and triggers in [[13-payments-and-stripe]].

## 8. Customer-facing disclaimer

Two numbers reach the customer and they must not be confused:

1. **Estimate** — shown in the configurator, before review. Labeled as an estimate, with range-quoted
   features shown as ranges.
2. **Final quote** — issued by the maker; price valid 14 days, slot held 72 hours, deposit amount and
   the non-refundable-once-cut condition stated on the acceptance screen.

The estimate screen must state plainly that the final price is set after the maker reviews
measurements and reference images, and that fabric price may change until the quote is issued.
Copy owned by [[19-storefront-and-public-content]].

## 9. Open questions

Blocked on maker-supplied numbers (PRD §13): per-silhouette `yards_billed`, `base_labor_cost`,
`build_time_days`; hardware unit costs; oversize thresholds; commission fee. **None block building** —
they are seed data behind an admin screen.

1. Is `commission_fee` a flat number or per-silhouette? Flat is assumed until told otherwise.
2. Tax handling — see [[16-shipping-and-tax]].

## 10. Definition of done

- [ ] `price()` importable with no framework, DB, or clock dependency
- [ ] `Breakdown` returns every line item, and the API never constructs a total by hand
- [ ] Golden test table green in CI and covering all seven cases in §6.1
- [ ] Simulator wired to the same function
</content>
