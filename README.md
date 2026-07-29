# BuyVanda

Made-to-measure denim. Five commissions at a time, sold as drops.

## Layout

```
api/     FastAPI, SQLAlchemy, Alembic, pricing, the worker   (not started)
web/     React + TypeScript (Vite)
docs/    PRD.md + plans/ — the design docs
```

The scraper lives in its own repo and talks to the API over `/internal/sourcing/*`.

## Start here

- [docs/PRD.md](docs/PRD.md) — product decisions, build order, risks
- [docs/plans/](docs/plans/) — 22 component plans, in dependency order
- [CLAUDE.md](CLAUDE.md) — architecture, invariants, how this repo is worked on

Nothing is built yet. Step 0 is [00 — Development Environment](docs/plans/00-development-environment.md).
