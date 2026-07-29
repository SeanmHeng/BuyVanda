# CLAUDE.md

## The project

BuyVanda — a made-to-measure denim shop for **one maker working alone**. Capacity is the product:
**five commissions at a time**, sold as drops. The differentiator is the configurator
(measurements + denim + features → estimate → maker approval → deposit → visible production queue).

```
BuyVanda/            one repo — API, web, and docs together
  api/               FastAPI, SQLAlchemy, Alembic, pricing, the worker (not started)
  web/               React + TypeScript (Vite)
  docs/PRD.md        product decisions, build order, risk table — the index
  docs/plans/        22 numbered plans (00 → 21), in dependency order
```

Monorepo, decided: the web app and the API share a generated OpenAPI client, so drift has to be one
CI job, not a cross-repo dance. **The scraper gets its own repo** when it's built at step 12 — its own
deploy cadence, its own trust boundary, and it talks to the API over `/internal/sourcing/*` like any
other client.

**`docs/plans/` is the source of truth.** Each plan owns its area; the PRD is the index. When the PRD
and a plan disagree, the plan wins. When code and a plan disagree, say so — don't silently pick one.
Read the relevant plan before answering questions about a feature.

## How I work (read this first)

I'm a junior dev. **This project is how I learn.** I write the code; you help me understand it.

1. **Don't write code unless I ask.** Default to explaining, sketching, and pointing at the file
   and line. I'll say "implement it", "write it", "you do it" when I want code from you.
2. **When I ask a "how do I" question, answer the question** — concepts, trade-offs, the one-line
   shape of the solution. Not a finished implementation I can paste.
3. **Snippets are fine, files are not.** A few lines to show a pattern is teaching. A complete
   working module is doing my homework.
4. **Review what I wrote when I ask.** Tell me what's wrong and why. Let me fix it.
5. **Tell me when I'm heading somewhere bad** before I've built on top of it, not after.
6. **One exception — security.** If you spot a real security problem (auth bypass, injection,
   leaked secret, missing authorization check, unsafe defaults), tell me what it is, then fix it
   yourself. Don't wait for permission. Explain the fix after.

Plans are tagged **[J]** I implement · **[P]** we design together, I implement · **[L]** you
implement and walk me through it. The split is by blast radius: money movement and concurrency
(09, 11, 13) are poor places to learn on live orders. Everything else is mine.

## Architecture

```
React + TypeScript (Vite)        storefront · configurator · customer portal · admin panel
        │  REST/JSON
FastAPI (Python)                 ALL business logic: pricing, quoting, state machine, slots,
        │                        queue, authorization, payment orchestration, webhooks
        ├── PostgreSQL           + Alembic migrations
        ├── Redis                rate limiting + background job queue
        ├── S3                   fabric photos, embroidery reference uploads (private bucket)
        ├── Identity provider    credentials, password reset, email verification
        └── Stripe               Checkout Sessions + webhooks
                ▲
        Scraper (separate repo)  POSTs to /internal/sourcing/* with a service token

        + a worker process       scheduled jobs and the transactional outbox
```

Node is build tooling for the React app only — **there is no Node server**. The frontend renders and
collects input; it never decides anything that costs money or changes state.

### Route namespaces

| Prefix | Auth | Notes |
| --- | --- | --- |
| `/api/public/*` | none | Shop state, silhouettes, curated fabrics, policy copy |
| `/api/me/*` | customer session | **Never takes a `user_id`** — the session is the scope |
| `/api/admin/*` | `require_admin` | Separate routes, own unscoped queries, own audit events |
| `/internal/sourcing/*` | service token | Scraper intake |
| `/webhooks/stripe` | signature | Payment truth |

Order-scoped customer routes nest under `/api/me/orders/{order_id}/…` and always resolve through
`get_owned_order`.

## Invariants — don't break these without saying so out loud

These are the expensive ones. Each is owned by a plan; go read it before arguing with the rule.

1. **Money is never a float.** `Decimal` or integer cents in the column, the Python type, and the
   JSON — including the frontend. → [01 §4.1](docs/plans/01-data-model-and-migrations.md)
2. **Never trust the client for money or state.** Request bodies carry ids and measurements only —
   never prices, totals, yards, status, priority, `drop_id`, or `user_id`. A client-supplied total
   is *ignored*, not validated. Every request model sets `extra="forbid"`.
   → [03 §2](docs/plans/03-security-baseline.md)
3. **Ownership belongs in the WHERE clause**, not an `if` after fetching. Order routes take
   `Depends(get_owned_order)` and never a bare `order_id`. Missing and forbidden both return
   **404**, never 403. Every id in a request body is an object reference and needs the same check.
   → [02 §5](docs/plans/02-identity-and-authorization.md)
4. **`transition()` is the only writer of `order.status`.** Legality lives in one `TRANSITIONS`
   table, every transition writes an `order_event` in the same transaction, and re-firing a
   transition is a no-op — no duplicate event, no duplicate email.
   → [08 §4](docs/plans/08-order-lifecycle-state-machine.md)
5. **`deposit_paid_at` is written only by the verified Stripe webhook.** It sets place in line.
   Never from a browser redirect to `success_url`. → [13](docs/plans/13-payments-and-stripe.md)
6. **A catalog row is a template; an order row is a record.** Everything quoted against is
   snapshotted onto the order at quote time (measurements, yards, cost per yard, buffer, breakdown,
   feature and hardware prices, shipping). If an order field can be derived from a catalog row at
   read time, that's probably a bug. → [01 §4.2](docs/plans/01-data-model-and-migrations.md)
7. **Pricing is a pure function** returning a full `Breakdown`, covered by a golden test table. The
   API never returns a bare total — always the breakdown, so the UI renders lines without
   recomputing. → [04](docs/plans/04-pricing-engine.md), [05 §5](docs/plans/05-api-contract-and-typed-client.md)
8. **Outbound side effects go through the outbox**, enqueued inside the same transaction as the
   change that caused them. → [11](docs/plans/11-background-jobs-and-outbox.md)
9. **Public ids are UUIDs.** Defense in depth against enumeration, not authorization.
10. **Every schema change is a reversible Alembic migration.** The app's DB role holds no DDL
    rights; migrations run as a separate role. Data migrations are separate revisions from schema
    migrations.

## Vocabulary

Use these words the way the plans use them — precision here prevents real bugs.

- **Drop** — a capacity opening. **Slot** — one of the 5 concurrent commissions. A slot is claimed
  at `SUBMITTED` and released at `READY`, `DECLINED`, `SLOT_FORFEITED`, or `CANCELLED`.
- **Two different clocks, never conflate them:** the **72-hour slot hold** (`slot_hold_expires_at`,
  unpaid → `SLOT_FORFEITED`) and the **14-day quote validity** (`quote_valid_until`, price goes
  stale → `EXPIRED`).
- **Estimate** — the pre-approval number, always labeled as an estimate. **Quote** — the maker's
  approved `final_total`. No charge ever happens before maker approval.
- **Preset** vs **full custom** — curated denim and fixed silhouettes vs. free reign, priced higher.
- **Feature price is labor only.** The physical part is always a separate `hardware` line, or
  features and hardware double-count.
- Lifecycle: `DRAFT → SUBMITTED → QUOTED → DEPOSIT_PAID → IN_PRODUCTION → READY → BALANCE_PAID →
  SHIPPED → COMPLETED`, plus `DECLINED`, `SLOT_FORFEITED`, `EXPIRED`, `CANCELLED`.

## KISS

The rules, in order:

- **Simplest thing that works.** No abstraction until there are three real uses for it.
- **No speculative features.** Build what the current plan step asks for, nothing extra.
- **Boring over clever.** If it needs a comment to explain the trick, use the obvious version.
- **Match the surrounding code** — naming, structure, comment density.
- **Delete rather than keep around.** No commented-out code, no `_old`, no "might need this".
- **Small, obvious names.** `order_total`, not `calc_ord_tot_v2`.

## Rules for you

- Answer at the altitude I asked. Short question → short answer.
- No summaries of what you just did unless I ask.
- Don't refactor, reformat, or "improve" files I didn't ask about.
- Don't add dependencies without asking. Say what it's for and what it costs.
- If you're unsure what I mean, ask one question. Don't build both versions.
- Never say something is done or working unless you verified it. Say what you actually checked.
- Don't commit or push unless I ask.
- Plans carry `[ ] DECIDE` markers for open technical choices. If one blocks the work, point at it
  and give me a recommendation with the trade-off — don't quietly pick for me.

## Conventions

- Python: type hints on signatures, `snake_case`, no bare `except:`, `Decimal`/cents for money.
- TypeScript: no `any`, `camelCase` values, `PascalCase` components and types. API types come from
  the generated OpenAPI client — don't hand-write a response interface.
- FastAPI: explicit `operation_id` on every route (it names the generated TS symbol).
- SQLAlchemy: never f-string into `text()`; dynamic identifiers come from a hardcoded allowlist.
- React: no `dangerouslySetInnerHTML` on customer- or scraper-supplied content, ever.
- Secrets live in `.env`, never in code, never in a commit. Nothing secret in the React bundle.
- Tests that carry weight: pricing golden table, the slot-race concurrency test, the cross-user
  authorization matrix, webhook replay.
