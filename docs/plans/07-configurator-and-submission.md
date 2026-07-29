# 07 — Configurator & Submission

**Status:** Scaffold — not started
**Build step:** §14 step 3 · **Owner:** [J]
**Depends on:** [[04-pricing-engine]], [[05-api-contract-and-typed-client]],
[[06-measurement-capture]]
**Unblocks:** [[08-order-lifecycle-state-machine]], [[12-admin-review-and-quoting]]
**Source:** PRD §1, §4.1, §4.2, §5.4, §6.4, §11.1

---

## 1. Purpose

> The differentiating feature is the configurator.

Measurements + denim + design features → estimated quote → maker approval → deposit → production
queue. Off-the-shelf commerce cannot do measurement-driven pricing, maker approval, staged payment,
capacity-gated ordering, or a production queue. **That gap is the product.**

## 2. The two product types

### 2.1 Preset design
1. Visitor browses preset silhouettes and sees the shop's open/closed state
   ([[09-capacity-slots-and-drops]]).
2. Picks silhouette + denim from the **curated denim list** — maker-selected fabrics flagged
   `reorderable`, i.e. reliably purchasable on demand — plus optional design features.
3. Enters or selects a measurement profile. **Sign-in required at this point.**
4. Sees an **estimated total** from the pricing formula.
5. Submits — **only possible while a slot is free**. Order enters `SUBMITTED` and holds a slot.

### 2.2 Full custom commission
Same spine, three differences:

- The **commission** lands higher in its range — a one-off costs more of the maker's time, and
  complexity is what moves that number ([[04-pricing-engine]] §4). It is no longer a custom-only
  surcharge: every order carries a commission, because it is the only thing paying for labour.
- The customer may submit a **denim sourcing request** instead of choosing from the curated list: a
  link, mill/fabric name, weight, and notes. The maker confirms availability and landed cost before
  quoting; the deposit reflects the actual sourced denim cost
  ([[17-sourcing-and-scraper-intake]]).
- **Free-text design requests** are allowed alongside the structured features, priced by hand during
  review.

Custom commissions consume the **same slots** as presets — there is one pool of five.

## 3. Pricing display rules

- Everything monetary is computed **server-side**. The browser posts ids and measurements only; a
  client-supplied total is ignored ([[03-security-baseline]] §2).
- The estimate is the `Breakdown` from [[04-pricing-engine]], rendered line by line.
- **Materials are exact; the commission is a range.** The estimate reads "$100 materials + $50–100,
  final price set on approval" — clearly marked pending review, never a fabricated point estimate
  ([[04-pricing-engine]] §4).
- The screen must state plainly that the final price is set after the maker reviews measurements and
  reference images, and that fabric price may change until the quote is issued.
- **Materials are sold at cost, and we may now say so.** The denim line is the buffered figure,
  labelled as including a price buffer that is settled against the real cost at balance
  ([[04-pricing-engine]] §3). The prohibition in the previous version of this document is retired.
- What the customer still never sees is the arithmetic: no raw `cost_per_yard`, no
  `price_buffer_pct`, no multiplier — one final cost per line.

## 4. Validation of selections

Ids are validated by **existence and state**, not just type ([[03-security-baseline]] §3):

- `fabric_id` must be `is_curated` and active (preset path)
- `feature_id` must be in the chosen silhouette's `applies_to`
- `measurement_profile_id` must belong to the caller ([[02-identity-and-authorization]] §5.3)
- Reference image uploads go through the hardened upload path ([[03-security-baseline]] §7)

## 5. Saved configurations

Any signed-in customer can build and **save a configuration** at any time — silhouette, fabric,
features, measurement profile. They exist so a customer can submit **in one click the moment a drop
opens**.

> They confer **no place in line and no reservation.** This is the deliberate alternative to a
> waitlist, which was rejected because it recreates a second queue and dilutes the limited-drop model.

- A saved configuration shows an **indicative** price only, and must say prices are re-quoted at
  submission — the fabric price will likely have moved.
- A `SLOT_FORFEITED` order's configuration is kept as a saved configuration the customer can resubmit
  at the next drop ([[09-capacity-slots-and-drops]]).

## 6. Submission

`DRAFT → SUBMITTED` goes through the state machine ([[08-order-lifecycle-state-machine]]), inside the
same transaction that claims a slot ([[09-capacity-slots-and-drops]] §4). Preconditions:

- shop state is `OPEN` or `FORCE_OPEN`
- a slot is free, counted **server-side in the transaction** — not by hiding the button
- the customer's email is verified
- the customer has no other active order in this drop
- the measurement confirmation screen was completed

On success the order snapshots measurements and the estimate, records any measurement flags, and
enqueues a fabric price refresh ([[04-pricing-engine]] §5).

## 7. Failure modes worth designing for

| Case | Behaviour |
| --- | --- |
| Slot taken between page load and submit | Clear "the last slot just went" message, configuration saved automatically, no error page |
| Fabric deactivated mid-session | Re-validate at submit; explain and offer the current curated list |
| Measurement flag raised | Confirmation step, not a block ([[06-measurement-capture]] §4) |
| Shop closes mid-session | Reflect live shop state, do not let the submit button lie |

## 8. Open questions

1. Does the configurator allow **multiple garments per order**? Assumed **no** for v1 — one garment,
   one order, one slot. Worth confirming, because it touches the slot model.
2. ~~Is the commission fee shown as its own line or folded into labor?~~ **Its own line, always.**
   There is no labor line left to fold it into ([[04-pricing-engine]] §2).
3. How many reference images per feature? One, assumed.

## 9. Definition of done

- [ ] Preset and custom paths both reach `SUBMITTED`
- [ ] No price of any kind is accepted from the client (asserted by test)
- [ ] Materials render exactly and the commission renders as a range with the pending-review label
- [ ] Saved configurations round-trip and prefill a submission
- [ ] All four failure modes in §7 handled without an error page
</content>
