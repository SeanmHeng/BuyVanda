// The shape of every table. Columns only — never a row.
// Tables and columns stay snake_case; TypeScript properties are camelCase.
// Money is integer cents in the column, and the property name ends in `Cents`.
// docs/plans/01-data-model-and-migrations.md §3

import { sql } from "drizzle-orm";
import {
  boolean,
  check,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  text,
  timestamp,
  unique,
  uuid,
} from "drizzle-orm/pg-core";

// ---------------------------------------------------------------------------
// Enums — only for the value sets the plans actually spell out. Everything
// whose values another plan still owns (sub_stage, maker_status, payment
// status, outbox status) stays `text` until that plan pins the list.
// ---------------------------------------------------------------------------

// Whether the shop is taking commissions. `auto` follows the slot count;
// the two overrides let the maker close or open the shop by hand.
export const shopOverrideState = pgEnum("shop_override_state", [
  "auto",
  "force_open",
  "force_closed",
]);

// How a customer wants to hear from us.
export const contactPreference = pgEnum("contact_preference", ["in_app", "email", "phone"]);

// Who a user is to the system.
export const userRole = pgEnum("user_role", ["customer", "admin"]);

// Which unit the customer entered a measurement profile in. Storage is always mm.
export const measurementUnits = pgEnum("measurement_units", ["in", "cm"]);

// Preset (curated denim + fixed silhouette) vs full custom (free reign).
export const orderType = pgEnum("order_type", ["preset", "custom"]);

// The order lifecycle. `transition()` is the only writer of this column
// (CLAUDE.md invariant 4 · plan 08). Terminal states sit after COMPLETED.
export const orderStatus = pgEnum("order_status", [
  "DRAFT",
  "SUBMITTED",
  "QUOTED",
  "DEPOSIT_PAID",
  "IN_PRODUCTION",
  "READY",
  "BALANCE_PAID",
  "SHIPPED",
  "COMPLETED",
  "DECLINED",
  "SLOT_FORFEITED",
  "EXPIRED",
  "CANCELLED",
]);

// A payment is either the deposit or the final balance.
export const paymentKind = pgEnum("payment_kind", ["deposit", "balance"]);

// ---------------------------------------------------------------------------
// Block 1 — shop configuration & catalog source
// ---------------------------------------------------------------------------

// Shop settings
export const shopSettings = pgTable(
  "shop_settings",
  {
    id: integer("id").primaryKey().default(1),
    maxSlots: integer("max_slots").notNull().default(5),
    overrideState: shopOverrideState("override_state").notNull().default("auto"),
    nextDropAt: timestamp("next_drop_at", { withTimezone: true }),
    closedMessage: text("closed_message").notNull(),
    commissionMinCents: integer("commission_min").notNull(),
    commissionMaxCents: integer("commission_max").notNull(),
  },

  // Make sure its only one row, Non zero capacity, cannot exceed range
  (t) => [
    check("shop_settings_single_row", sql`${t.id} = 1`),
    check("shop_settings_max_slots_positive", sql`${t.maxSlots} > 0`),
    check(
      "shop_settings_commission_range",
      sql`${t.commissionMinCents} >= 0 and ${t.commissionMinCents} <= ${t.commissionMaxCents}`,
    ),
  ],
);

// Suppliers
export const suppliers = pgTable(
  "suppliers",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    url: text("url").notNull(),
    leadTimeTypicalDays: integer("lead_time_typical_days").notNull(),
    leadTimeWorstDays: integer("lead_time_worst_days").notNull(),
    notes: text("notes").notNull().default(""),
  },
  (t) => [
    check("suppliers_typical_lead_positive", sql`${t.leadTimeTypicalDays} > 0`),
    check(
      "suppliers_worst_lead_not_better",
      sql`${t.leadTimeWorstDays} >= ${t.leadTimeTypicalDays}`,
    ),
  ],
);

// A denim a customer can pick, or that the maker sources. `is_curated`
// marks the preset shortlist; `reorderable` means we can buy it again.
export const fabrics = pgTable(
  "fabrics",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    color: text("color").notNull(),
    weightOz: integer("weight_oz").notNull(),
    costPerYardCents: integer("cost_per_yard").notNull(),
    priceBufferPct: integer("price_buffer_pct").notNull(),
    isCurated: boolean("is_curated").notNull().default(false),
    reorderable: boolean("reorderable").notNull().default(true),
    supplierId: uuid("supplier_id").references(() => suppliers.id),
    productUrl: text("product_url"),
    lastPriceCheckedAt: timestamp("last_price_checked_at", { withTimezone: true }),
    photoKey: text("photo_key"),
  },
  (t) => [
    check("fabrics_cost_nonneg", sql`${t.costPerYardCents} >= 0`),
    check("fabrics_buffer_nonneg", sql`${t.priceBufferPct} >= 0`),
  ],
);

// Every price we've observed for a fabric — hand-entered or scraped.
export const fabricPriceHistory = pgTable("fabric_price_history", {
  id: uuid("id").primaryKey().defaultRandom(),
  fabricId: uuid("fabric_id")
    .notNull()
    .references(() => fabrics.id),
  costPerYardCents: integer("cost_per_yard").notNull(),
  observedAt: timestamp("observed_at", { withTimezone: true }).notNull().defaultNow(),
  source: text("source").notNull(),
});

// A cut the shop offers. `oversize_threshold` is jsonb because the trigger
// is a set of measurement bounds; crossing it bills extra yards.
export const silhouettes = pgTable(
  "silhouettes",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    yardsBilled: integer("yards_billed").notNull(),
    oversizeThreshold: jsonb("oversize_threshold"),
    oversizeExtraYards: integer("oversize_extra_yards").notNull().default(0),
    buildTimeDays: integer("build_time_days").notNull(),
    active: boolean("active").notNull().default(true),
  },
  (t) => [check("silhouettes_yards_nonneg", sql`${t.yardsBilled} >= 0`)],
);

// An add-on the customer can choose. `material_price` is labor only — the
// physical part is a separate `hardware` row (CLAUDE.md vocabulary).
export const features = pgTable("features", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  category: text("category").notNull(),
  materialPriceCents: integer("material_price").notNull(),
  sizeTier: text("size_tier"),
  appliesTo: text("applies_to").array().notNull(),
  requiresReview: boolean("requires_review").notNull().default(false),
  requiredHardware: uuid("required_hardware").array(),
});

// A physical part — buttons, rivets, zips. Priced per unit, times qty.
export const hardware = pgTable("hardware", {
  id: uuid("id").primaryKey().defaultRandom(),
  name: text("name").notNull(),
  kind: text("kind").notNull(),
  unitCostCents: integer("unit_cost").notNull(),
  defaultQty: integer("default_qty").notNull().default(1),
  active: boolean("active").notNull().default(true),
});

// ---------------------------------------------------------------------------
// Block 2 — people, drops, saved work
// ---------------------------------------------------------------------------

// A customer or the maker. `idp_subject` links to the Cognito identity;
// the app never stores a password.
export const users = pgTable("users", {
  id: uuid("id").primaryKey().defaultRandom(),
  email: text("email").notNull().unique(),
  emailVerifiedAt: timestamp("email_verified_at", { withTimezone: true }),
  phone: text("phone"),
  contactPreference: contactPreference("contact_preference").notNull().default("in_app"),
  notifyOnDrop: boolean("notify_on_drop").notNull().default(false),
  role: userRole("role").notNull().default("customer"),
  idpSubject: text("idp_subject").unique(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// A reusable set of body measurements a customer saves. Every measurement is
// stored as whole millimetres, whatever the customer typed; `units` only records
// which unit they entered in, so it can be shown back to them (plan 06 §2).
// Snapshotted onto an order at quote time, never read live.
export const measurementProfiles = pgTable("measurement_profiles", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id),
  label: text("label").notNull(),
  units: measurementUnits("units").notNull(),
  waistMm: integer("waist_mm").notNull(),
  hipMm: integer("hip_mm").notNull(),
  thighMm: integer("thigh_mm").notNull(),
  kneeMm: integer("knee_mm").notNull(),
  legOpeningMm: integer("leg_opening_mm").notNull(),
  frontRiseMm: integer("front_rise_mm").notNull(),
  backRiseMm: integer("back_rise_mm").notNull(),
  inseamMm: integer("inseam_mm").notNull(),
  outseamMm: integer("outseam_mm").notNull(),
  fitPreference: text("fit_preference"),
  notes: text("notes").notNull().default(""),
});

// A capacity opening: the maker offers a batch of slots.
export const drops = pgTable("drops", {
  id: uuid("id").primaryKey().defaultRandom(),
  openedAt: timestamp("opened_at", { withTimezone: true }).notNull().defaultNow(),
  closedAt: timestamp("closed_at", { withTimezone: true }),
  slotsOffered: integer("slots_offered").notNull(),
  openedBy: uuid("opened_by").references(() => users.id),
});

// A configurator draft a customer parked before submitting. `indicative_total`
// is an estimate for display only — the order recomputes at submission.
export const savedConfigurations = pgTable("saved_configurations", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id),
  silhouetteId: uuid("silhouette_id").references(() => silhouettes.id),
  fabricId: uuid("fabric_id").references(() => fabrics.id),
  measurementProfileId: uuid("measurement_profile_id").references(() => measurementProfiles.id),
  features: jsonb("features"),
  indicativeTotalCents: integer("indicative_total"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// A request to source a fabric that isn't in the catalog. `order_id` links
// back to the order without a DB foreign key — the reverse pointer lives on
// orders.sourcing_request_id, and declaring both would make a reference cycle
// Drizzle can't type. This side stays a plain uuid on purpose.
export const sourcingRequests = pgTable("sourcing_requests", {
  id: uuid("id").primaryKey().defaultRandom(),
  orderId: uuid("order_id"),
  url: text("url").notNull(),
  fabricName: text("fabric_name").notNull(),
  weightOz: integer("weight_oz"),
  notes: text("notes").notNull().default(""),
  makerStatus: text("maker_status").notNull().default("pending"),
  confirmedCostPerYardCents: integer("confirmed_cost_per_yard"),
});

// Flat-rate shipping by region. `region_codes` is an array of codes the zone
// covers; exactly one zone should be `is_default`.
export const shippingZones = pgTable(
  "shipping_zones",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    name: text("name").notNull(),
    regionCodes: text("region_codes").array().notNull(),
    flatRateCents: integer("flat_rate").notNull(),
    isDefault: boolean("is_default").notNull().default(false),
    active: boolean("active").notNull().default(true),
  },
  (t) => [check("shipping_zones_rate_nonneg", sql`${t.flatRateCents} >= 0`)],
);

// ---------------------------------------------------------------------------
// Block 3 — orders and everything snapshotted onto them
// ---------------------------------------------------------------------------

// The central record. Everything the customer was quoted against is frozen
// here at quote time (`*_at_quote`, `cost_breakdown`, `measurement_snapshot`,
// `commission_fee`) so a later catalog edit never moves a placed order
// (CLAUDE.md invariant 6 · plan 01 §4.2). Money columns are integer cents.
export const orders = pgTable("orders", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id")
    .notNull()
    .references(() => users.id),
  dropId: uuid("drop_id").references(() => drops.id),
  type: orderType("type").notNull(),
  silhouetteId: uuid("silhouette_id").references(() => silhouettes.id),
  fabricId: uuid("fabric_id").references(() => fabrics.id),
  sourcingRequestId: uuid("sourcing_request_id").references(() => sourcingRequests.id),
  measurementSnapshot: jsonb("measurement_snapshot"),
  status: orderStatus("status").notNull().default("DRAFT"),
  subStage: text("sub_stage"),
  priority: integer("priority").notNull().default(0),
  estimateTotalCents: integer("estimate_total"),
  finalTotalCents: integer("final_total"),
  costBreakdown: jsonb("cost_breakdown"),
  yardsBilledAtQuote: integer("yards_billed_at_quote"),
  costPerYardAtQuoteCents: integer("cost_per_yard_at_quote"),
  bufferPctAtQuote: integer("buffer_pct_at_quote"),
  quoteValidUntil: timestamp("quote_valid_until", { withTimezone: true }),
  slotHoldExpiresAt: timestamp("slot_hold_expires_at", { withTimezone: true }),
  shippingZoneId: uuid("shipping_zone_id").references(() => shippingZones.id),
  shippingAmountCents: integer("shipping_amount"),
  policyAcceptedAt: timestamp("policy_accepted_at", { withTimezone: true }),
  commissionFeeCents: integer("commission_fee"),
  depositAmountCents: integer("deposit_amount"),
  depositPaidAt: timestamp("deposit_paid_at", { withTimezone: true }),
  actualDenimCostCents: integer("actual_denim_cost"),
  denimCostRecordedAt: timestamp("denim_cost_recorded_at", { withTimezone: true }),
  denimProofKey: text("denim_proof_key"),
  readyAt: timestamp("ready_at", { withTimezone: true }),
  trackingCarrier: text("tracking_carrier"),
  trackingNumber: text("tracking_number"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
});

// A measurement that tripped a validation rule on an order, for maker review.
export const measurementFlags = pgTable("measurement_flags", {
  id: uuid("id").primaryKey().defaultRandom(),
  orderId: uuid("order_id")
    .notNull()
    .references(() => orders.id),
  field: text("field").notNull(),
  rule: text("rule").notNull(),
  message: text("message").notNull(),
});

// A feature chosen on an order, with its labor price frozen at order time.
export const orderFeatures = pgTable("order_features", {
  id: uuid("id").primaryKey().defaultRandom(),
  orderId: uuid("order_id")
    .notNull()
    .references(() => orders.id),
  featureId: uuid("feature_id")
    .notNull()
    .references(() => features.id),
  materialPriceAtOrderCents: integer("material_price_at_order").notNull(),
  referenceImageKey: text("reference_image_key"),
  notes: text("notes").notNull().default(""),
});

// A hardware line on an order, with its unit cost frozen at order time.
export const orderHardware = pgTable("order_hardware", {
  id: uuid("id").primaryKey().defaultRandom(),
  orderId: uuid("order_id")
    .notNull()
    .references(() => orders.id),
  hardwareId: uuid("hardware_id")
    .notNull()
    .references(() => hardware.id),
  qty: integer("qty").notNull(),
  unitCostAtOrderCents: integer("unit_cost_at_order").notNull(),
});

// The append-only history of an order's status changes. Written inside the
// same transaction as every `transition()` (CLAUDE.md invariant 4).
// `actor_id` is null when the system (worker) drove the change.
export const orderEvents = pgTable("order_events", {
  id: uuid("id").primaryKey().defaultRandom(),
  orderId: uuid("order_id")
    .notNull()
    .references(() => orders.id),
  actorId: uuid("actor_id").references(() => users.id),
  fromStatus: orderStatus("from_status"),
  toStatus: orderStatus("to_status").notNull(),
  note: text("note"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// A deposit or balance charge. `provider_ref` is the Stripe id. `deposit_paid_at`
// on the order is set only by the verified webhook (CLAUDE.md invariant 5).
export const payments = pgTable(
  "payments",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    orderId: uuid("order_id")
      .notNull()
      .references(() => orders.id),
    kind: paymentKind("kind").notNull(),
    provider: text("provider").notNull(),
    providerRef: text("provider_ref"),
    amountCents: integer("amount").notNull(),
    status: text("status").notNull(),
  },
  (t) => [check("payments_amount_nonneg", sql`${t.amountCents} >= 0`)],
);

// The webhook dedupe ledger: a provider event we've already handled, so a
// replay is a no-op. (provider, event_id) is unique.
export const processedWebhooks = pgTable(
  "processed_webhooks",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    provider: text("provider").notNull(),
    eventId: text("event_id").notNull(),
    receivedAt: timestamp("received_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [unique("processed_webhooks_provider_event").on(t.provider, t.eventId)],
);

// ---------------------------------------------------------------------------
// Block 4 — sourcing intake, messaging, outbox
// ---------------------------------------------------------------------------

// A fabric the scraper found. Not yet tied to an order — the maker triages
// candidates into requests. (source, external_id) identifies the listing.
export const sourcingCandidates = pgTable(
  "sourcing_candidates",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    source: text("source").notNull(),
    externalId: text("external_id").notNull(),
    url: text("url").notNull(),
    title: text("title").notNull(),
    priceCents: integer("price"),
    weightOz: integer("weight_oz"),
    scrapedAt: timestamp("scraped_at", { withTimezone: true }).notNull().defaultNow(),
    makerStatus: text("maker_status").notNull().default("pending"),
  },
  (t) => [unique("sourcing_candidates_source_external").on(t.source, t.externalId)],
);

// A message on an order thread, between customer and maker.
export const orderMessages = pgTable("order_messages", {
  id: uuid("id").primaryKey().defaultRandom(),
  orderId: uuid("order_id")
    .notNull()
    .references(() => orders.id),
  senderId: uuid("sender_id")
    .notNull()
    .references(() => users.id),
  body: text("body").notNull(),
  attachmentKey: text("attachment_key"),
  readAt: timestamp("read_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

// The transactional outbox: a side effect enqueued in the same transaction as
// the change that caused it, drained later by the worker (CLAUDE.md invariant
// 8 · plan 11). `next_attempt_at` drives retry backoff.
export const outbox = pgTable("outbox", {
  id: uuid("id").primaryKey().defaultRandom(),
  kind: text("kind").notNull(),
  payload: jsonb("payload").notNull(),
  status: text("status").notNull().default("pending"),
  attempts: integer("attempts").notNull().default(0),
  nextAttemptAt: timestamp("next_attempt_at", { withTimezone: true }).notNull().defaultNow(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  sentAt: timestamp("sent_at", { withTimezone: true }),
});
