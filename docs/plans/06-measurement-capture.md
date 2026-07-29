# 06 — Measurement Capture & Validation

**Status:** Scaffold — not started
**Build step:** §14 step 3 · **Owner:** [J]
**Depends on:** [[01-data-model-and-migrations]], [[05-api-contract-and-typed-client]]
**Unblocks:** [[07-configurator-and-submission]], [[12-admin-review-and-quoting]]
**Source:** PRD §4.4, §11.4

---

## 1. Purpose

> The largest product risk in the whole design.

Made to measure means no returns, so one transposed number is a garment nobody can wear, a deposit
dispute, and the maker's time gone. **Arithmetic is a far cheaper place to catch that than a
chargeback.**

## 2. Guided capture

Each field has a **diagram** and a **one-line instruction** ("measure over the widest part of the
seat, standing").

The unit selector (`in`/`cm`) is **explicit and required** — never defaulted, never inferred. An
unmarked cm value read as inches is the worst single failure mode in the product. `units` is stored
on the profile and on the order snapshot.

Fields (per `measurement_profiles`): waist, hip, thigh, knee, leg_opening, front_rise, back_rise,
inseam, outseam, plus `fit_preference` and free-text `notes`.

- [ ] **DECIDE:** whether to collect **height**. It is the input for the inseam plausibility check in
      §4 and costs one field. Recommendation: collect it, optional, clearly marked as used only for
      sanity checking.

## 3. Range validation

Each measurement bounded to a plausible human range — e.g. waist 20–70 in — with the unit taken into
account. Enforced by Pydantic at the boundary ([[03-security-baseline]] §3), not only in the browser.

## 4. Cross-field sanity checks

Bounds alone will not catch a transposition, because **32 and 23 are both valid waists**.
Relationships between measurements will:

| Check | Rule |
| --- | --- |
| Rise consistency | `outseam ≈ inseam + front_rise` — flag if off by more than a tolerance |
| Body proportion | `hip > waist` for most bodies |
| Taper | `thigh > knee > leg_opening` |
| Height | inseam plausible against stated height, if collected |

> These are **warnings, not hard blocks.** Real bodies are varied, and a hard block on an unusual but
> correct measurement loses a sale.

Flag it, make the customer confirm, and **surface the flag to the maker at review**.

- [ ] **DECIDE:** the tolerance on the rise check. Needs the maker's input — it is the one rule that
      will fire on correct measurements if set too tight.

## 5. Confirmation screen

Before submission, all values are shown back in a summary the customer **explicitly confirms**.
Flagged fields are highlighted with the rule that fired, in plain language ("your hip measurement is
smaller than your waist — that's unusual, please double-check").

## 6. Flags reach the maker

Anything flagged is recorded on the order as a `measurement_flags` row (`order_id`, `field`, `rule`,
`message`), so the maker sees it **during review, not after cutting**
([[12-admin-review-and-quoting]]).

## 7. Snapshotting

Measurements are **snapshotted onto the order** at submission as `measurement_snapshot` (jsonb),
including units. **Editing a saved profile must never change a placed order**
([[01-data-model-and-migrations]] §4.2).

## 8. Authorization note

`measurement_profile_id` in a submission body is an object reference and needs an ownership check —
submitting with someone else's profile is a real IDOR path, not a theoretical one
([[02-identity-and-authorization]] §5.3). Measurements are also PII and must stay out of logs and
error payloads ([[03-security-baseline]] §9).

## 9. Testing

- Unit tests per rule, including the transposition case the bounds miss (waist 23 / hip 22).
- A cm-entered profile priced identically to its inch equivalent.
- Flags persisted on the order and rendered on the admin review screen.
- Profile edited after submission → order snapshot unchanged.

## 10. Open questions

1. Collect height? (§2)
2. Rise-check tolerance (§4).
3. Whether to offer a "measured by a tailor" checkbox that suppresses warnings. Tempting; probably
   a way to lose the protection the section exists for. Default: no.

## 11. Definition of done

- [ ] Every field has a diagram and an instruction line
- [ ] Unit selector required, no default
- [ ] All four cross-field checks implemented as warnings with confirmation
- [ ] Flags written to `measurement_flags` and visible in admin review
- [ ] Snapshot isolation proven by test
</content>
