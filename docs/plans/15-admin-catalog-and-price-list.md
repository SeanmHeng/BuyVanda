# 15 — Admin Catalog & Price List

**Status:** Scaffold — not started
**Build step:** §14 step 10 · **Owner:** [J]
**Depends on:** [[04-pricing-engine]], [[12-admin-review-and-quoting]]
**Unblocks:** [[16-shipping-and-tax]], [[17-sourcing-and-scraper-intake]]
**Source:** PRD §4.3, §5, §5.1, §8, §13

---

## 1. Purpose

Every number in the pricing formula is a row the maker owns. This is the screen that turns the open
items in the PRD from blockers into **seed data behind an admin screen** — which is precisely why
none of them block building.

## 2. What the maker maintains

| Entity | Fields that matter | Why it matters |
| --- | --- | --- |
| **Silhouettes** | `yards_billed`, `build_time_days`, `oversize_threshold`, `oversize_extra_yards`, `active` | Sets the denim quantity **and** the queue's pace |
| **Fabrics** | `cost_per_yard`, `price_buffer_pct`, `is_curated`, `reorderable`, `supplier_id`, `product_url`, `photo_key`, `last_price_checked_at` | The curated list customers choose from; the deposit basis |
| **Suppliers** | `lead_time_typical_days`, `lead_time_worst_days` | Turnaround quoting — **lead time lives here, not on the fabric** |
| **Features** | `material_price`, `size_tier`, `applies_to[]`, `requires_review`, `required_hardware[]` | **Material only** — the labor is in the commission, the physical part is hardware |
| **Hardware** | `unit_cost`, `default_qty`, `kind` | Buttons, rivets, zippers, buckles |
| **Shipping zones** | `region_codes[]`, `flat_rate`, `is_default` | [[16-shipping-and-tax]] |
| **Shop settings** | `max_slots`, `override_state`, `next_drop_at`, `closed_message`, `commission_min`, `commission_max` | [[09-capacity-slots-and-drops]]; the commission range is [[04-pricing-engine]] §4 |

## 3. Rules the screens must enforce

- **`price_buffer_pct` is per fabric, set by that supplier's actual volatility.** Starting values:
  10% default, 15–20% for imported/FX-exposed selvedge, 5% for a stable domestic supplier.
- **A feature's price is material only.** Its labor is paid by the commission, so a feature that
  consumes nothing has no price at all. The UI should make the `required_hardware[]` link visible so
  the maker cannot accidentally price the buckle twice ([[04-pricing-engine]] §2.1).
- **The commission range is a business number, not a constant.** Editing it must be a form field —
  and the screen should say that changing it never reprices a quoted order.
- **Editing a price never touches an existing order** — every quoted order carries its own snapshot
  ([[01-data-model-and-migrations]] §4.2). Worth saying on the screen, because it is the maker's most
  likely worry.
- **Only `is_curated` + `reorderable` fabrics reach the configurator.** Everything else is
  maker-only.
- Deactivating a fabric with live orders against it warns rather than blocks.

## 4. The price simulator

The same `price()` function as production quoting ([[04-pricing-engine]] §6). The maker enters a
hypothetical garment and sees:

- the full breakdown, line by line
- the **take-home** — the commission, against the build hours it is meant to pay for

Materials are pass-through, so margin is no longer something to derive: it is the commission and
nothing else. The simulator's job is therefore to answer whether $50–100 is a defensible rate for a
garment that takes a day, and it should be built **before launch pricing is set**, not after
([[04-pricing-engine]] §9).

## 5. Price freshness and history

- `last_price_checked_at` shown with its age; anything older than **7 days** is visibly stale and
  flagged at review ([[12-admin-review-and-quoting]] §2).
- `fabric_price_history` gives a small sparkline per fabric — enough to see whether a buffer is set
  right, which is the only reason to keep the history.
- Prices arriving from the scraper are **suggestions**, never automatic writes
  ([[17-sourcing-and-scraper-intake]]).

## 6. Revenue summary

A simple view — deposits collected, balances collected, outstanding balances, orders by state. Not
accounting software; enough that the maker does not open Stripe to answer "how did this drop go."

- [ ] **DECIDE:** scope of the revenue view. Recommendation: per-drop totals plus a list, nothing
      cumulative or tax-related. Real accounting comes out of Stripe.

## 7. Authorization and safety

All routes under `/api/admin/*` behind `require_admin`
([[02-identity-and-authorization]] §4). Every price edit writes an audit record — the price list is
the single most valuable thing an attacker who reaches the admin account could quietly change, and
without a record the change is invisible.

Fabric search uses a hardcoded sort/filter allowlist and escapes `%`/`_` in `LIKE`
([[03-security-baseline]] §4).

## 8. Blocked on maker input (PRD §13)

None of these block building; they are values behind these screens.

1. Per-silhouette `yards_billed` and `build_time_days`
2. Supplier lead times (typical + worst case)
3. Shipping zone rates and which states count as "near"
4. Hardware unit costs
5. Oversize thresholds
6. The commission range — $50–100 assumed, revisited against real build times

## 9. Definition of done

- [ ] CRUD for all seven entities in §2
- [ ] Simulator showing breakdown **and** take-home per garment
- [ ] Commission range editable, with quoted orders provably unaffected
- [ ] Price edits audited; snapshot isolation demonstrated on the screen's copy and by test
- [ ] Stale-price age visible per fabric
- [ ] Non-curated fabrics provably unreachable from the configurator
</content>
