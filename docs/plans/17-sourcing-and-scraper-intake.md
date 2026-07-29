# 17 — Sourcing Queue & Scraper Intake

**Status:** Scaffold — not started
**Build step:** §14 step 12 · **Owner:** [P]
**Depends on:** [[11-background-jobs-and-outbox]], [[15-admin-catalog-and-price-list]],
[[03-security-baseline]]
**Unblocks:** price freshness guarantees in [[04-pricing-engine]] §5
**Source:** PRD §4.2, §4.3, §5.3, §11.11, §11.5

---

## 1. Purpose

The maker cannot carry inventory, so the price list has to stay honest without him checking a dozen
supplier sites by hand. A scraper in a separate repo does the looking; **the maker does all the
deciding**.

## 2. Two jobs

1. **Discovery.** The scraper posts denim listings it finds to an internal endpoint. They appear in
   the admin **sourcing queue** with source, price, weight, and link.
2. **Price monitoring.** Re-checking fabrics already on the curated list and flagging ones whose price
   moved, so the maker knows when to update `cost_per_yard` or raise `price_buffer_pct`.

The second job is the one that protects the deposit.

## 3. The sourcing queue

The maker marks a listing **ignored**, **watching**, or **promoted**.

**Promoting creates or updates a `fabrics` row** — name, colour, weight, `cost_per_yard`, supplier —
which is what the configurator prices against.

> This is the **price list, not an inventory count.** Nothing here means the maker has fabric.

**Customers only ever see curated `fabrics` rows, never raw scraper output**
([[15-admin-catalog-and-price-list]] §3). Scraper output is maker-only, behind admin auth. A public
catalog of scraped third-party denim is a permanent non-goal.

## 4. Price monitoring and freshness

- Refresh runs on a schedule ([[11-background-jobs-and-outbox]] §2), stamping
  `fabrics.last_price_checked_at` and appending to `fabric_price_history`.
- **Scraped prices are suggestions, never automatic writes to `cost_per_yard`.** An automatic write is
  an untrusted third party setting the deposit basis.
- **Quoting never blocks on a live scrape.** A synchronous fetch at quote time would make quoting fail
  whenever a supplier site is slow or has changed layout. Submission **enqueues** a refresh; the maker
  sees the price age at review ([[12-admin-review-and-quoting]] §2).
- Older than **7 days** → flagged at review, confirm-or-correct before approval.

## 5. Customer-submitted sourcing requests (full custom)

On a commission the customer may request a specific fabric instead of choosing from the curated list:
a **link**, mill/fabric name, weight, and notes (`sourcing_requests`).

The maker confirms availability and **landed cost** before quoting; `confirmed_cost_per_yard` becomes
the deposit basis ([[12-admin-review-and-quoting]] §3).

> **The URL is customer-supplied.** If the backend ever fetches it, SSRF protection is mandatory, not
> theoretical — block private ranges, `localhost`, and `169.254.169.254`, and do not follow redirects
> into them ([[03-security-baseline]] §8).

## 6. The internal endpoint

`/internal/sourcing/*`:

- Authenticated with a **service token distinct from user auth**, scoped to this prefix,
  **rate-limited independently**, and rotated.
- **Treat the payload as hostile:** validate schema, bound string lengths, clamp prices to sane
  ranges, normalize URLs.
- Idempotent on `(source, external_id)` so a re-run does not duplicate the queue.

## 7. The XSS trap

> **Scraped data is untrusted internet input rendered in the admin panel.**

Titles, URLs, and prices come from third-party sites we do not control, and they are rendered in front
of **the one account that can change prices** — the sneakiest vector in the whole design. Escape on
render, no `dangerouslySetInnerHTML`, and validate scraped URLs to `http`/`https` before putting them
in an `href` ([[03-security-baseline]] §5).

## 8. Failure posture

Scraper breakage is an **internal tool problem**: it degrades to "no new suggestions" and stale
freshness flags, never a bad customer experience. Last successful run and stale-price count appear on
the ops page ([[20-observability-and-ops]]).

**Automated purchasing on third-party sites is out of scope, permanently.** Not built.

## 9. Testing

- Payload with a 10 MB title, a negative price, and a `javascript:` URL is rejected at the boundary.
- Re-posting the same `(source, external_id)` updates rather than duplicates.
- A scraped price never mutates `cost_per_yard` without a maker action.
- Sourcing request URL pointing at `169.254.169.254` is refused.
- Admin panel renders a title containing `<script>` inertly.
- Unauthenticated or wrong-token requests to `/internal/*` return 404/401 and are rate-limited.

## 10. Open questions

1. Does the backend fetch sourcing-request URLs at all (for a preview image), or only store them?
   **Storing only** removes the SSRF surface entirely. Recommendation: store only in v1.
2. Should promoting a candidate carry its photo into `fabrics.photo_key`? Third-party product imagery
   on a commercial site is a rights question — the PRD's position is the maker uses **his own
   photos**. Recommendation: no automatic photo carry-over.

## 11. Definition of done

- [ ] Service-token endpoint live, hostile-input validated, idempotent
- [ ] Queue with ignore/watch/promote, promotion writing a `fabrics` row
- [ ] Freshness stamps and history feeding the review-screen flag
- [ ] Escaping and URL-scheme validation proven by test
- [ ] No path by which scraper output reaches a customer
</content>
