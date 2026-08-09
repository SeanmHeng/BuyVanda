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
        │                            static build on S3, served by CloudFront
        │  REST/JSON
Hono (TypeScript)                  ← ALL business logic
        │  Lambda + API Gateway
        ├── PostgreSQL             ← RDS · Drizzle Kit migrations
        ├── S3                     ← fabric photos, embroidery reference uploads
        ├── Cognito                ← credentials, password reset, email verification, MFA
        └── Stripe                 ← Checkout Sessions + webhooks
                ▲
        Scraper repo (Python)      ← Lambda on an EventBridge schedule
                                     POSTs to /internal/sourcing/* with a service token
```

Plus the **worker** — EventBridge Scheduler invoking a Lambda every minute for scheduled jobs and
the outbox ([[11-background-jobs-and-outbox]]). Easy to forget in a deployment plan and immediately
fatal to slot expiry if omitted. Being a schedule rather than a process does not make it optional —
it makes it easier to forget.

## 3. Hosting decision

**DECIDED: serverless AWS.** Lambda + API Gateway for the API and the worker, RDS for Postgres,
S3 + CloudFront for the frontend, Cognito for identity. **No Fargate, no ElastiCache, no load
balancer.**

The deciding number is not compute. A Fargate task at 0.5 vCPU / 1 GB is about $9/month and two
would be needed — but an Application Load Balancer bills roughly **$16/month simply to exist**,
before a single request, with NAT Gateway, public IPv4 charges, and CloudWatch ingestion behind it.
Fargate is priced for a service with steady traffic. This is a shop that opens five times a year.

Lambda's free tier is **perpetual**, not a twelve-month trial: 1M requests and 400,000 GB-seconds a
month, with EventBridge Scheduler adding 14M invocations. The realistic v1 bill is the database
alone.

This section previously recommended Render, argued on calendar time — that AWS would cost more of it
than the configurator, and the configurator is the product. That argument still holds for someone
shipping a business. It loses here to two things: **this project is a learning exercise**, where the
AWS surface is part of the point, and the serverless shape is genuinely simpler than the Fargate one
that made AWS look expensive in the first place.

Two things to design around rather than discover:

- **Cold starts** — 200–500ms on the first request after idle. Acceptable, and Hono was chosen
  partly because it is small enough to keep that number low.
- **Connection limits** — each concurrent Lambda opens a database connection and RDS caps them. At
  five concurrent commissions this is theoretical, but it is what bites first if traffic ever
  surprises us. RDS Proxy is the fix and it costs money; do not add it pre-emptively.

- [ ] **DECIDE:** infrastructure as code — **AWS CDK** or **SST**. CDK is AWS's own, generates
      CloudFormation from TypeScript, and teaches the real resource model at the cost of roughly
      four times the code. SST is faster and its `sst dev` live-Lambda loop is genuinely better, but
      since v3 it runs on Pulumi and Terraform providers rather than CloudFormation — a parallel
      ecosystem, not a layer on CDK. Recommendation: **CDK**, consistent with choosing Cognito over
      a friendlier managed provider. Needed at first deploy, not before.

## 4. Deployment

- Migrations run **as a deploy step, before the new version serves traffic** — a one-off task, never
  from the Lambda's own startup, where concurrent cold starts would race each other to migrate the
  same database. Every migration reversible ([[01-data-model-and-migrations]] §5).
- **Never deploy during an open drop.** Put it in the runbook.
- Frontend served as static assets behind CloudFront; **API and worker deploy together** so an
  outbox payload shape never outruns the worker that reads it. They are one codebase and must stay
  one deployable unit.
- Secrets in SSM Parameter Store or Secrets Manager, never committed; no secrets in the React bundle,
  where `VITE_`-prefixed variables are public by construction ([[03-security-baseline]] §9).

## 5. Environments

Local (Postgres in `docker compose` plus `npm run dev`, [[00-development-environment]]) and
production, at minimum. Local is not fully self-contained: Cognito has no emulator, so development
points at a real **dev user pool** and tests stub token verification.

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

1. Infrastructure as code — CDK or SST (§3).
2. Staging environment (§5).
3. Domain, TLS, and email sending domain — needed together, since DKIM/DMARC hang off the domain
   ([[18-messaging-and-notifications]] §6).

## 9. Definition of done

- [ ] App deployed: API Lambda, worker Lambda on its schedule, RDS, S3, CloudFront, Cognito
- [ ] The whole stack defined in code, and a second environment provable from the same definition
- [ ] Migrations run as a deploy step, not on Lambda startup, and are reversible
- [ ] Daily snapshots with PITR, and S3 versioning enabled
- [ ] **A restore performed into a scratch database and recorded**
- [ ] Four runbooks in §7 written
</content>
