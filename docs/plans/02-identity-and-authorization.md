# 02 — Identity & Authorization

**Status:** Scaffold — not started
**Build step:** §14 step 1 (dependencies from day one), test matrix formalized at step 9 · **Owner:** [P]
**Depends on:** [[01-data-model-and-migrations]]
**Unblocks:** every route in the system
**Source:** PRD §9.2, §11.2, §11.6

---

## 1. Purpose

Authentication is delegated. **Authorization is entirely ours**, and object-level checks are where
small apps leak. This document defines both halves and the test that keeps the second one honest.

## 2. Authentication — delegated

The identity provider owns credentials, sessions, password reset, and email verification. The API
owns role checks and ownership checks. **No hand-rolled password hashing, no session table.**

**DECIDED: AWS Cognito.** It satisfies the requirement that actually mattered — MFA with more than
one enrollment per account, for the break-glass case in §4 — and it keeps identity inside the same
account and bill as the rest of the infrastructure ([[21-infrastructure-and-deployment]]).

Two costs came with that choice, and both are real:

- **No local emulator.** Cognito was the weakest candidate on the fourth selection criterion — a
  clean way to run locally. Development points at a **real dev user pool**, free at this volume, and
  the test suite stubs token verification so it needs no network
  ([[00-development-environment]] §4).
- **The hosted UI is dated and awkward to restyle.** Expect to build sign-in, sign-up, and reset
  screens against the SDK rather than redirecting to a hosted page. More work than Clerk would have
  been; that was the trade.

`users.idp_subject` is the join key — the Cognito `sub` claim. The local `users` row owns role,
contact preference, and `email_verified_at` mirrored from the pool. **Role lives in our database,
not in a Cognito group or a custom claim**: a token is a cached assertion, and an admin flag that
survives in an unexpired token after we revoke it is exactly the failure this separation prevents.

## 3. Sessions

- Tokens in **httpOnly, Secure, SameSite=Lax cookies**, not `localStorage`. localStorage tokens are
  readable by any XSS; cookie flags make one bug non-catastrophic instead of total.
- Short-lived access tokens with refresh; **server-side revocation** on logout and password change.
- CSRF protection on cookie-authenticated state-changing routes: SameSite plus a double-submit token.
- Generic auth error messages — no "that email isn't registered."
- **Email verification required before submitting an order.** This doubles as abuse control during a
  drop ([[09-capacity-slots-and-drops]]).

## 4. The admin account

One admin account is the entire business — revenue view, price list, order control. It is the
highest-value credential in the system.

- **MFA required** on every admin account.
- **A second, break-glass admin account** with a separate MFA enrollment. A lost phone with the only
  enrollment locks the maker out of his own shop mid-drop. Both accounts audited.
- Role is `users.role`; admin routes are **separate routes** behind `requireAdmin` with their own
  unscoped queries and their own audit events.

## 5. Object-level authorization (IDOR)

IDOR is when a route trusts an id from the request without verifying the caller owns the thing it
points at: `GET /orders/42` returning order 42 merely because *someone* is logged in. Here that
discloses another customer's **body measurements, home address, phone number, and order value**.

It is the most likely real vulnerability in this design because every route is id-addressed, the
check must be repeated on every one of them, and forgetting it produces no error, no test failure,
and no visible symptom.

### 5.1 The rule

> Ownership belongs in the **WHERE clause**, not in an `if` after fetching. A query that can return
> another user's row has already failed, whatever the code below it does.

```ts
// Hono middleware — both predicates in the same WHERE clause
const getOwnedOrder = createMiddleware(async (c, next) => {
  const user = c.get('user')
  const order = await db.query.orders.findFirst({
    where: and(eq(orders.id, c.req.param('orderId')), eq(orders.userId, user.id)),
  })
  if (!order) return c.json({ code: 'not_found' }, 404)  // 404, never 403 — see 5.2
  c.set('order', order)
  await next()
})
```

Every order-scoped route mounts this middleware and reads `c.get('order')`, **never the raw
`orderId` param**. The check cannot be forgotten because there is no other way to obtain the object.

Typing `c.get('order')` through Hono's context variable map is what makes that true at compile time
rather than by convention — a handler that skipped the middleware should not type-check.

### 5.2 Return 404, not 403

A 403 confirms the row exists, turning the endpoint into an existence oracle that leaks order volume
and lets an attacker map valid ids. Absent and forbidden must be indistinguishable.

### 5.3 IDOR on write is the half people miss

Guarding reads is intuitive; the same flaw on submission is easier to exploit and does more damage.
**Every id in a request body is an object reference** and needs the same check:

- `measurement_profile_id` — submitting with someone else's profile
- `saved_configuration_id`, shipping address ids
- `order_id` on a message post — writing into another customer's thread
- Nested routes: for `/orders/{oid}/messages/{mid}`, verify the message belongs to that order **and**
  the order belongs to the caller. Checking `mid` alone is the classic nested-IDOR bug.

**Mass assignment** is the adjacent flaw. A `PATCH` body containing `user_id`, `status`, `priority`,
`deposit_paid_at`, or `final_total` must be **rejected, not merged**. `.strict()` Zod schemas
([[03-security-baseline]]) plus explicit per-route field allowlists — never spread a parsed body into
an update. `db.update(orders).set(body)` is the mass-assignment bug written in TypeScript.

### 5.4 Non-obvious surfaces in this design

- **S3 reference images.** A presigned URL *is* an object reference. Bucket stays private, keys are
  random (never `orders/{id}/ref.jpg`), URLs minted only **after** the ownership check, short expiry.
  A public bucket makes every other check here decorative.
- **Admin bypass sprinkled inline.** Do not write
  `if not user.is_admin and order.user_id != user.id` scattered through handlers — that pattern gets
  inverted or dropped during a refactor. Separate routes, `requireAdmin`, separate queries.
- **Stripe webhooks** resolve the order via `provider_ref` from the signed payload, never via an id
  supplied by a client ([[13-payments-and-stripe]]).
- **Queue and drop reads.** Position is derived server-side for the caller's own order. There is no
  endpoint that takes an arbitrary `order_id` and returns its position or status
  ([[10-queue-and-production-tracking]]).
- **Message attachments** inherit the thread's ownership check, not just the message id.

### 5.5 What is not a defense

- UUID public ids raise the cost of enumeration. They are **not** a fix — a guessable id is a
  weakness, but the missing check is the vulnerability.
- Hiding the UI is not authorization. Every endpoint is reachable directly with curl.
- Rate limiting slows enumeration; it does not stop a targeted request.

## 6. Proving it, permanently

Manual review does not survive the twentieth route. A **parametrized test** creates two customers and
one admin, then walks the **entire route table**, asserting that:

- user B receives **404** on every one of user A's objects, on reads *and* writes
- customer credentials are rejected on every admin-only path
- admin routes still write their audit event

New routes enter the matrix **by construction** — the test enumerates Hono's registered routes
(`app.routes`) rather than a hand-maintained list, so coverage cannot quietly rot. It is written
early (step 1) and grown continuously; step 9 in the roadmap is when it is audited for completeness,
not when it starts.

## 7. Open questions

1. Whether admins get a read-only "view as customer" path for support. Convenient, and a classic
   place for an ownership check to be bypassed. Default: no, in v1.

## 8. Definition of done

- [ ] Cognito dev user pool live, integrated, and stubbed in tests
- [ ] `getOwnedOrder` / `requireAdmin` exist before the first order route does
- [ ] Two admin accounts with independent MFA enrollments
- [ ] Route-table-walking authorization matrix in CI, green, and failing when a route is added without
      an ownership dependency
</content>
