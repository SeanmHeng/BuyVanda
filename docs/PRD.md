# BuyVanda — Product Requirements Document & Roadmap

**Status:** Draft v2.0 — scope settled; detail decomposed into component plans ·
**Date:** 2026-07-25 · **Owner:** jjgreenwald

> **This document is the index.** It holds the product decisions, the architecture at a glance, and
> the build order. Every component and feature has its own plan under [plans/](plans/), and that plan
> is the authoritative detail for its area. When they disagree, the component plan is right and this
> file needs updating.

---

## 1. Summary

BuyVanda is a made-to-measure denim storefront for a **single maker working alone**. It sells two
things:

1. **Preset designs** — a fixed set of silhouettes (bootcut, straight fit, …) in a small curated range
   of denim (black, indigo, white, …), made to the customer's measurements.
2. **Full custom commissions** — priced higher, where the customer has free reign over denim choice
   and design features, subject to maker approval.

Capacity is the defining constraint: **five commissions at a time, no more.** Orders open as a
**drop**, slots fill, the shop closes. That scarcity is intentional and part of the product's appeal.

The differentiating feature is the **configurator**: measurements + denim + design features →
estimated quote → maker approval → deposit → production queue with visible status.

Off-the-shelf commerce handles browsing and money. It cannot handle measurement-driven pricing, maker
approval, staged payment, capacity-gated ordering, or a production queue. **That gap is the product.**

## 2. Decisions ledger

Everything below is settled. Each links to the plan that implements it.

| Decision | Detail |
| --- | --- |
| Curated denim for presets, free reign on paid commissions | [07](plans/07-configurator-and-submission.md) |
| Formula estimate + mandatory maker approval before any charge | [04](plans/04-pricing-engine.md), [12](plans/12-admin-review-and-quoting.md) |
| Deposit = denim cost incl. buffer; balance on ready | [13](plans/13-payments-and-stripe.md) |
| Configurator + queue as v1 | [07](plans/07-configurator-and-submission.md), [10](plans/10-queue-and-production-tracking.md) |
| Sourced-to-order; flat per-fabric buffer + 14-day quote expiry; single final cost shown | [04](plans/04-pricing-engine.md) §3 |
| **Stripe** for payments; webhooks are the source of payment truth | [13](plans/13-payments-and-stripe.md) |
| Everything made to measure | [06](plans/06-measurement-capture.md) |
| Flat-rate shipping by zone | [16](plans/16-shipping-and-tax.md) |
| Per-order in-app messaging with email/phone contact preference | [18](plans/18-messaging-and-notifications.md) |
| Range-quoted embroidery priced at review | [04](plans/04-pricing-engine.md) §4 |
| Flat `yards_billed` per silhouette — the customer pays the full cut | [04](plans/04-pricing-engine.md) §2.1 |
| Fit issues handled case by case against a **published** policy | [12](plans/12-admin-review-and-quoting.md) §7 |
| **Hard cap of 5 concurrent commissions, sold as limited drops** | [09](plans/09-capacity-slots-and-drops.md) |
| **No waitlist** | [09](plans/09-capacity-slots-and-drops.md) §8 |

## 3. Goals / Non-goals

### Goals (v1)
- Customer can configure a garment, submit it, and track it to delivery.
- Maker can review, price, approve, and progress orders without leaving the admin panel.
- Two-stage payment: denim cost as deposit, balance when the garment is ready.
- Capacity is enforced by the system, never by the maker remembering to say no.
- Customers see an honest queue position and production stage.

### Non-goals (v1)
- **A waitlist.** Deliberately rejected: it recreates a second queue and dilutes the limited-drop
  model. Saved configurations exist so customers can submit *fast* at open, not to hold a place.
- Automated purchasing on third-party sites. Explicitly out of scope, permanently.
- A public catalog of scraped third-party denim. Scraper output is maker-only.
- In-house denim stock / inventory tracking. Everything is sourced-to-order.
- Standard/off-the-rack sizing. Everything is made to measure.
- Automated SMS. Phone is a contact hint for manual texting.
- Rush/priority upsells. Reordering is visible to everyone in a five-person queue.
- Multi-maker / marketplace. Single maker assumed throughout.
- Returns and exchanges. Made-to-measure; fit is handled case by case.
- Mobile apps, internationalization, multi-currency.

## 4. Users

| Role | Needs |
| --- | --- |
| **Visitor** | Understand what's sold, see preset designs and pricing, see whether orders are open, decide to buy. |
| **Customer** (authenticated) | Save measurement profiles and configurations, submit at open, pay deposit and balance, see order status + queue position, message the maker. |
| **Maker / Admin** (single account, expandable) | Open and close drops, review and quote submissions, maintain the denim price list and per-fabric buffers, advance production stages, see revenue, work a sourcing queue. |

## 5. Architecture at a glance

```
React + TypeScript (Vite)          ← storefront, configurator, customer portal, admin panel
        │  REST/JSON
FastAPI (Python)                   ← ALL business logic: pricing, quoting, state machine, slots,
        │                            queue, authorization, payment orchestration, webhooks
        ├── PostgreSQL (+ Alembic migrations)
        ├── Redis                  ← rate limiting + background job queue
        ├── S3                     ← fabric photos, embroidery reference uploads
        ├── Identity provider      ← credential storage, password reset, email verification
        └── Stripe                 ← Checkout Sessions + webhooks
                ▲
        Scraper repo (Python)      ← POSTs to /internal/sourcing/* with a service token

        + a worker process         ← scheduled jobs and the transactional outbox
```

Node is build tooling for the React app only; there is no Node server. Detail in
[21 — Infrastructure](plans/21-infrastructure-and-deployment.md).

## 6. Plan index

Ownership: **[J]** junior dev implements · **[P]** paired — designed together, implemented by the
junior against a spec · **[L]** lead implements, junior reviews and is walked through it. The split is
by blast radius, not difficulty alone: money movement and concurrency are poor places to learn on live
orders.

### Tier 1 — Foundations
*Nothing downstream is safe or fast without these. Built first because retrofitting any of them is
expensive and because every later plan writes against them.*

| # | Plan | Covers | Own |
|---|---|---|---|
| 00 | [Development Environment & CI](plans/00-development-environment.md) | Repo layout, `docker compose`, seed data in every order state, CI gate | J |
| 01 | [Data Model & Migrations](plans/01-data-model-and-migrations.md) | Schema, Alembic, money type, snapshot boundaries | P |
| 02 | [Identity & Authorization](plans/02-identity-and-authorization.md) | Delegated auth, sessions, admin MFA + break-glass, `get_owned_order`, the route-walking IDOR matrix | P |
| 03 | [Security Baseline](plans/03-security-baseline.md) | Never trust the client for money or state, input validation, XSS, SSRF, uploads, rate limiting, PII | P |
| 04 | [Pricing Engine](plans/04-pricing-engine.md) | The formula as a pure function, buffers, quote expiry, range-quoted features, golden tests | J |
| 05 | [API Contract & Typed Client](plans/05-api-contract-and-typed-client.md) | Route namespaces, request/response conventions, generated TS client | J |

### Tier 2 — The customer path
*The product itself. Each depends on all of Tier 1 and on the one before it.*

| # | Plan | Covers | Own |
|---|---|---|---|
| 06 | [Measurement Capture & Validation](plans/06-measurement-capture.md) | Guided capture, range bounds, cross-field sanity checks, confirmation, flags | J |
| 07 | [Configurator & Submission](plans/07-configurator-and-submission.md) | Preset and custom paths, estimate display, saved configurations, `DRAFT → SUBMITTED` | J |
| 08 | [Order Lifecycle & State Machine](plans/08-order-lifecycle-state-machine.md) | The transition table, the single `transition()` writer, the event log | P |

### Tier 3 — Capacity and time
*What makes it a drop rather than a shop. Concurrency and scheduled work — the highest-blast-radius
code in the system.*

| # | Plan | Covers | Own |
|---|---|---|---|
| 09 | [Capacity, Slots & Drops](plans/09-capacity-slots-and-drops.md) | The 5-slot cap, the transactional slot race, shop states, 72h hold, abuse control | L |
| 10 | [Queue & Production Tracking](plans/10-queue-and-production-tracking.md) | Position by `deposit_paid_at`, sub-stages, turnaround ranges | J |
| 11 | [Background Jobs & Outbox](plans/11-background-jobs-and-outbox.md) | Slot/quote expiry jobs, the transactional outbox, idempotency, dead letters | L |

### Tier 4 — Money and the maker
*Everything that turns a submission into revenue.*

| # | Plan | Covers | Own |
|---|---|---|---|
| 12 | [Admin Review & Quoting](plans/12-admin-review-and-quoting.md) | The review screen, price freshness, oversize prompt, quote acceptance, fit policy | J |
| 13 | [Payments (Stripe)](plans/13-payments-and-stripe.md) | `MockPaymentProvider` → Stripe, webhook idempotency, deposit/balance schedule | L |
| 14 | [Customer Portal](plans/14-customer-portal.md) | Order list, timeline, position, balance payment, profiles | J |
| 15 | [Admin Catalog & Price List](plans/15-admin-catalog-and-price-list.md) | Fabrics, suppliers, silhouettes, features, hardware, price simulator, revenue | J |
| 16 | [Shipping & Tax](plans/16-shipping-and-tax.md) | Flat-rate zones, default-zone fallback, tax as a zero line until nexus is answered | J |

### Tier 5 — Supporting systems
*Deferred deliberately: none of them block taking an order, and each is cheaper once the core is real.*

| # | Plan | Covers | Own |
|---|---|---|---|
| 17 | [Sourcing & Scraper Intake](plans/17-sourcing-and-scraper-intake.md) | Sourcing queue, price monitoring, the internal endpoint, the admin-panel XSS trap | P |
| 18 | [Messaging & Notifications](plans/18-messaging-and-notifications.md) | Per-order threads, contact preference, transactional email, drop announcements | J |
| 19 | [Storefront & Public Content](plans/19-storefront-and-public-content.md) | Public pages, shop-state banners, the copy that carries legal weight | J |
| 20 | [Observability & Ops](plans/20-observability-and-ops.md) | Error tracking with PII scrubbing, structured logs, the drop-day ops page | P |
| 21 | [Infrastructure & Deployment](plans/21-infrastructure-and-deployment.md) | Hosting, deploys, backups, **a rehearsed restore** | P |

## 7. Build order

Each step is the smallest thing that unblocks the next. Read the "why here" column — it is the
argument for the sequence.

| # | Step | Plans | Own | Why here |
|---|---|---|---|---|
| 0 | Local environment + seed data; CI gate | 00 | J | Every later step is faster with a seeded environment, and the rare states (expiry, forfeit, full shop) never get exercised without one. Retrofitting is nobody's favourite afternoon. |
| 1 | Schema + migrations; auth; admin MFA + break-glass; `get_owned_order` / `require_admin` from day one | 01, 02 | P | The ownership dependency must exist **before the first order route does**, or it gets added to twenty routes retroactively and missed on one. |
| 2 | Pricing engine as a pure function + golden tests; generated TS client | 04, 05 | J | Pure and dependency-free, so it can be built and proven before any UI exists. Everything downstream displays its output. |
| 3 | Configurator UI; measurement capture, cross-checks, confirmation; `DRAFT → SUBMITTED` | 06, 07 | J | The product's differentiator, and the first thing worth showing the maker. |
| 4 | Order state machine + event log | 08 | P | Written once submission exists so the transition table has a real first transition, and before slots, which hook into it. |
| 5 | Slot enforcement, shop state, drops — transactional; Redis rate limiting | 09, 03 | L | Needs the state machine to hook slot accounting into. The concurrency test is the point; it cannot be written earlier. |
| 6 | Background worker + transactional outbox; slot-hold and quote expiry jobs | 11 | L | Immediately after slots, because **without it a forfeited slot stays occupied and the shop never reopens**. |
| 7 | Admin review/quote/approve; price simulator; `MockPaymentProvider`; queue computation | 12, 13, 10 | J | The whole lifecycle becomes exercisable end to end with no Stripe keys and no network. |
| 8 | Customer portal: order list, timeline, queue position, balance payment | 14 | J | Now there is something to display, in every state, from seed data. |
| 9 | Cross-user authorization test matrix, extended to every route built so far | 02 §6 | J | Listed once so it has an owner. It is **written at step 1 and grown continuously**; this is the audit, not the start. |
| 10 | Admin ops: denim price list + buffers, suppliers, shipping zones, revenue | 15, 16 | J | Turns the open items in §9 from blockers into data entry. |
| 11 | `StripePaymentProvider` + webhooks, idempotency, replay safety | 13 | L | Last of the money work, and safe to do late because the mock provider already proved the lifecycle. |
| 12 | Sourcing queue + scraper intake and price-monitoring endpoints | 17 | P | Maker convenience. Degrades to "no new suggestions" — never a bad customer experience. |
| 13 | Per-order messaging + email notifications via the outbox; maker inbox; drop announcements | 18 | J | Needs the outbox to already exist and be trusted. |
| 14 | Observability + ops page; backups with a rehearsed restore | 20, 21 | P | Before the first real drop, not after. A drop is a fixed-capacity event with no second chance. |
| — | Storefront polish | 19 | J | Rides on a minimal theme until the configurator is real. |

## 8. Risks

Each risk is owned by the plan that mitigates it.

| Risk | Mitigation | Owner |
| --- | --- | --- |
| Two customers take the last slot at once | Slot count enforced server-side in a locked transaction, proven by a concurrency test | [09](plans/09-capacity-slots-and-drops.md) |
| Unpaid submissions squat scarce slots | 72-hour hold, then `SLOT_FORFEITED` and the slot returns to the pool | [09](plans/09-capacity-slots-and-drops.md) |
| Drop scarcity attracts bots/abuse | Verified email, account+IP rate limits, one active order per customer per drop | [03](plans/03-security-baseline.md), [09](plans/09-capacity-slots-and-drops.md) |
| Queue position disputes | Position derives from `deposit_paid_at`, set from the Stripe webhook and never edited | [10](plans/10-queue-and-production-tracking.md), [13](plans/13-payments-and-stripe.md) |
| Fabric price rises before purchase | Per-fabric buffer + 14-day quote expiry; scraper price monitoring flags stale cost | [04](plans/04-pricing-engine.md), [17](plans/17-sourcing-and-scraper-intake.md) |
| Curated fabric discontinued mid-order | Availability confirmed at quote; if it dies after deposit, substitute or refund | [12](plans/12-admin-review-and-quoting.md) |
| Scraped third-party data on a commercial site | Maker-only behind admin auth; customers see curated fabrics with the maker's own photos | [17](plans/17-sourcing-and-scraper-intake.md) |
| Scraped content is untrusted input rendered to the admin | Escape on render, validate URL schemes — it targets the one account that can change prices | [17](plans/17-sourcing-and-scraper-intake.md) |
| Mispriced custom work | Estimate + mandatory maker approval before any charge | [12](plans/12-admin-review-and-quoting.md) |
| Deposit disputes | Non-refundable-once-cut stated at acceptance; published fit policy with `policy_accepted_at`; full audit trail | [12](plans/12-admin-review-and-quoting.md) |
| Measurement errors → unwearable garment | Guided capture, range bounds, cross-field checks, confirmation screen; flags surfaced at review | [06](plans/06-measurement-capture.md) |
| Notification never reaches the customer | Outbox with retries and a visible dead-letter state | [11](plans/11-background-jobs-and-outbox.md) |
| Pricing formula change silently repricing wrongly | Pure function with a golden test table; changes appear as a test diff | [04](plans/04-pricing-engine.md) |
| Another customer's measurements/address leak | Ownership in the WHERE clause, 404 not 403, route-walking authorization matrix in CI | [02](plans/02-identity-and-authorization.md) |
| Data loss | Automated snapshots + PITR, S3 versioning, and **a restore rehearsed before launch** | [21](plans/21-infrastructure-and-deployment.md) |
| Silent failure during a drop | Error tracking + ops page showing slot state, outbox depth, failed payments | [20](plans/20-observability-and-ops.md) |
| Scraper breakage | Internal tool only — degrades to "no new suggestions" | [17](plans/17-sourcing-and-scraper-intake.md) |

## 9. Open items

### 9.1 Blocked on the maker — numbers and copy
None block building. They are seed data behind an admin screen
([15](plans/15-admin-catalog-and-price-list.md)).

1. **Per-silhouette `yards_billed`, `base_labor_cost`, `build_time_days`** — the numbers that set every
   price and the queue's pace.
2. **Supplier lead times** — typical and worst case, per supplier.
3. **Shipping zone rates**, and which states count as "near".
4. **Hardware unit costs** — buttons, rivets, zippers, buckles.
5. **Fit & Alterations policy copy**, for the acceptance checkbox.
6. **Oversize thresholds** — at what inseam/waist an extra yard is needed.
7. **Drop cadence** — reopen as each slot frees, or batch to 5 and open all at once? Batching is the
   stronger drop; trickling keeps him busier.
8. **Sales tax** — whether the maker has nexus obligations; Stripe Tax if so.

### 9.2 Blocked on us — technical decisions
Each is marked `[ ] DECIDE` in its plan. Ordered by when it must be answered.

| Decision | Plan | Needed by |
| --- | --- | --- |
| Monorepo vs. two repos | [00](plans/00-development-environment.md) §3 | step 0 |
| Identity provider selection | [02](plans/02-identity-and-authorization.md) §2 | **step 1 — blocking** |
| Money representation: integer cents vs. `NUMERIC` | [01](plans/01-data-model-and-migrations.md) §4.1 | step 1 |
| Enforcement mechanism for "only `transition()` writes status" | [08](plans/08-order-lifecycle-state-machine.md) §4 | step 4 |
| Generated-client approach: types-only vs. generated methods | [05](plans/05-api-contract-and-typed-client.md) §6 | step 2 |
| Advisory lock vs. `FOR UPDATE` for the slot race | [09](plans/09-capacity-slots-and-drops.md) §4 | step 5 |
| Job runner: APScheduler vs. RQ/Celery | [11](plans/11-background-jobs-and-outbox.md) §6 | step 6 |
| Re-quote in place vs. new order on `EXPIRED` | [08](plans/08-order-lifecycle-state-machine.md) §8 | step 7 |
| Email provider and deliverability setup | [18](plans/18-messaging-and-notifications.md) §6 | step 13 |
| Hosting: AWS now vs. Render/Railway first | [21](plans/21-infrastructure-and-deployment.md) §3 | first deploy |
| Data retention and deletion path | [03](plans/03-security-baseline.md) §9 | before launch |

## 10. Changelog

| Version | Change |
| --- | --- |
| v2.0 | Decomposed into 22 component plans under `plans/`; this document became the index and roadmap. Content is unchanged in substance — every decision from v1.3 now lives in the plan that owns it. |
| v1.3 | Scope settled, security and engineering practices defined. |
</content>
