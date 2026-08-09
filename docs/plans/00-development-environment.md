# 00 — Development Environment & CI

**Status:** Scaffold — not started
**Build step:** §14 step 0 · **Owner:** [J]
**Depends on:** nothing — this is the floor
**Unblocks:** every other document
**Source:** PRD §12.1, §12.2, §12.3

---

## 1. Purpose

Make every later step faster and make the rare states reachable. Step 0 comes before schema work
deliberately: retrofitting a seeded environment is nobody's favourite afternoon, and the states that
matter most (expiry, forfeit, full shop) are the ones you will otherwise never see.

## 2. Scope

### In scope
- Repository layout across the API, the web app, and the (separate) scraper repo.
- `docker compose up` bringing the whole stack to a usable state.
- Seed data as versioned code.
- The CI gate and what it blocks on.
- Generated TypeScript client wiring (contract detail lives in [[05-api-contract-and-typed-client]]).

### Out of scope
- Production hosting, secrets management, backups — [[21-infrastructure-and-deployment]].
- Runtime observability — [[20-observability-and-ops]].

## 3. Repository layout

**DECIDED:** the API and the web app share **one repo**, and both are TypeScript. They import the
same `shared/` package, so a response shape that changes on one side fails to compile on the other.
Two repos would keep deploys independent, but for one developer that independence costs more
coordination than it saves — and it would put a package boundary in the way of the thing that makes
the drift check free.

```
BuyVanda/
  api/            Hono, Drizzle, Zod, the pricing module, the worker handler
  web/            React + TypeScript (Vite)
  shared/         Zod schemas + inferred types — imported by api/ and web/
  docs/           PRD.md + plans/
  docker-compose.yml
  package.json    npm workspaces
```

**npm workspaces**, not pnpm or Turborepo. Three packages and one developer do not need a build
graph; workspaces ship with npm and do the one thing required — let `web/` import `shared/` without
publishing it anywhere.

The scraper stays in its own repo and talks to the API over `/internal/sourcing/*`
([[17-sourcing-and-scraper-intake]]). Node is build tooling for the React app only; there is no Node
server.

## 4. One-command local environment

**`docker compose up` runs Postgres. That is the whole compose file.**

The API and the web app run natively — `npm run dev` — because both are Node processes and
containerising a dev server costs the fast feedback loop while buying nothing. A rebuild on every
save, an awkward debugger, and slow bind-mounted file watching on Windows, in exchange for
reproducibility that `package-lock.json` already provides. Postgres is different: it has real state,
a version that must match production, and no sane Windows install story. That is exactly what a
container is for.

**Redis is gone.** The outbox is a Postgres table and the worker is a scheduled Lambda
([[11-background-jobs-and-outbox]]); rate-limit counters live in Postgres behind one function
([[03-security-baseline]] §6). At five concurrent commissions there is nothing left for it to do.
The earlier argument for keeping it — that retrofitting rate limiting means re-testing every limit —
applies to the *interface*, not the store, and the interface is one function either way.

Requirements:
- **Migrations are a script, not a container boot step** — `npm run db:migrate`, run explicitly.
  There is no API container to run them on start, and an implicit migration on boot is a habit worth
  not forming before production.
- Seed loading is a single command, idempotent, and safe to re-run.
- A reset command that drops and rebuilds from empty in under a minute.

Cognito has no local emulator. Development points at a **real dev user pool** in AWS — free at this
volume — and the test suite stubs token verification so it needs no network
([[02-identity-and-authorization]]). This is the one place the local environment is not
self-contained, and it is the price of choosing Cognito.

## 5. Seed data

Seeds are **code (a versioned script), not a dumped SQL file**, so they keep working as the schema
moves. The dataset must include:

- Real silhouettes with plausible `yards_billed` and `build_time_days`.
- A commission range in `shop_settings` ([[04-pricing-engine]] §4).
- A dozen fabrics across **two suppliers** with different `price_buffer_pct` and lead times.
- Hardware with unit costs, and features with **material** prices — including at least one feature
  that consumes nothing and therefore costs nothing ([[04-pricing-engine]] §2.1).
- Orders sitting in **every** state, specifically:
  - a `QUOTED` order with **two hours left** on its slot hold
  - one `IN_PRODUCTION / awaiting_denim` **with no denim cost recorded** — the blocked-balance case
  - one `IN_PRODUCTION` **with a recorded cost below the buffered figure** — the true-up credit case
  - one **with a recorded cost above it** — the absorbed-overrun case
  - one `READY` awaiting balance
  - a full drop at **5/5**
  - a `SLOT_FORFEITED` order with its saved configuration intact
  - one `EXPIRED` past its 14-day price validity
- Two customers and one admin, so the cross-user authorization matrix
  ([[02-identity-and-authorization]]) has fixtures from day one.

Secondary benefit, and not a small one: **the maker can be shown a working site in week two** and
give feedback while it is still cheap to act on.

## 6. The `shared/` package

Request and response shapes are **Zod schemas in `shared/`**, imported by `api/` to validate and by
`web/` to type. One definition does both jobs.

There is no code generation step, no committed generated file, and no CI job comparing the two. A
renamed field breaks `tsc` the moment it is renamed — the check is the compiler, and it runs on
every keystroke in the editor rather than on push.

> This is the single largest saving from choosing TypeScript. In a Python + TypeScript stack the
> wire is where drift accumulates, and the fix is a generation pipeline that has to be built, run,
> committed, and policed. Here the problem does not exist to be solved.

Conventions in [[05-api-contract-and-typed-client]].

## 7. CI gate

Every push runs:

| Check | Tool |
| --- | --- |
| Lint | `eslint` |
| Type check | `tsc --noEmit` across all three workspaces |
| Tests | `vitest` |
| Migrations current **and reversible** | Drizzle Kit check + an up/down/up smoke run |
| Dependency audit | `npm audit` |

Five checks, not seven — the generated-client diff is gone with the generator, and one language
means one linter, one type checker, one test runner, and one lockfile to audit.

The reversibility check earns its place here more than it did before: **Drizzle Kit writes the `up`
migration and nothing else.** The `down` is hand-written, which means it is the kind of thing that
gets skipped at 1am. CI running up → down → up against a scratch database is what makes
[[01-data-model-and-migrations]] §5 true rather than aspirational.

Two suites are called out because they only protect anything if they **cannot be skipped**:
- the cross-user authorization matrix ([[02-identity-and-authorization]])
- the pricing golden tests ([[04-pricing-engine]])

## 8. Open questions

1. Test database strategy — transactional rollback per test vs. schema-per-worker. Affects suite
   wall-clock more than correctness; pick at step 1 when there is a schema to test against.

## 9. Definition of done

- [ ] `docker compose up` plus `npm run dev` on a clean machine yields a browsable site with seeded
      data, in under ten minutes from `git clone`
- [ ] Seed script is idempotent and covers every order state listed in §5
- [ ] CI runs all five checks in §7 and blocks merge on failure
- [ ] A migration's `down` is exercised in CI, verified by deliberately writing a broken one once
- [ ] Renaming a field in `shared/` breaks `tsc` in both `api/` and `web/` (verified once, on
      purpose — this is the check that replaced the generated client)
</content>
