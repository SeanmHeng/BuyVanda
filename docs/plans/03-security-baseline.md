# 03 — Security Baseline (cross-cutting)

**Status:** Scaffold — not started
**Build step:** applied continuously from step 1; rate limiting lands at step 5 · **Owner:** [P]
**Depends on:** [[02-identity-and-authorization]]
**Unblocks:** nothing directly — it is a constraint on every other plan
**Source:** PRD §11.1, §11.3–§11.5, §11.7, §11.10–§11.13

---

## 1. Purpose

Baseline practices are assumed. This document records the decisions and the **app-specific traps** —
the places where this particular design creates a vulnerability a generic checklist misses.
Authorization has its own document ([[02-identity-and-authorization]]) because it is large enough to
warrant one.

## 2. Never trust the client for money or state

The single highest-value rule in the system. The browser sends **selections**, never prices.

```ts
// The request body contains ONLY ids and measurements:
//   silhouetteId, fabricId, featureIds[], measurementProfileId, shippingAddress
// It NEVER contains: unit prices, subtotal, total, depositCents, yards, bufferPct,
//   queue position, status, priority, dropId, or userId.
```

Everything monetary is recomputed server-side from database rows at submission and again at quote
approval ([[04-pricing-engine]]). A client-supplied `total` is not "validated" — it is **ignored**.

The same applies to state: transitions go through the state machine on the server
([[08-order-lifecycle-state-machine]]), and `deposit_paid_at` — which sets place in line — is written
**only** by the verified Stripe webhook handler, never from a browser redirect to `success_url`
([[13-payments-and-stripe]]).

Every request schema is a Zod object with **`.strict()`**, so an unexpected key is a 400 rather than
a field that silently vanishes. Zod strips unknown keys by default — quietly, with no error — which
is the friendlier behaviour and the wrong one here. `.strict()` is not optional decoration; without
it a client can send `totalCents` and get a 200, having learned that the field is ignored rather
than rejected. A test walks every exported schema in `shared/` and fails on any that is not strict.

## 3. Input validation — domain bounds, not just types

- **Measurements:** positive, bounded to plausible human ranges (waist 20–70 in), unit enum
  (`in`/`cm`) **required**. A unit mixup is a ruined garment, so this is a correctness issue as much
  as a security one. Detail in [[06-measurement-capture]].
- **Ids validated by existence *and* state:** a `fabric_id` must be `is_curated` and active; a
  `feature_id` must be in the chosen silhouette's `applies_to`. Otherwise a crafted request orders a
  non-curated fabric or an incompatible feature.
- **Caps on quantities and free text** — notes, messages, custom requests — so a 10 MB message body
  cannot be posted. `z.string().max(n)` on every free-text field; there is no default limit.
- Money is integer cents throughout, and **the client never sends any**
  ([[01-data-model-and-migrations]] §4.1).

## 4. SQL injection

Drizzle's query builder parameterizes everything, so exposure is confined to where we bypass it:

- Raw SQL goes through the **`sql` template tag**, which parameterizes interpolated values:
  `sql\`... WHERE id = ${id}\``. Never build a query by string concatenation and pass the result in.
- **Identifiers cannot be parameterized.** Any dynamic `ORDER BY`, column filter, or table name comes
  from a hardcoded allowlist object, never from a request string. `sql.identifier()` still needs the
  value to have come from the allowlist first.
- Escape `%` and `_` in user input used in `LIKE` — fabric search in the admin panel
  ([[15-admin-catalog-and-price-list]]).
- The app's database role owns no DDL rights ([[01-data-model-and-migrations]]).

## 5. XSS and output encoding

React escapes by default, so the rules are narrow and absolute:

- No `dangerouslySetInnerHTML` on any customer- or scraper-supplied content: messages, notes,
  free-text custom requests, fabric names.
- **Scraped data is untrusted internet input rendered in the admin panel.** Titles, URLs, and prices
  from `sourcing_candidates` come from third-party sites we do not control — the sneakiest vector in
  the design, because it targets the one account that can change prices. Escape on render, and
  validate scraped URLs to `http`/`https` before putting them in an `href` (`javascript:` URLs).
  See [[17-sourcing-and-scraper-intake]].
- Response `Content-Type` always `application/json`; never reflect request content into HTML.
- CSP with no `unsafe-inline`, plus HSTS, `X-Content-Type-Options: nosniff`, `Referrer-Policy`.

## 6. Rate limiting

Tiered, because a drop open is a **legitimate** traffic spike that must not be throttled into failure.

| Surface | Limit |
| --- | --- |
| Login, password reset, email verification | Strict per-account **and** per-IP, exponential backoff |
| Order submission | Per-account (one active order per customer per drop) |
| Messaging, uploads | Modest per-account |
| Public read endpoints | Generous per-IP |

Per-IP limits alone are the wrong tool for submissions: dorms, offices, and mobile carriers share
addresses via CGNAT, so an aggressive IP limit blocks legitimate buyers at exactly the worst moment
while a determined abuser rotates addresses. Account-scoped limits plus verified email do the real
work; IP limits are a backstop against unauthenticated floods.

Implemented as **counters in Postgres**, behind a single `checkRateLimit()` function.

In-process counters are useless here — every Lambda invocation may be a fresh execution
environment, so a counter in memory is a counter of one request. The store has to be shared, and
Postgres is already the shared thing. At five concurrent commissions the write volume is trivial;
this is a row with a compound key and an expiry, not an engineering problem.

Keeping it behind one function is the point: if volume ever justifies Redis or DynamoDB, the change
is inside that function and no call site moves.

**API Gateway throttling is a separate, blunter layer** — per-route request ceilings that stop an
unauthenticated flood before it reaches Lambda at all. It cannot express any of the rules in the
table above, because those need to know who the user is and what is in the database. Use both; do
not mistake one for the other.

## 7. File uploads (embroidery reference images, supplier invoices)

- Cap size; verify the real content type by **sniffing magic bytes**, not by extension or the client's
  header.
- **Re-encode server-side** — strips EXIF (including GPS) and any embedded payload.
- **Reject SVG.** For this purpose SVG is a script-execution vector, not an image format.
- Store under **random keys** in a non-public S3 bucket; serve via short-lived presigned URLs so
  access respects the ownership check rather than being public-by-URL.

The maker's proof-of-purchase upload on the cost-entry screen ([[12-admin-review-and-quoting]] §6)
uses the **same path, unmodified**. An admin upload is not a trusted upload: the admin account is the
highest-value credential in the system ([[02-identity-and-authorization]] §4), and a bypass built for
convenience is a bypass an attacker inherits.

## 8. SSRF

If the backend ever fetches a scraped or customer-supplied URL — fabric images, sourcing request
links — block private IP ranges, `localhost`, and the cloud metadata endpoint (`169.254.169.254`),
and do not follow redirects into them. **A sourcing request URL is customer-supplied**
([[17-sourcing-and-scraper-intake]]), so this is a real path, not a theoretical one.

## 9. Secrets and PII

- No secrets in the React bundle; anything in the frontend is public. Server secrets in a secrets
  manager or env, never committed.
- The app stores **body measurements, addresses, and phone numbers** — modest but genuinely personal.
  TLS everywhere, encryption at rest, and measurements/addresses/tokens **stay out of application
  logs** and out of error-tracking payloads ([[20-observability-and-ops]]).
- Errors return generic messages to the client; stack traces and SQL go to logs only. Hono's error
  handler must never serialise the caught error into the response body — the default in most
  examples does exactly that, and a Drizzle error carries the query with it.
- [ ] **DECIDE:** a stated retention/deletion path for customer data, since accounts hold body
      measurements. Needed before launch, not before build. Drives the soft-delete question in
      [[01-data-model-and-migrations]].

## 10. Dependencies

Pin with `package-lock.json`; Dependabot on; `npm audit` in CI ([[00-development-environment]]).

One language tree now, but npm is the larger and more hostile of the two ecosystems — transitive
dependency counts are an order of magnitude higher than pip's, and typosquatting is routine. Prefer
few, well-known dependencies, and read what a package pulls in before adding it. The scraper repo
carries its own Python supply chain, watched separately.

## 11. Definition of done

- [ ] `.strict()` on every request schema, enforced by a test that walks everything `shared/` exports
- [ ] Security headers present on every response (asserted by test)
- [ ] Postgres-backed rate limiting live with the tiers in §6, behind one function
- [ ] Upload pipeline re-encodes and rejects SVG (tested with a crafted file)
- [ ] SSRF guard covering the metadata endpoint and private ranges (tested)
- [ ] PII scrubbing verified in the error tracker before launch
</content>
