# BuyVanda

Made-to-measure denim. Five commissions at a time, sold as drops.

## Layout

```
api/      Hono, Drizzle, Zod, pricing, the worker   (not started)
web/      React + TypeScript (Vite)
shared/   Zod schemas + inferred types, imported by both
docs/     PRD.md + plans/ — the design docs
```

TypeScript end to end, on serverless AWS — Lambda behind API Gateway, Postgres on RDS, the frontend
static on S3 + CloudFront. The scraper is the one exception: Python, in its own repo, on an
EventBridge schedule, talking to the API over `/internal/sourcing/*` like any other client.

## Start here

- [docs/PRD.md](docs/PRD.md) — product decisions, build order, risks
- [docs/plans/](docs/plans/) — 22 component plans, in dependency order
- [CLAUDE.md](CLAUDE.md) — architecture, invariants, how this repo is worked on

Nothing is built yet. Step 0 is [00 — Development Environment](docs/plans/00-development-environment.md).
