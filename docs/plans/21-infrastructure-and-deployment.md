# 21 — Infrastructure, Deployment & Backups

**Status:** Scaffold — not started
**Build step:** §14 step 14 (backups); hosting decided before first deploy · **Owner:** [P]
**Depends on:** [[00-development-environment]], [[20-observability-and-ops]]
**Unblocks:** launch
**Source:** PRD §9, §9.3, §12.5, §11.12

---

## 1. Purpose

Where this runs, how it gets there, and — the part that is not optional — **proof that the data can
come back**.

## 2. The target shape

```
React + TypeScript (Vite)          ← storefront, configurator, customer portal, admin panel
        │  REST/JSON
FastAPI (Python)                   ← ALL business logic
        ├── PostgreSQL (+ Alembic migrations)
        ├── Redis                  ← rate limiting + job queue
        ├── S3                     ← fabric photos, embroidery reference uploads
        ├── Identity provider      ← credentials, password reset, email verification
        └── Stripe                 ← Checkout Sessions + webhooks
                ▲
        Scraper repo (Python)      ← POSTs to /internal/sourcing/* with a service token
```

Plus a **worker process** for scheduled jobs and the outbox
([[11-background-jobs-and-outbox]]) — easy to forget in a deployment plan and immediately fatal to
slot expiry if omitted.

## 3. Hosting decision

Target is AWS: **ECS Fargate or App Runner + RDS + ElastiCache + S3 + CloudFront**.

- [ ] **DECIDE (PRD §9.3):** does v1 deploy to a simpler platform (Render / Railway / Fly) first and
      migrate once there is revenue to protect? **AWS setup will likely cost more calendar time than
      the configurator itself**, and the configurator is the product.

  Recommendation: **ship on Render or equivalent.** The application is deliberately portable —
  Postgres, Redis, S3-compatible storage, one web process, one worker — so the migration is a
  configuration exercise, not a rewrite. Revisit when a drop's revenue justifies the operational
  surface. Keep S3 itself (not a platform-specific blob store) so the uploads path never has to move.

## 4. Deployment

- Migrations run on deploy, before the new version serves traffic. Every migration reversible
  ([[01-data-model-and-migrations]] §5).
- **Never deploy during an open drop.** Put it in the runbook.
- Frontend served as static assets behind a CDN; API and worker deployed together so an outbox
  payload shape never outruns the worker that reads it.
- Secrets in a secrets manager, never committed; no secrets in the React bundle
  ([[03-security-baseline]] §9).

## 5. Environments

Local (`docker compose`, [[00-development-environment]]) and production, at minimum.

- [ ] **DECIDE:** is there a staging environment? For a solo developer it is real cost. A cheaper
      substitute: seeded local + a Stripe test-mode smoke test before each deploy. Recommendation:
      no staging in v1, but **never test payments in production**.

## 6. Backups and a rehearsed restore

- Automated **daily Postgres snapshots with point-in-time recovery**.
- **S3 versioning** on the uploads bucket.
- Encryption at rest.

> **A restore must be performed at least once, before launch, into a scratch database.**
> An untested backup is a belief, not a backup.

Measurements, order history, and payment records exist **nowhere else**. Losing them is not a bad
week; it is every open commission unbuildable and every dispute unanswerable.

Record the restore: date, duration, what was verified. Repeat annually.

## 7. Runbooks

Short, written before they are needed:

1. **Restore from backup** — the rehearsed one (§6).
2. **Worker is down** — how to tell (heartbeat, [[20-observability-and-ops]] §6), and what expires
   while it is.
3. **Stripe webhooks failing** — replay from the Stripe dashboard; idempotency makes it safe
   ([[13-payments-and-stripe]] §5).
4. **Drop day** — what to watch ([[20-observability-and-ops]] §5), and the no-deploy rule.

## 8. Open questions

1. Hosting platform for v1 (§3).
2. Staging environment (§5).
3. Domain, TLS, and email sending domain — needed together, since DKIM/DMARC hang off the domain
   ([[18-messaging-and-notifications]] §6).

## 9. Definition of done

- [ ] Hosting decided and the app deployed with web + worker + Redis + Postgres + S3
- [ ] Migrations run automatically on deploy and are reversible
- [ ] Daily snapshots with PITR, and S3 versioning enabled
- [ ] **A restore performed into a scratch database and recorded**
- [ ] Four runbooks in §7 written
</content>
