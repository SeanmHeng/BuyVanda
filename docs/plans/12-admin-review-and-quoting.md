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
| **Price** | The full `Breakdown` from [[04-pricing-engine]], line by line, each editable |
| **Fabric freshness** | `last_price_checked_at` and its age; **flagged if older than 7 days** |
| **Oversize prompt** | Fires when measurements cross the silhouette's `oversize_threshold` |
| **Customer** | Order history, contact preference, thread link |

## 3. What the maker does

1. **Confirms the fabric is still available at the listed price.** Sourced-to-order means there is no
   inventory to fall back on; if the price is older than 7 days the screen requires confirmation or
   correction before approval.
2. **Prices range-quoted features.** Embroidery and any `requires_review` feature gets its real
   number here, landing in `order_features.labor_price_at_order`. Full-custom free-text requests use
   the same path.
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
  buffer multiplier.
- **Price valid 14 days. Slot held 72 hours.** Two clocks, both shown.
- The deposit amount, and that it becomes **non-refundable once the denim is purchased or cut**.
- A **Fit & Alterations policy** checkbox, timestamped into `orders.policy_accepted_at` (§7).

## 6. The price simulator

The maker enters a hypothetical garment and sees the full breakdown **and his margin**, using the same
`price()` function. This is how `base_labor` gets validated as a real hourly rate × hours rather than
a number that felt about right ([[04-pricing-engine]] §2.1). Lives in the admin panel
([[15-admin-catalog-and-price-list]]).

## 7. Fit and alterations

Made to measure means no resale value and no returns. Fit problems are handled **case by case** by the
maker — alteration, remake, or partial credit at his discretion, over the order's message thread or
email. **Not in the state machine for v1:** no `REMAKE` status, no automated flow.

> **But it must be written down.** "Case by case" with nothing published is what loses card disputes.

A short **Fit & Alterations policy**, explicitly accepted at quote acceptance, stating: garments are
made to the measurements the customer supplied; no returns or refunds for fit; the maker will work
with the customer on alterations; measurement accuracy is the customer's responsibility.

- [ ] **BLOCKED (PRD §13.5):** policy copy from the maker.

## 8. Authorization

Admin review routes live under `/api/admin/*` behind `require_admin`, with their **own unscoped
queries and their own audit events** — never an `is_admin` branch inside a customer route
([[02-identity-and-authorization]] §5.4).

## 9. Testing

- Approval snapshots every field in §4; a later fabric price change leaves the order untouched.
- Stale-price flag fires at 7 days and blocks approval until confirmed.
- Oversize prompt fires exactly at the threshold boundary.
- A range-quoted feature cannot reach `QUOTED` without a real price.
- Line override is recorded and reflected in the breakdown and the total.
- `policy_accepted_at` is required before deposit checkout can be created.

## 10. Open questions

1. Can the maker **re-quote** an `EXPIRED` order in place, or does it become a new order?
   ([[08-order-lifecycle-state-machine]] §8)
2. Should declining require a reason? Recommendation: yes, free text, included in the customer email —
   a decline with no explanation generates a message thread anyway.

## 11. Definition of done

- [ ] One screen shows configuration, flags, breakdown, freshness, and oversize prompt
- [ ] Approval writes every snapshot field and both clocks
- [ ] Acceptance screen states both clocks, the deposit condition, and the policy checkbox
- [ ] Simulator shares the pricing function with production quoting
</content>
