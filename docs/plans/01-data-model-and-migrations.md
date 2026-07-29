# 01 — Data Model & Migrations

**Status:** Scaffold — not started
**Build step:** §14 step 1 · **Owner:** [P]
**Depends on:** [[00-development-environment]]
**Unblocks:** everything with a database in it — [[04-pricing-engine]],
[[08-order-lifecycle-state-machine]], [[09-capacity-slots-and-drops]], [[13-payments-and-stripe]]
**Source:** PRD §8

---

## 1. Purpose

The schema is the contract every other document writes against. Two properties matter more than
completeness: **money is never a float**, and **anything that can change later is snapshotted onto
the order at quote time**.

## 2. Scope

### In scope
Tables, key fields, ownership edges, snapshot boundaries, Alembic conventions, database roles.

### Out of scope
Business rules that operate on these tables — they live in the plan for the feature that owns them.

## 3. Tables

| Table | Key fields | Owned by plan |
| --- | --- | --- |
| `users` | id, email, email_verified_at, phone, contact_preference (`in_app`/`email`/`phone`), notify_on_drop, role (`customer`/`admin`), idp_subject | [[02-identity-and-authorization]] |
| `measurement_profiles` | user_id, label, units, waist, hip, thigh, knee, leg_opening, front_rise, back_rise, inseam, outseam, fit_preference, notes | [[06-measurement-capture]] |
| `measurement_flags` | order_id, field, rule, message | [[06-measurement-capture]] |
| `suppliers` | id, name, url, lead_time_typical_days, lead_time_worst_days, notes | [[15-admin-catalog-and-price-list]] |
| `fabrics` | id, name, color, weight_oz, cost_per_yard, price_buffer_pct, is_curated, reorderable, supplier_id, product_url, last_price_checked_at, photo_key | [[15-admin-catalog-and-price-list]] |
| `fabric_price_history` | fabric_id, cost_per_yard, observed_at, source | [[17-sourcing-and-scraper-intake]] |
| `silhouettes` | id, name, yards_billed, oversize_threshold (jsonb), oversize_extra_yards, build_time_days, active | [[04-pricing-engine]] |
| `features` | id, name, category, material_price, size_tier, applies_to[], requires_review, required_hardware[] | [[04-pricing-engine]] |
| `hardware` | id, name, kind, unit_cost, default_qty, active | [[04-pricing-engine]] |
| `shop_settings` | max_slots, override_state (`auto`/`force_open`/`force_closed`), next_drop_at, closed_message, commission_min, commission_max | [[09-capacity-slots-and-drops]], [[04-pricing-engine]] §4 |
| `drops` | id, opened_at, closed_at, slots_offered, opened_by | [[09-capacity-slots-and-drops]] |
| `saved_configurations` | user_id, silhouette_id, fabric_id, measurement_profile_id, features (jsonb), indicative_total, created_at | [[07-configurator-and-submission]] |
| `orders` | id, user_id, drop_id, type (`preset`/`custom`), silhouette_id, fabric_id \| sourcing_request_id, measurement_snapshot (jsonb), status, sub_stage, priority, estimate_total, final_total, cost_breakdown (jsonb), yards_billed_at_quote, cost_per_yard_at_quote, buffer_pct_at_quote, quote_valid_until, slot_hold_expires_at, shipping_zone_id, shipping_amount, policy_accepted_at, commission_fee, deposit_amount, deposit_paid_at, actual_denim_cost, denim_cost_recorded_at, denim_proof_key, ready_at, tracking_carrier, tracking_number | [[08-order-lifecycle-state-machine]] |
| `order_features` | order_id, feature_id, material_price_at_order, reference_image_key, notes | [[12-admin-review-and-quoting]] |
| `order_hardware` | order_id, hardware_id, qty, unit_cost_at_order | [[04-pricing-engine]] |
| `order_events` | order_id, actor_id, from_status, to_status, note, created_at | [[08-order-lifecycle-state-machine]] |
| `payments` | order_id, kind (`deposit`/`balance`), provider, provider_ref, amount, status | [[13-payments-and-stripe]] |
| `processed_webhooks` | provider, event_id (**unique**), received_at | [[13-payments-and-stripe]] |
| `sourcing_requests` | order_id, url, fabric_name, weight_oz, notes, maker_status, confirmed_cost_per_yard | [[17-sourcing-and-scraper-intake]] |
| `sourcing_candidates` | source, external_id, url, title, price, weight_oz, scraped_at, maker_status | [[17-sourcing-and-scraper-intake]] |
| `shipping_zones` | id, name, region_codes[], flat_rate, is_default, active | [[16-shipping-and-tax]] |
| `order_messages` | order_id, sender_id, body, attachment_key, read_at, created_at | [[18-messaging-and-notifications]] |
| `outbox` | id, kind, payload (jsonb), status, attempts, next_attempt_at, created_at, sent_at | [[11-background-jobs-and-outbox]] |

## 4. Cross-cutting rules

### 4.1 Money
`Decimal` or integer cents end to end — column type, Python type, and JSON representation. Never
float, at any layer, including the frontend.

- [ ] **DECIDE:** integer cents vs. `NUMERIC(10,2)`. Cents removes a whole class of rounding
      surprise and serializes cleanly to JSON; `NUMERIC` reads better in ad-hoc SQL. Pick once, at
      step 1, and make it a lint rule.

### 4.2 Snapshotting
Anything the customer was quoted against must be **frozen onto the order** at quote time so later
edits never move an existing quote:

- `measurement_snapshot` — editing a saved profile must never change a placed order.
- `yards_billed_at_quote`, `cost_per_yard_at_quote`, `buffer_pct_at_quote`
- `cost_breakdown` (jsonb) — the full pricing `Breakdown`, persisted verbatim
- `order_features.material_price_at_order`, `order_hardware.unit_cost_at_order`
- `shipping_amount`
- `commission_fee` — the maker's number for this garment. A later edit to
  `shop_settings.commission_min`/`max` never reprices a quoted order ([[04-pricing-engine]] §4).

The rule generalizes: **a catalog row is a template, an order row is a record.** If a field on the
order can be derived from a catalog row at read time, it is probably a bug.

**The true-up is not an exception to this.** `actual_denim_cost` is recorded after the quote, but it
never rewrites `final_total` — the credit is computed from the two frozen figures and rendered as its
own line, so the record reads *quoted → adjustment → charged* ([[04-pricing-engine]] §3.4).

### 4.3 Ids
Public ids are **UUIDs** (non-sequential) to raise the cost of enumeration. This is defense in depth,
not authorization — see [[02-identity-and-authorization]].

### 4.4 Ownership edges
Every customer-facing table reaches `users.id` in one hop or through `orders`. Anything that does not
is a table whose authorization story has not been thought through yet.

## 5. Migrations

- Alembic, autogenerate reviewed by hand — never applied blind.
- Every migration must be **reversible**, and CI asserts it ([[00-development-environment]]).
- The application's database role holds **no DDL rights**; migrations run as a separate role
  ([[03-security-baseline]]).
- Data migrations are separate revisions from schema migrations, so a failed backfill does not strand
  a schema change.

## 6. Open questions

1. Money representation (§4.1).
2. Whether `order_hardware` is populated at submission (from feature `required_hardware[]`) or only
   at quote approval. Affects whether the estimate and the quote can disagree on hardware —
   resolve in [[04-pricing-engine]].
3. Soft-delete vs. hard-delete for customer data, driven by the retention decision in
   [[03-security-baseline]].

## 7. Definition of done

- [ ] All tables in §3 created via Alembic, reversible, applied by `docker compose up`
- [ ] Money type decided and enforced by a lint/type rule
- [ ] Seed script populates every table ([[00-development-environment]])
- [ ] App role verified to be unable to run DDL
</content>
