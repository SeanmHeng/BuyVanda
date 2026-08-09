# 04 — Pricing Engine

**Status:** Scaffold — not started
**Build step:** §14 step 2 · **Owner:** [J]
**Depends on:** [[01-data-model-and-migrations]]
**Unblocks:** [[07-configurator-and-submission]], [[12-admin-review-and-quoting]],
[[13-payments-and-stripe]], [[16-shipping-and-tax]]
**Source:** PRD §5, §5.1–§5.4, §5.10
**Revised 2026-07-29:** margin moved out of computed labor into a single maker-set commission;
materials are pass-through and the denim buffer is now **trued up**. Downstream documents were
updated to match — see the PRD v2.1 changelog entry for the full list.

---

## 1. Purpose

Pricing bugs are money bugs. The calculation is isolated from everything that makes code hard to
test, and every number the customer ever sees comes out of it.

Most of the formula is now arithmetic over supplier costs. Exactly **one** number is a judgment call
— the commission — and it is made by a human, once, on a screen. That is the whole design: the
machine adds up receipts, the maker prices his own time.

## 2. The formula

```
denim_cost    = yards_billed × cost_per_yard × (1 + price_buffer_pct)
hardware_cost = Σ (qty × unit_cost)          # buttons, rivets, zipper, buckle…
addon_cost    = Σ material_price(feature)    # contrast panels, thread, anything consumed

materials     = denim_cost + hardware_cost + addon_cost
commission    = set by the maker at review — flat, by complexity (§4)

total         = materials + commission + shipping + tax
```

Worked example, the one to keep in your head:

```
materials   $100   (denim $75 incl. buffer, hardware and add-ons $25)
commission   $75   (complex build, mid-range)
total       $175
deposit      $75   denim incl. buffer, paid up front
balance     $100   → $90 if the denim lands at $65 (§3.2)
```

### 2.1 Rules that are not obvious from the formula

- **All margin is the commission.** Materials are pass-through. If the maker wants to earn more, the
  commission goes up — never the fabric line. This is a reversal of the previous model, and it is the
  reason the at-cost claim is now available to us (§3.3).
- **`yards_billed` is a fixed figure per silhouette, not computed from measurements.** The customer
  pays for the full cut, so a 2.3-yard and a 2.7-yard garment in the same silhouette cost the same.
  Set it to the whole-yard purchase the maker actually makes; remnants are the maker's.
  Maker-overridable per order.
- **Oversize guard.** Because yardage is flat, an unusually tall or large customer can exceed the
  standard cut. Each silhouette carries an `oversize_threshold` (e.g. inseam > 36" or waist > 44")
  that adds `oversize_extra_yards` **at review**. Under this model that is a straight materials
  increase, not a surcharge — the maker is buying more denim.
- **Features are material only; their labor is in the commission.** A deep yoke costs the customer
  whatever extra fabric it eats and nothing else; the hours it takes are what push the commission
  from $50 toward $100. A feature that consumes no material has **no price at all**.
- **Features and hardware must not double-count.** The physical part is always a `hardware` line. A
  feature may declare `required_hardware[]` so the part is added automatically.
- The customer-facing number pre-approval is an **estimate** and must be labeled as such. Materials
  are exact; the commission is a range until the maker looks.
- Every component cost is **snapshotted onto the order** at quote time
  ([[01-data-model-and-migrations]] §4.2).

## 3. Materials at cost — the buffer and the true-up

The maker cannot carry denim inventory, so **every order is sourced-to-order** and the fabric is
bought as soon as the deposit clears. The gap between quoting and buying is the risk, and the buffer
is how it is covered.

### 3.1 The buffer

A flat multiplier on `cost_per_yard`, stored as `fabrics.price_buffer_pct`, set by how volatile that
supplier actually is. Starting values: **10% default, 15–20% for imported/FX-exposed selvedge, 5% for
a stable domestic supplier.** Maker-editable per fabric.

The buffer is **insurance, not income**. It is collected because prices move, and it is settled
against what actually happened.

### 3.2 The true-up

When the maker places the supplier order he records what the denim actually cost (§3.4). At balance
time the difference is settled, and it only ever moves one way:

| Actual denim cost | Effect on the balance |
| --- | --- |
| **Under** the buffered figure | Difference is **credited** on the balance invoice |
| **Over** the buffered figure | **The maker eats it.** Nothing is added |

> **The accepted total is a ceiling.** A customer who accepts $175 will never be asked for $176.

That promise is worth stating on the acceptance screen. It is also the honest description of what a
buffer is: sometimes insurance pays out.

Call the credit what it is — **"Denim came in under estimate — $10"** or similar. It is **not a
discount**; nothing was marked down, and framing a returned overcharge as a saving is exactly the
kind of copy that ages badly on a public storefront. Copy owned by
[[19-storefront-and-public-content]].

### 3.3 The consequence: we may now say "at cost"

The previous model retained unused buffer, which made any at-cost claim false. With a true-up it is
true, and **the prohibition in the old §3 is retired.** Materials are sold at cost; the maker's
income is the commission, stated plainly as its own line.

This is worth using. Most made-to-measure shops cannot say it.

### 3.4 Recording the actual cost

The balance cannot be computed until the denim has been bought, which puts a new step in the maker's
workflow at `awaiting_denim` ([[08-order-lifecycle-state-machine]] §2).

- Full custom already has somewhere to put it: `sourcing_requests.confirmed_cost_per_yard`
  ([[17-sourcing-and-scraper-intake]]).
- Curated fabrics need an equivalent on the order — a recorded landed cost, entered when the supplier
  order is placed.
- `final_total` is **never rewritten**. The credit is its own line, so the record reads
  *quoted $175 → adjustment −$10 → charged $165* ([[01-data-model-and-migrations]] §4.2).
- The balance amount is computed **server-side** at checkout from the frozen quote plus the recorded
  actual. The browser never sends it ([[03-security-baseline]] §2).

**DECIDED:** an unrecorded cost **blocks balance checkout.** The alternative — silently falling back
to the quoted figure — costs the customer money they were owed and leaves no trace. The friction
lands on the one person who can clear it, holding the supplier invoice.

The entry screen shows the maker the whole picture at once, so the number is entered in context
rather than into a bare field ([[12-admin-review-and-quoting]] §6):

| Field | Notes |
| --- | --- |
| **Denim cost** | What he actually paid. The one required input. |
| **Proof of purchase** | **Required.** Screenshot or photo of the supplier invoice. Hardened upload path, [[03-security-baseline]] §7 |
| **Commission** | Read-only, as quoted |
| **Hardware and add-ons** | Read-only, as quoted |
| **Resulting balance** | Computed live, with the credit line, so he sees what the customer will see |

**DECIDED:** the proof upload is **required**, not optional. The true-up asks the customer to trust a
number only the maker can see, and a claim of overcharging is answered with the invoice or not at
all. Requiring it costs one screenshot per order and removes the argument entirely.

It is evidence, not decoration: it is never shown to the customer by default, but it exists if a
balance is ever questioned.

### 3.5 Quote expiry

Every quote carries `quote_valid_until` (default **14 days**) for the *price*. Past it the order moves
to `EXPIRED` and a re-quote reprices against current `cost_per_yard`. This is a **different clock**
from the 72-hour slot hold ([[09-capacity-slots-and-drops]]).

Expiry matters more under this model than the last one: the maker now absorbs overruns, so the
14-day window is the cap on how far a supplier price can move against him.

## 4. The commission

One number, set by the maker at review, covering **all** of his time — cutting, sewing, finishing,
embroidery, and any custom work.

- Range: **$50–$100** by complexity, stored as `shop_settings.commission_min` / `commission_max`
  ([[01-data-model-and-migrations]] §3) and editable by the maker
  ([[15-admin-catalog-and-price-list]]). It is a business number and it will move; it must never be a
  constant in code or a redeploy.
- Shown in the configurator as a **range**, clearly marked as pending review, alongside exact
  materials. The customer sees "$100 materials + $50–100 — final price set on approval."
- Reference images inform the judgment; the upload path is governed by [[03-security-baseline]] §7.
- Recorded on the order as its own snapshotted line and rendered as its own line to the customer.

Mechanically this is the old range-quoted-feature capability promoted from a per-feature mechanism to
a whole-order one. Feature-level `requires_review` flags are no longer needed for pricing; keep them
only if they should force the maker's attention for some other reason.

**DECIDED:** $50–100 to start, and the range lives in `shop_settings` precisely because the right
answer is unknown. Embroidery alone was previously priced $10–45 as labor on top of a per-silhouette
base, so a plain straight-leg and an elaborate custom now differ by at most $50 however many hours
separate them. That is accepted as a starting position, not a conclusion — the maker moves the
numbers once real builds have been timed (§9).

Because the range is data, changing it is a form edit. Orders already quoted keep the commission they
were quoted ([[01-data-model-and-migrations]] §4.2); a range change never reprices anything.

## 5. Price freshness at quote time

The deposit is only as good as `cost_per_yard`, and there is no inventory to fall back on.

- The scraper refreshes curated fabric prices on a schedule and stamps `last_price_checked_at`
  ([[17-sourcing-and-scraper-intake]]).
- **Quoting never blocks on a live scrape.** A synchronous fetch at quote time would make quoting
  fail whenever a supplier site is slow or has changed layout. Submission **enqueues** a refresh
  ([[11-background-jobs-and-outbox]]) and the maker sees the price age in the review screen.
- If a fabric's price is older than **7 days**, the admin review screen flags it and the maker
  confirms or corrects before approving.

Stale prices are now the maker's problem rather than the customer's — he quotes a ceiling and eats
anything above it — which makes the 7-day flag a protection for him, not a formality.

## 6. Implementation: pricing is a pure function

```ts
// no DB, no HTTP, no framework, no clock — every input is an argument
export function price(input: PricingInput): Breakdown
```

`PricingInput` is plain values — silhouette, fabric cost, buffer, features, hardware, zone, and the
**commission as an input**, not something the function decides. `Breakdown` returns **every line**,
never a bare total. The route loads rows and calls it; the function itself is deterministic and
trivially testable.

Two rules that keep it pure now that the frontend speaks the same language:

- **`price()` lives in `api/`, never in `shared/`.** Shipping it to the browser would let the client
  compute a total that looks authoritative, which is the exact confusion the whole design avoids.
  `shared/` may hold the `Breakdown` *shape*; the function that produces it stays server-side
  ([[05-api-contract-and-typed-client]] §2).
- **Every intermediate value is integer cents**, and rounding happens at named, deliberate points —
  not wherever a division lands ([[01-data-model-and-migrations]] §4.1). The golden table is what
  proves those points never move.

Three things fall out:

1. **The quote snapshot is just its output persisted.** No second code path.
2. **The admin price simulator** is the same function with hand-entered inputs
   ([[15-admin-catalog-and-price-list]]). Its job has changed: there is no longer a formula to
   validate, so it now answers *what does the maker actually take home on this garment* —
   commission against build hours. That question got more important, not less.
3. The estimate and the final quote cannot drift apart, because they are the same call with
   different inputs — the estimate passes the commission range, the quote passes the number.

### 6.1 Golden test table

A table-driven test covering, at minimum:

- plain preset
- multiple material-bearing add-ons
- oversize extra yards applied
- commission at the floor and at the ceiling
- **true-up credit applied** — actual under buffered, balance reduced
- **true-up overrun absorbed** — actual over buffered, total unchanged and adjustment zero
- **each** shipping zone ([[16-shipping-and-tax]])
- rounding edges, including deposit rounding (§7)

Any change to the formula shows up as a **diff in expected numbers** rather than a surprise on an
invoice. Part of the CI gate ([[00-development-environment]]).

## 7. Deposit calculation

Deposit = `denim_cost` **including buffer**, rounded up. Balance = `total − deposit − true_up_credit`.
Shipping and tax are part of the **balance**, not the deposit. Schedule and triggers in
[[13-payments-and-stripe]].

The deposit is unchanged by the true-up: it is collected before anyone knows the real number. The
settlement happens at the balance, which is the only point where both figures exist.

## 8. Customer-facing disclaimer

Three numbers reach the customer and they must not be confused:

1. **Estimate** — shown in the configurator, before review. Materials exact, commission as a range,
   labeled as an estimate.
2. **Final quote** — issued by the maker; price valid 14 days, slot held 72 hours, deposit amount and
   the non-refundable-once-cut condition stated on the acceptance screen. **The most the customer
   will ever pay.**
3. **Balance** — the quote minus the deposit, minus any true-up credit, with the credit shown as its
   own named line.

The estimate screen must state plainly that the final price is set after the maker reviews
measurements and reference images, and that fabric price may change until the quote is issued.
Copy owned by [[19-storefront-and-public-content]].

## 9. Open questions

Blocked on maker-supplied numbers (PRD §13): per-silhouette `yards_billed` and `build_time_days`;
hardware unit costs; oversize thresholds; the commission range. **None block building** — they are
seed data behind an admin screen. `base_labor_cost` is **no longer needed** and can come off that
list; `silhouettes.build_time_days` still matters for turnaround
([[10-queue-and-production-tracking]] §4).

1. Whether $50–100 clears the maker's own hourly bar (§4). A pair of made-to-measure jeans is a lot
   of hours, and the commission is now the only thing paying for any of them. The range is editable,
   so this is a number to revisit with the simulator once real builds have been timed — but revisit
   it **before** launch pricing is set, not after a drop has sold out at the wrong price.
2. Tax handling — see [[16-shipping-and-tax]].

## 10. Definition of done

- [ ] `price()` importable with no framework, DB, or clock dependency
- [ ] `Breakdown` returns every line item, and the API never constructs a total by hand
- [ ] Commission is an input to `price()`, sourced from the order, never computed
- [ ] True-up credit computed server-side and rendered as its own named line
- [ ] Overrun proven to leave the customer's total untouched
- [ ] Golden test table green in CI and covering every case in §6.1
- [ ] Simulator wired to the same function and reporting take-home per garment
