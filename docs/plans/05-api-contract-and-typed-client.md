# 05 — API Contract & Shared Types

**Status:** Scaffold — not started
**Build step:** §14 step 2 · **Owner:** [J]
**Depends on:** [[00-development-environment]], [[02-identity-and-authorization]]
**Unblocks:** every frontend document — [[07-configurator-and-submission]],
[[14-customer-portal]], [[15-admin-catalog-and-price-list]], [[19-storefront-and-public-content]]
**Source:** PRD §9, §12.2, §11.1

---

## 1. Purpose

The wire is where drift accumulates: a renamed field or a changed nullability breaks the frontend at
runtime, in front of a customer, with no compile error. **One language removes that failure mode
rather than tooling around it.** This document fixes the conventions that keep it removed.

> This plan used to be about generating a TypeScript client from FastAPI's OpenAPI schema, and most
> of it was pipeline — generate, commit, diff in CI, keep the operation ids stable. All of that was
> scaffolding around the fact that Python and TypeScript could not share a type. They can now, so
> the scaffolding is gone and what remains is the contract itself.

## 2. Shape

```
React + TypeScript (Vite)   ──REST/JSON──▶   Hono (TypeScript)
            └──────────────  shared/  ──────────────┘
                    Zod schemas + inferred types
```

The API holds **all** business logic: pricing, quoting, state machine, slots, queue, authorization,
payment orchestration, webhooks. The frontend renders and collects input.

**Both sides being TypeScript does not soften that boundary — it removes the language barrier that
used to enforce it.** The separation is now a decision rather than a consequence, which means it has
to be held deliberately. Nothing in `shared/` may import from `api/`, and no pricing, eligibility, or
state logic may live in `shared/` where the browser could reach it. `shared/` holds **shapes, not
behaviour**.

## 3. Route namespaces

| Prefix | Auth | Notes |
| --- | --- | --- |
| `/api/public/*` | none | Shop state, silhouettes, curated fabrics, policy copy. Generous per-IP rate limit. |
| `/api/me/*` | customer session | Profiles, saved configurations, orders, messages. **Never takes a `user_id`** — the session is the scope. |
| `/api/admin/*` | `requireAdmin` | Separate routes with their own unscoped queries and audit events. Never a flag on a customer route. |
| `/internal/sourcing/*` | service token | Scraper intake ([[17-sourcing-and-scraper-intake]]). |
| `/webhooks/stripe` | signature | [[13-payments-and-stripe]]. |

Order-scoped customer routes are nested — `/api/me/orders/{orderId}/…` — and always resolve through
`getOwnedOrder` ([[02-identity-and-authorization]]).

## 4. Request conventions

- Request bodies carry **ids and measurements only**, never money or state
  ([[03-security-baseline]] §2).
- Every schema: `.strict()`. Zod strips unknown keys silently by default, which is the wrong
  default here ([[03-security-baseline]] §2).
- Ids are UUIDs in path params; no sequential integers on the wire.
- `PATCH` bodies use explicit per-route allowlist schemas. Never `createInsertSchema(table).partial()`
  over a Drizzle table — that is the same mistake as a generic ORM partial-update, arrived at through
  a nicer API. It would happily accept `status` or `finalTotalCents`.

## 5. Response conventions

- Money as **integer cents** — a JSON number that is always whole
  ([[01-data-model-and-migrations]] §4.1). Never a decimal, never a formatted string.
- Timestamps ISO-8601 UTC with an explicit offset.
- Enums are `z.enum([...])` in `shared/`, giving a string union both sides use verbatim — the same
  values the database stores ([[08-order-lifecycle-state-machine]] statuses, sub-stages, shop state).
- A price is **never** returned as a bare total — always the full `Breakdown`
  ([[04-pricing-engine]]) so the UI can render lines without recomputing anything.
- Errors: generic client-facing messages, machine-readable `code`, no stack traces
  ([[03-security-baseline]] §9). Absent and forbidden are both **404**.

## 6. The `shared/` package

**DECIDED: no code generation.** One Zod schema per shape, exported from `shared/`, imported by
`api/` to validate at the boundary and by `web/` to type the response.

```
shared/
  schemas/        one file per resource — orders, fabrics, pricing, measurements
  index.ts        the public surface
```

- Schemas are the single definition. Types come from `z.infer<typeof Schema>` — never hand-written
  beside the schema, where the two can disagree.
- `web/` calls the API through a thin typed `fetch` wrapper that parses responses with the same
  schema. **Parsing on the client is not paranoia about our own server** — it is what turns a
  deployment skew between `web/` and `api/` into a clear error instead of `undefined` reaching a
  component.
- Nothing generated, nothing committed twice, no CI diff job. `tsc` is the check.

The old requirement for stable `operation_id`s is gone with the generator — there are no generated
symbols to keep stable. Route handler names are now an internal matter.

## 7. Versioning

v1 is a single-consumer API — the web app deploys with it. **No versioned URL prefix.** If the
scraper contract ever needs to change independently, `/internal/sourcing/*` gets its own version, not
the whole API.

## 8. Open questions

1. Pagination convention for admin lists (orders, sourcing candidates, messages). Cursor is right if
   these ever grow; with 5 concurrent orders, offset is honest for v1. Decide at step 7.

## 9. Definition of done

- [ ] Namespaces in §3 established before the first business route
- [ ] Every route validates its body against a `.strict()` schema from `shared/`
- [ ] Renaming a field in `shared/` fails `tsc` in both `api/` and `web/` — verified deliberately
- [ ] `shared/` contains no pricing, eligibility, or state logic — only shapes
- [ ] A money value round-trips API → TS type → rendered string as an integer, dividing exactly once
      in the formatter
</content>
