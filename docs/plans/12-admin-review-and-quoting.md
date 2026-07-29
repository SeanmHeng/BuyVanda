# 12 — Admin Review & Quoting

**Status:** Scaffold — not started
**Build step:** §14 step 7 · **Owner:** [J]
**Depends on:** [[04-pricing-engine]], [[06-measurement-capture]],
[[08-order-lifecycle-state-machine]], [[11-background-jobs-and-outbox]]
**Unblocks:** [[13-payments-and-stripe]], [[14-customer-portal]]
**Source:** PRD §4.1, §5, §5.2, §5.3, §5.4, §5.9

---

## 1. Purpose

The maker's review is the **only** gate between a submitted configuration and a charge. It is where
the estimate becomes a price, where measurement flags get caught before cutting, and where a stale
fabric price gets corrected. Everything expensive that goes wrong in this product goes wrong by
skipping past this screen.

## 2. The review screen

One screen, everything the maker needs to decide:

| Panel | Contents |
| --- | --- |
| **Configuration** | Silhouette, fabric (or sourcing request), features, free-text custom requests |
| **Measurements** | Full snapshot with units, **flags highlighted first** ([[06-measurement-capture]] §6) |
| **Materials** | Denim, hardware, add-ons — the pass-through lines from [[04-pricing-engine]], each editable |
| **Commission** | The one number he sets. Slider or field bounded by `shop_settings.commission_min`/`max`, with build time and the reference images in view |
| **Fabric freshness** | `last_price_checked_at` and its age; **flagged if older than 7 days** |
| **Oversize prompt** | Fires when measurements cross the silhouette's `oversize_threshold` |
| **Customer** | Order history, contact preference, thread link |

## 3. What the maker does

1. **Confirms the fabric is still available at the listed price.** Sourced-to-order means there is no
   inventory to fall back on; if the price is older than 7 days the screen requires confirmation or
   correction before approval.
2. **Sets the commission.** One judgment covering all of his time on this garment — cutting, sewing,
   finishing, embroidery, and any free-text custom request. It lands in `orders.commission_fee` and
   it is the only margin in the order ([[04-pricing-engine]] §4). This is the number the whole screen
   exists to get right.
3. **Applies the oversize surcharge** if prompted — `oversize_extra_yards`. It is a prompt, not an
   automatic charge, because the maker reviews every order anyway.
4. **Overrides any line or the total** if needed. **Overrides are recorded** — the reason belongs in
   the event note, not in his memory.
5. **Approves → `QUOTED`**, or **declines → `DECLINED`**.

For a full custom commission the maker must first confirm the **sourcing request**: availability and
landed cost, written back as `sourcing_requests.confirmed_cost_per_yard`, which becomes the deposit
basis ([[17-sourcing-and-scraper-intake]]).

## 4. What approval sets

On `SUBMITTED → QUOTED` ([[08-order-lifecycle-state-machine]] §3):

- `final_total` and the full `cost_breakdown` snapshot
- `commission_fee` — frozen, and unaffected by any later change to the range
- `yards_billed_at_quote`, `cost_per_yard_at_quote`, `buffer_pct_at_quote`
- `shipping_zone_id`, `shipping_amount` ([[16-shipping-and-tax]])
- `deposit_amount` = denim cost incl. buffer, rounded up
- `quote_valid_until` = **+14 days** (price)
- `slot_hold_expires_at` = **+72 hours** (slot)
- an outbox email to the customer ([[11-background-jobs-and-outbox]])

After this point, later changes to a fabric's `cost_per_yard`, a feature price, or hardware cost
**never alter this order** ([[01-data-model-and-migrations]] §4.2).

## 5. The quote acceptance screen (customer side)

Stated plainly, not buried in terms:

- The final price, line by line, with a single final cost per line — never `cost_per_yard` or the
  buffer multiplier. Materials and commission are separate lines, because that split is the honest
  description of what is being bought.
- **This total is a ceiling.** State it: the customer will never be asked for more than the figure
  they accept. If the denim comes in under the buffered estimate the difference is credited on the
  balance; if it comes in over, the maker absorbs it ([[04-pricing-engine]] §3.2).
- **Price valid 14 days. Slot held 72 hours.** Two clocks, both shown.
- The deposit amount, and that it becomes **non-refundable once the denim is purchased or cut**.
- A **Fit & Alterations policy** checkbox, timestamped into `orders.policy_accepted_at` (§7).

## 6. Recording the denim cost

This screen is why the document covers settlement as well as quoting. When the maker places the
supplier order during `awaiting_denim`, he records what the denim **actually** cost. The field layout
is specified in [[04-pricing-engine]] §3.4 — the required cost, an optional proof upload, the quoted
lines read-only, and the resulting balance computed live so he sees what the customer will see.

> **Until it is recorded, balance checkout is blocked.** Falling back to the quoted figure would
> silently keep money the customer was owed, and leave nothing behind to notice.

Recording writes `actual_denim_cost`, `denim_cost_recorded_at`, and `denim_proof_key`, plus an
`order_event` ([[08-order-lifecycle-state-machine]] §5). It does **not** touch `final_total` — the
credit is derived at checkout ([[01-data-model-and-migrations]] §4.2).

**The proof is required.** The true-up asks the customer to trust a number only the maker can see;
the supplier invoice is what answers a claim of overcharging. It is stored, never shown to the
customer by default.

The proof upload is maker-supplied rather than customer-supplied but goes through the
identical hardened path — magic-byte sniffing, re-encode, no SVG, private bucket
([[03-security-baseline]] §7). An admin upload is not a trusted upload.

## 7. The price simulator

The same `price()` function as production quoting, in the admin panel
([[15-admin-catalog-and-price-list]]). Its purpose has changed: there is no computed labor left to
validate, so it now answers **what the maker actually takes home** — commission set against the hours
a build really takes.

That question is the whole business now that the commission is the only margin in an order. Run it
against real build times **before** launch pricing is set ([[04-pricing-engine]] §9).

## 8. Fit and alterations

Made to measure means no resale value and no returns. Fit problems are handled **case by case** by the
maker — alteration, remake, or partial credit at his discretion, over the order's message thread or
email. **Not in the state machine for v1:** no `REMAKE` status, no automated flow.

> **But it must be written down.** "Case by case" with nothing published is what loses card disputes.

A short **Fit & Alterations policy**, explicitly accepted at quote acceptance, stating: garments are
made to the measurements the customer supplied; no returns or refunds for fit; the maker will work
with the customer on alterations; measurement accuracy is the customer's responsibility.

- [ ] **BLOCKED (PRD §13.5):** policy copy from the maker.

## 9. Authorization

Admin review routes live under `/api/admin/*` behind `require_admin`, with their **own unscoped
queries and their own audit events** — never an `is_admin` branch inside a customer route
([[02-identity-and-authorization]] §5.4).

## 10. Testing

- Approval snapshots every field in §4; a later fabric price change leaves the order untouched.
- A later change to `shop_settings.commission_min`/`max` leaves a quoted order's `commission_fee`
  untouched.
- Stale-price flag fires at 7 days and blocks approval until confirmed.
- Oversize prompt fires exactly at the threshold boundary.
- An order cannot reach `QUOTED` with no commission set, or one outside the configured range.
- Balance checkout is refused while `actual_denim_cost` is null (§6).
- Cost entry is refused without a proof upload.
- A recorded cost under the buffered figure produces a credit line; one over produces no change to
  the customer's total.
- Line override is recorded and reflected in the breakdown and the total.
- `policy_accepted_at` is required before deposit checkout can be created.

## 11. Open questions

1. Can the maker **re-quote** an `EXPIRED` order in place, or does it become a new order?
   ([[08-order-lifecycle-state-machine]] §8)
2. Should declining require a reason? Recommendation: yes, free text, included in the customer email —
   a decline with no explanation generates a message thread anyway.

## 12. Definition of done

- [ ] One screen shows configuration, flags, materials, commission input, freshness, and oversize
      prompt
- [ ] Approval writes every snapshot field, the commission, and both clocks
- [ ] Acceptance screen states both clocks, the ceiling promise, the deposit condition, and the
      policy checkbox
- [ ] Cost-entry screen exists and balance checkout is provably blocked without it
- [ ] Simulator shares the pricing function with production quoting and reports take-home
</content>
