# 18 — Messaging & Notifications

**Status:** Scaffold — not started
**Build step:** §14 step 13 · **Owner:** [J]
**Depends on:** [[11-background-jobs-and-outbox]], [[14-customer-portal]]
**Unblocks:** nothing — but it is what makes "case by case" fit handling workable
**Source:** PRD §5.8, §5.9, §6.4, §9.4

---

## 1. Purpose

Two related things: the **per-order thread** (a record that survives email loss) and the **outbound
notifications** that get someone to look at it. The second is where money is lost when it fails.

## 2. Per-order threads

- Each order has a message thread visible to **its owner and the maker**.
- **The thread is the record.** It lives in the database and survives email loss — which is what makes
  case-by-case fit handling ([[12-admin-review-and-quoting]] §7) defensible rather than
  he-said-she-said.
- Maker-side: **one inbox** listing threads with unread counts.
- Attachments allowed, through the hardened upload path ([[03-security-baseline]] §7).

### 2.1 Authorization

`order_messages` is the classic nested-IDOR shape. For `/orders/{oid}/messages/{mid}`, verify the
message belongs to that order **and** the order belongs to the caller. Checking `mid` alone is the
bug ([[02-identity-and-authorization]] §5.3). **Attachments inherit the thread's ownership check**,
not just the message id.

Message bodies are customer-supplied: length-capped, escaped on render, never
`dangerouslySetInnerHTML`.

## 3. Contact preference

Customers choose how they are notified: **in-app only**, **email**, or **phone**.

- **Email** sends a notification with a **link to the thread, not the full conversation** — the thread
  stays the record, and the email is not a copy of personal detail sitting in an inbox.
- **Phone** in v1 stores the number as a **contact hint for the maker to text manually**. Automated
  SMS means Twilio plus US A2P 10DLC registration — disproportionate for v1, and an explicit non-goal.
- **In-app only** means the customer sees it when they visit. Acceptable for chat, **not** for the
  transactional emails in §4, which send regardless.

## 4. Transactional notifications

All sent through the outbox ([[11-background-jobs-and-outbox]]), enqueued in the same transaction as
the state change that caused them.

| Notification | Trigger | Why it matters |
| --- | --- | --- |
| Quote issued | `SUBMITTED → QUOTED` | Starts both clocks |
| **Slot expiring in 24h** | scheduled | **Its loss is a forfeited slot** |
| Slot forfeited | `QUOTED → SLOT_FORFEITED` | Explains what happened, points at the saved config |
| Deposit receipt | webhook | Confirms place in line |
| Stage advanced | maker action | Reduces "where is it" messages |
| **Garment ready, balance due** | `IN_PRODUCTION → READY` | **Its loss is a chargeback from a customer who was never told** |
| Shipped + tracking | maker action | |
| Order declined | `SUBMITTED → DECLINED` | With a reason |
| New message | message posted | Respects contact preference |

The two in bold are the reason the outbox exists.

## 5. Drop announcements

Customers may opt into a drop announcement (`users.notify_on_drop`). **Everyone is notified at the
same time; it is marketing, not a queue** ([[09-capacity-slots-and-drops]] §8).

Sent as a batch through the outbox when the maker opens a drop, or on a scheduled `next_drop_at`.
Unsubscribe link required, and separate from transactional email — a customer who opts out of drop
announcements still gets their balance-due notice.

## 6. Deliverability

- [ ] **DECIDE (also in [[11-background-jobs-and-outbox]] §8):** email provider. Deliverability
      matters more than API ergonomics — a slot-expiry email in a spam folder costs a sale. SPF,
      DKIM, and DMARC configured before launch, not after the first missed notice.

## 7. Testing

- A message posted into another customer's thread returns 404, on read and write.
- Nested route with a valid `mid` but a foreign `oid` returns 404.
- Contact preference `in_app` still receives balance-due email.
- Every notification in §4 is enqueued in the same transaction as its trigger and sent exactly once.
- Unsubscribing from drop announcements does not suppress transactional mail.

## 8. Open questions

1. Email provider (§6).
2. Does the maker get a digest, or per-message email? With five orders, per-message is fine.
3. Are message threads retained after `COMPLETED`? They are dispute evidence — recommendation: yes,
   subject to the retention decision in [[03-security-baseline]] §9.

## 9. Definition of done

- [ ] Per-order threads with maker inbox and unread counts
- [ ] Nested ownership checks proven by the authorization matrix
- [ ] All nine transactional notifications wired through the outbox
- [ ] Drop announcement batch with unsubscribe, separate from transactional mail
- [ ] SPF/DKIM/DMARC verified before launch
</content>
