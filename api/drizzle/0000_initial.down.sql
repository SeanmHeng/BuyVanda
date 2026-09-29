-- 0000_initial.down.sql
-- The hand-written reverse of 0000_initial.sql (docs/plans/01 §5).
-- drizzle-kit NEVER runs this file. It is applied two ways:
--   * by CI, in the up -> down -> up smoke run on a scratch DB (plan 00 §7)
--   * by you, with `psql -f` when you deliberately roll back
--
-- Undo ONLY what 0000_initial.sql did — here, that happens to be everything,
-- because 0000 is the first migration. Future downs undo far less.
--
-- One transaction: Postgres DDL is transactional, so a failure halfway rolls
-- the whole file back instead of leaving half a schema behind.
-- `IF EXISTS` makes a re-run harmless.

BEGIN;

-- ── tables ─────────────────────────────────────────────────────────────────
-- Reverse of the order in src/db/schema.ts, so every table is dropped before
-- the table it points at. CASCADE makes the order not matter; the order is
-- kept anyway so the file still reads correctly without it.
DROP TABLE IF EXISTS "outbox" CASCADE;
DROP TABLE IF EXISTS "order_messages" CASCADE;
DROP TABLE IF EXISTS "sourcing_candidates" CASCADE;
DROP TABLE IF EXISTS "processed_webhooks" CASCADE;
DROP TABLE IF EXISTS "payments" CASCADE;
DROP TABLE IF EXISTS "order_events" CASCADE;
DROP TABLE IF EXISTS "order_hardware" CASCADE;
DROP TABLE IF EXISTS "order_features" CASCADE;
DROP TABLE IF EXISTS "measurement_flags" CASCADE;
DROP TABLE IF EXISTS "orders" CASCADE;
DROP TABLE IF EXISTS "shipping_zones" CASCADE;
DROP TABLE IF EXISTS "sourcing_requests" CASCADE;
DROP TABLE IF EXISTS "saved_configurations" CASCADE;
DROP TABLE IF EXISTS "drops" CASCADE;
DROP TABLE IF EXISTS "measurement_profiles" CASCADE;
DROP TABLE IF EXISTS "users" CASCADE;
DROP TABLE IF EXISTS "hardware" CASCADE;
DROP TABLE IF EXISTS "features" CASCADE;
DROP TABLE IF EXISTS "silhouettes" CASCADE;
DROP TABLE IF EXISTS "fabric_price_history" CASCADE;
DROP TABLE IF EXISTS "fabrics" CASCADE;
DROP TABLE IF EXISTS "suppliers" CASCADE;
DROP TABLE IF EXISTS "shop_settings" CASCADE;

-- ── enum types ─────────────────────────────────────────────────────────────
-- After the tables: a type can't be dropped while a column still uses it.
DROP TYPE IF EXISTS "payment_kind";
DROP TYPE IF EXISTS "order_status";
DROP TYPE IF EXISTS "order_type";
DROP TYPE IF EXISTS "measurement_units";
DROP TYPE IF EXISTS "user_role";
DROP TYPE IF EXISTS "contact_preference";
DROP TYPE IF EXISTS "shop_override_state";

-- ── drizzle's bookkeeping ──────────────────────────────────────────────────
-- The migrator records each applied migration as a row in
-- drizzle.__drizzle_migrations. Leave the row and the next `db:migrate` thinks
-- 0000 is still applied and skips it. Before 0000 the schema didn't exist at
-- all, so the exact reverse is to drop it. Later downs delete only their own
-- row instead.
DROP SCHEMA IF EXISTS "drizzle" CASCADE;

COMMIT;
