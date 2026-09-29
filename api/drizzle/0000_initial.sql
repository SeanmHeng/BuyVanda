CREATE TYPE "public"."contact_preference" AS ENUM('in_app', 'email', 'phone');--> statement-breakpoint
CREATE TYPE "public"."measurement_units" AS ENUM('in', 'cm');--> statement-breakpoint
CREATE TYPE "public"."order_status" AS ENUM('DRAFT', 'SUBMITTED', 'QUOTED', 'DEPOSIT_PAID', 'IN_PRODUCTION', 'READY', 'BALANCE_PAID', 'SHIPPED', 'COMPLETED', 'DECLINED', 'SLOT_FORFEITED', 'EXPIRED', 'CANCELLED');--> statement-breakpoint
CREATE TYPE "public"."order_type" AS ENUM('preset', 'custom');--> statement-breakpoint
CREATE TYPE "public"."payment_kind" AS ENUM('deposit', 'balance');--> statement-breakpoint
CREATE TYPE "public"."shop_override_state" AS ENUM('auto', 'force_open', 'force_closed');--> statement-breakpoint
CREATE TYPE "public"."user_role" AS ENUM('customer', 'admin');--> statement-breakpoint
CREATE TABLE "drops" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"opened_at" timestamp with time zone DEFAULT now() NOT NULL,
	"closed_at" timestamp with time zone,
	"slots_offered" integer NOT NULL,
	"opened_by" uuid
);
--> statement-breakpoint
CREATE TABLE "fabric_price_history" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"fabric_id" uuid NOT NULL,
	"cost_per_yard" integer NOT NULL,
	"observed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"source" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "fabrics" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"color" text NOT NULL,
	"weight_oz" integer NOT NULL,
	"cost_per_yard" integer NOT NULL,
	"price_buffer_pct" integer NOT NULL,
	"is_curated" boolean DEFAULT false NOT NULL,
	"reorderable" boolean DEFAULT true NOT NULL,
	"supplier_id" uuid,
	"product_url" text,
	"last_price_checked_at" timestamp with time zone,
	"photo_key" text,
	CONSTRAINT "fabrics_cost_nonneg" CHECK ("fabrics"."cost_per_yard" >= 0),
	CONSTRAINT "fabrics_buffer_nonneg" CHECK ("fabrics"."price_buffer_pct" >= 0)
);
--> statement-breakpoint
CREATE TABLE "features" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"category" text NOT NULL,
	"material_price" integer NOT NULL,
	"size_tier" text,
	"applies_to" text[] NOT NULL,
	"requires_review" boolean DEFAULT false NOT NULL,
	"required_hardware" uuid[]
);
--> statement-breakpoint
CREATE TABLE "hardware" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"kind" text NOT NULL,
	"unit_cost" integer NOT NULL,
	"default_qty" integer DEFAULT 1 NOT NULL,
	"active" boolean DEFAULT true NOT NULL
);
--> statement-breakpoint
CREATE TABLE "measurement_flags" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid NOT NULL,
	"field" text NOT NULL,
	"rule" text NOT NULL,
	"message" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "measurement_profiles" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"label" text NOT NULL,
	"units" "measurement_units" NOT NULL,
	"waist_mm" integer NOT NULL,
	"hip_mm" integer NOT NULL,
	"thigh_mm" integer NOT NULL,
	"knee_mm" integer NOT NULL,
	"leg_opening_mm" integer NOT NULL,
	"front_rise_mm" integer NOT NULL,
	"back_rise_mm" integer NOT NULL,
	"inseam_mm" integer NOT NULL,
	"outseam_mm" integer NOT NULL,
	"fit_preference" text,
	"notes" text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE TABLE "order_events" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid NOT NULL,
	"actor_id" uuid,
	"from_status" "order_status",
	"to_status" "order_status" NOT NULL,
	"note" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "order_features" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid NOT NULL,
	"feature_id" uuid NOT NULL,
	"material_price_at_order" integer NOT NULL,
	"reference_image_key" text,
	"notes" text DEFAULT '' NOT NULL
);
--> statement-breakpoint
CREATE TABLE "order_hardware" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid NOT NULL,
	"hardware_id" uuid NOT NULL,
	"qty" integer NOT NULL,
	"unit_cost_at_order" integer NOT NULL
);
--> statement-breakpoint
CREATE TABLE "order_messages" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid NOT NULL,
	"sender_id" uuid NOT NULL,
	"body" text NOT NULL,
	"attachment_key" text,
	"read_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "orders" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"drop_id" uuid,
	"type" "order_type" NOT NULL,
	"silhouette_id" uuid,
	"fabric_id" uuid,
	"sourcing_request_id" uuid,
	"measurement_snapshot" jsonb,
	"status" "order_status" DEFAULT 'DRAFT' NOT NULL,
	"sub_stage" text,
	"priority" integer DEFAULT 0 NOT NULL,
	"estimate_total" integer,
	"final_total" integer,
	"cost_breakdown" jsonb,
	"yards_billed_at_quote" integer,
	"cost_per_yard_at_quote" integer,
	"buffer_pct_at_quote" integer,
	"quote_valid_until" timestamp with time zone,
	"slot_hold_expires_at" timestamp with time zone,
	"shipping_zone_id" uuid,
	"shipping_amount" integer,
	"policy_accepted_at" timestamp with time zone,
	"commission_fee" integer,
	"deposit_amount" integer,
	"deposit_paid_at" timestamp with time zone,
	"actual_denim_cost" integer,
	"denim_cost_recorded_at" timestamp with time zone,
	"denim_proof_key" text,
	"ready_at" timestamp with time zone,
	"tracking_carrier" text,
	"tracking_number" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "outbox" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"kind" text NOT NULL,
	"payload" jsonb NOT NULL,
	"status" text DEFAULT 'pending' NOT NULL,
	"attempts" integer DEFAULT 0 NOT NULL,
	"next_attempt_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"sent_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "payments" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid NOT NULL,
	"kind" "payment_kind" NOT NULL,
	"provider" text NOT NULL,
	"provider_ref" text,
	"amount" integer NOT NULL,
	"status" text NOT NULL,
	CONSTRAINT "payments_amount_nonneg" CHECK ("payments"."amount" >= 0)
);
--> statement-breakpoint
CREATE TABLE "processed_webhooks" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"provider" text NOT NULL,
	"event_id" text NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "processed_webhooks_provider_event" UNIQUE("provider","event_id")
);
--> statement-breakpoint
CREATE TABLE "saved_configurations" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"user_id" uuid NOT NULL,
	"silhouette_id" uuid,
	"fabric_id" uuid,
	"measurement_profile_id" uuid,
	"features" jsonb,
	"indicative_total" integer,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "shipping_zones" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"region_codes" text[] NOT NULL,
	"flat_rate" integer NOT NULL,
	"is_default" boolean DEFAULT false NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	CONSTRAINT "shipping_zones_rate_nonneg" CHECK ("shipping_zones"."flat_rate" >= 0)
);
--> statement-breakpoint
CREATE TABLE "shop_settings" (
	"id" integer PRIMARY KEY DEFAULT 1 NOT NULL,
	"max_slots" integer DEFAULT 5 NOT NULL,
	"override_state" "shop_override_state" DEFAULT 'auto' NOT NULL,
	"next_drop_at" timestamp with time zone,
	"closed_message" text NOT NULL,
	"commission_min" integer NOT NULL,
	"commission_max" integer NOT NULL,
	CONSTRAINT "shop_settings_single_row" CHECK ("shop_settings"."id" = 1),
	CONSTRAINT "shop_settings_max_slots_positive" CHECK ("shop_settings"."max_slots" > 0),
	CONSTRAINT "shop_settings_commission_range" CHECK ("shop_settings"."commission_min" >= 0 and "shop_settings"."commission_min" <= "shop_settings"."commission_max")
);
--> statement-breakpoint
CREATE TABLE "silhouettes" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"yards_billed" integer NOT NULL,
	"oversize_threshold" jsonb,
	"oversize_extra_yards" integer DEFAULT 0 NOT NULL,
	"build_time_days" integer NOT NULL,
	"active" boolean DEFAULT true NOT NULL,
	CONSTRAINT "silhouettes_yards_nonneg" CHECK ("silhouettes"."yards_billed" >= 0)
);
--> statement-breakpoint
CREATE TABLE "sourcing_candidates" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"source" text NOT NULL,
	"external_id" text NOT NULL,
	"url" text NOT NULL,
	"title" text NOT NULL,
	"price" integer,
	"weight_oz" integer,
	"scraped_at" timestamp with time zone DEFAULT now() NOT NULL,
	"maker_status" text DEFAULT 'pending' NOT NULL,
	CONSTRAINT "sourcing_candidates_source_external" UNIQUE("source","external_id")
);
--> statement-breakpoint
CREATE TABLE "sourcing_requests" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"order_id" uuid,
	"url" text NOT NULL,
	"fabric_name" text NOT NULL,
	"weight_oz" integer,
	"notes" text DEFAULT '' NOT NULL,
	"maker_status" text DEFAULT 'pending' NOT NULL,
	"confirmed_cost_per_yard" integer
);
--> statement-breakpoint
CREATE TABLE "suppliers" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"url" text NOT NULL,
	"lead_time_typical_days" integer NOT NULL,
	"lead_time_worst_days" integer NOT NULL,
	"notes" text DEFAULT '' NOT NULL,
	CONSTRAINT "suppliers_typical_lead_positive" CHECK ("suppliers"."lead_time_typical_days" > 0),
	CONSTRAINT "suppliers_worst_lead_not_better" CHECK ("suppliers"."lead_time_worst_days" >= "suppliers"."lead_time_typical_days")
);
--> statement-breakpoint
CREATE TABLE "users" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"email" text NOT NULL,
	"email_verified_at" timestamp with time zone,
	"phone" text,
	"contact_preference" "contact_preference" DEFAULT 'in_app' NOT NULL,
	"notify_on_drop" boolean DEFAULT false NOT NULL,
	"role" "user_role" DEFAULT 'customer' NOT NULL,
	"idp_subject" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "users_email_unique" UNIQUE("email"),
	CONSTRAINT "users_idp_subject_unique" UNIQUE("idp_subject")
);
--> statement-breakpoint
ALTER TABLE "drops" ADD CONSTRAINT "drops_opened_by_users_id_fk" FOREIGN KEY ("opened_by") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "fabric_price_history" ADD CONSTRAINT "fabric_price_history_fabric_id_fabrics_id_fk" FOREIGN KEY ("fabric_id") REFERENCES "public"."fabrics"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "fabrics" ADD CONSTRAINT "fabrics_supplier_id_suppliers_id_fk" FOREIGN KEY ("supplier_id") REFERENCES "public"."suppliers"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "measurement_flags" ADD CONSTRAINT "measurement_flags_order_id_orders_id_fk" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "measurement_profiles" ADD CONSTRAINT "measurement_profiles_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "order_events" ADD CONSTRAINT "order_events_order_id_orders_id_fk" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "order_events" ADD CONSTRAINT "order_events_actor_id_users_id_fk" FOREIGN KEY ("actor_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "order_features" ADD CONSTRAINT "order_features_order_id_orders_id_fk" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "order_features" ADD CONSTRAINT "order_features_feature_id_features_id_fk" FOREIGN KEY ("feature_id") REFERENCES "public"."features"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "order_hardware" ADD CONSTRAINT "order_hardware_order_id_orders_id_fk" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "order_hardware" ADD CONSTRAINT "order_hardware_hardware_id_hardware_id_fk" FOREIGN KEY ("hardware_id") REFERENCES "public"."hardware"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "order_messages" ADD CONSTRAINT "order_messages_order_id_orders_id_fk" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "order_messages" ADD CONSTRAINT "order_messages_sender_id_users_id_fk" FOREIGN KEY ("sender_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orders" ADD CONSTRAINT "orders_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orders" ADD CONSTRAINT "orders_drop_id_drops_id_fk" FOREIGN KEY ("drop_id") REFERENCES "public"."drops"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orders" ADD CONSTRAINT "orders_silhouette_id_silhouettes_id_fk" FOREIGN KEY ("silhouette_id") REFERENCES "public"."silhouettes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orders" ADD CONSTRAINT "orders_fabric_id_fabrics_id_fk" FOREIGN KEY ("fabric_id") REFERENCES "public"."fabrics"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orders" ADD CONSTRAINT "orders_sourcing_request_id_sourcing_requests_id_fk" FOREIGN KEY ("sourcing_request_id") REFERENCES "public"."sourcing_requests"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "orders" ADD CONSTRAINT "orders_shipping_zone_id_shipping_zones_id_fk" FOREIGN KEY ("shipping_zone_id") REFERENCES "public"."shipping_zones"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "payments" ADD CONSTRAINT "payments_order_id_orders_id_fk" FOREIGN KEY ("order_id") REFERENCES "public"."orders"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "saved_configurations" ADD CONSTRAINT "saved_configurations_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "saved_configurations" ADD CONSTRAINT "saved_configurations_silhouette_id_silhouettes_id_fk" FOREIGN KEY ("silhouette_id") REFERENCES "public"."silhouettes"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "saved_configurations" ADD CONSTRAINT "saved_configurations_fabric_id_fabrics_id_fk" FOREIGN KEY ("fabric_id") REFERENCES "public"."fabrics"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "saved_configurations" ADD CONSTRAINT "saved_configurations_measurement_profile_id_measurement_profiles_id_fk" FOREIGN KEY ("measurement_profile_id") REFERENCES "public"."measurement_profiles"("id") ON DELETE no action ON UPDATE no action;