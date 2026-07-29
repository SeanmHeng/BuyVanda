# 19 — Storefront & Public Content

**Status:** Scaffold — not started
**Build step:** minimal theme from step 3; polish after the configurator is real · **Owner:** [J]
**Depends on:** [[05-api-contract-and-typed-client]], [[09-capacity-slots-and-drops]]
**Unblocks:** nothing technical — it is what makes the scarcity legible
**Source:** PRD §1, §3, §5.4, §6.4, §14 (closing note)

---

## 1. Purpose

The public surface has one job beyond looking right: **make the shop's state unmistakable.** A visitor
should know within a second whether they can order, and if not, when they might.

> Storefront polish rides on a minimal theme until the configurator is real. This document exists so
> the copy decisions are made deliberately, not typed into JSX at midnight.

## 2. Pages

| Page | Purpose |
| --- | --- |
| **Home** | What this is, the five-slot constraint stated plainly, current shop state, next drop |
| **Presets** | The silhouette range, with the curated denim available |
| **Custom commissions** | What free reign means, that it costs more, and that the maker approves |
| **How it works** | Configure → estimate → maker review → deposit → queue → balance → ship |
| **Sizing & measuring** | The guide behind the capture screens ([[06-measurement-capture]]) |
| **Fit & Alterations policy** | Public copy of the policy accepted at checkout |
| **FAQ / Terms / Privacy** | Deposit conditions, no-returns, data handling |

## 3. Shop state, everywhere it matters

Driven by the computed state from [[09-capacity-slots-and-drops]] §5:

| State | Visitor sees |
| --- | --- |
| `OPEN` | Slots remaining, straight into the configurator |
| `CLOSED_FULL` | **"Orders closed — 5 of 5 in production"**, plus `next_drop_at` if scheduled |
| `FORCE_CLOSED` | The maker's `closed_message`, plus next drop if set |
| `FORCE_OPEN` | Open, without a slot count |

Signed-in visitors always get the **save a configuration** path, with the standing caveat that it
confers no place in line and prices are re-quoted at submission.

## 4. Copy that carries legal and commercial weight

These are not decoration. Each exists because of a decision made elsewhere:

- **"Estimate" vs. "final quote."** The configurator's number is an estimate; the final price is set
  after the maker reviews measurements and reference images, and fabric price may change until the
  quote is issued ([[04-pricing-engine]] §8).
- **Never describe denim as sold at cost.** The buffer is retained, not credited back. This is a
  direct consequence of the plain-buffer decision and is **not optional**
  ([[04-pricing-engine]] §3).
- **Deposit is non-refundable once the denim is purchased or cut** — stated at acceptance, not buried
  in terms.
- **No returns or exchanges** — made to measure. Fit handled case by case against the published
  policy.
- **Two clocks:** price valid 14 days, slot held 72 hours.
- **No waitlist**, and saved configurations reserve nothing.

## 5. Scarcity done honestly

The drop model is first-come-first-served, and **that exclusivity is the intent**. The storefront
should say so rather than imply everyone who wants one can have one. Two things follow:

- Slot counts shown must be **live** — a stale "2 slots left" is worse than no number.
- The drop-announcement opt-in is the only thing offered to someone who missed it; it is marketing,
  not a queue ([[18-messaging-and-notifications]] §5).

## 6. Assets and imagery

Product photography is **the maker's own**. Scraped third-party product imagery never reaches a public
page ([[17-sourcing-and-scraper-intake]] §3) — a rights problem and a non-goal.

- [ ] **DECIDE:** does the storefront need a CMS, or is copy in the repo? With one maker and seven
      pages, **copy in the repo** is honest; policy copy that changes needs a git history anyway.

## 7. Non-goals restated here because they shape the design

Mobile apps, internationalization, multi-currency, standard/off-the-rack sizing, a public catalog of
third-party denim, returns and exchanges, rush upsells, multi-maker.

## 8. Testing

- Each shop state renders its correct banner from seeded data.
- Slot count matches the server's computed state (no cached number).
- The estimate disclaimer is present on every screen showing a pre-quote price.
- Lighthouse/accessibility pass on the public pages.

## 9. Definition of done

- [ ] Seven pages in §2 exist with real copy
- [ ] All four shop states render correctly
- [ ] Every clause in §4 appears where it is required
- [ ] No third-party product imagery on any public page
</content>
