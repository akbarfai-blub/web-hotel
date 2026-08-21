-- =========================================================
-- Web Hotel — Initial migration
--
-- Construction:
--   1. Prisma-generated baseline (npx prisma migrate diff
--      --from-empty --to-schema prisma/schema.prisma --script):
--      enums, tables, columns, defaults, PKs, FKs, normal
--      indexes/uniques, vector column.
--   2. Manually preserved PostgreSQL-specific objects from the
--      canonical schema (docs/database-schema.sql):
--      extensions, CHECK constraints, partial indexes,
--      EXCLUDE USING GIST constraints, pgvector index,
--      auth profile trigger, updated_at triggers, RLS.
--
-- Notes:
--   - ON UPDATE actions are intentionally left at the PostgreSQL
--     default (NO ACTION), matching the canonical schema; UUID PKs
--     never change.
--   - Requires a Supabase PostgreSQL environment: the auth trigger
--     depends on auth.users and RLS policies depend on auth.uid()
--     and the auth/JWT schemas.
-- =========================================================

-- =========================================================
-- PHASE A — EXTENSIONS (must exist before dependent objects)
-- =========================================================
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

CREATE SCHEMA IF NOT EXISTS "public";

-- =========================================================
-- PHASE B — ENUMS
-- =========================================================

-- CreateEnum
CREATE TYPE "user_role" AS ENUM ('guest', 'staff', 'admin');

-- CreateEnum
CREATE TYPE "reservation_status" AS ENUM ('pending_payment', 'confirmed', 'checked_in', 'checked_out', 'cancelled', 'no_show', 'expired');

-- CreateEnum
CREATE TYPE "payment_status" AS ENUM ('pending', 'paid', 'failed', 'expired', 'refunded');

-- =========================================================
-- PHASE C/D/E/F — TABLES, COLUMNS, DEFAULTS, CHECK CONSTRAINTS
-- (foreign keys are added after all tables exist)
-- =========================================================

-- CreateTable
CREATE TABLE "hotels" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "name" TEXT NOT NULL,
    "address" TEXT,
    "city" TEXT,
    "check_in_time" TIME NOT NULL DEFAULT '14:00'::time,
    "check_out_time" TIME NOT NULL DEFAULT '12:00'::time,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "hotels_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "users" (
    "id" UUID NOT NULL,
    "email" TEXT NOT NULL,
    "phone" TEXT,
    "full_name" TEXT NOT NULL,
    "role" "user_role" NOT NULL DEFAULT 'guest',
    "identity_number_encrypted" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "room_types" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "hotel_id" UUID NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "base_price" DECIMAL(12,2) NOT NULL,
    "max_occupancy" INTEGER NOT NULL DEFAULT 2,
    "size_sqm" DECIMAL(6,2),
    "amenities" JSONB NOT NULL DEFAULT '[]',
    "images" JSONB NOT NULL DEFAULT '[]',
    "is_active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "room_types_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "room_types_check" CHECK ("base_price" >= 0),
    CONSTRAINT "room_types_check1" CHECK ("max_occupancy" > 0),
    CONSTRAINT "room_types_check2" CHECK ("size_sqm" IS NULL OR "size_sqm" > 0)
);

-- CreateTable
CREATE TABLE "rooms" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "hotel_id" UUID NOT NULL,
    "room_type_id" UUID NOT NULL,
    "room_number" TEXT NOT NULL,
    "floor" INTEGER,
    -- Operational/housekeeping state only. Occupancy is derived from
    -- reservations (DB-005). No 'occupied' status.
    "status" TEXT NOT NULL DEFAULT 'available',
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "rooms_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "rooms_check" CHECK ("status" IN ('available','maintenance','cleaning'))
);

-- CreateTable
CREATE TABLE "room_type_rates" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "room_type_id" UUID NOT NULL,
    "start_date" DATE NOT NULL,
    "end_date" DATE NOT NULL,
    "price_override" DECIMAL(12,2) NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "room_type_rates_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "room_type_rates_check" CHECK ("price_override" >= 0),
    CONSTRAINT "room_type_rates_check1" CHECK ("end_date" > "start_date")
);

-- CreateTable
CREATE TABLE "reservations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "hotel_id" UUID NOT NULL,
    "guest_id" UUID NOT NULL,
    "room_id" UUID NOT NULL,
    "room_type_id" UUID NOT NULL,
    "check_in_date" DATE NOT NULL,
    "check_out_date" DATE NOT NULL,
    "guests_count" INTEGER NOT NULL DEFAULT 1,
    -- Immutable historical price snapshot (DB-009).
    "subtotal" DECIMAL(12,2) NOT NULL,
    "discount_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "tax_amount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "service_fee" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "total_price" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'IDR',
    "status" "reservation_status" NOT NULL DEFAULT 'pending_payment',
    "special_requests" TEXT,
    "payment_expires_at" TIMESTAMPTZ,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "reservations_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "reservations_check" CHECK ("check_out_date" > "check_in_date"),
    CONSTRAINT "reservations_check1" CHECK ("discount_amount" <= "subtotal"),
    CONSTRAINT "reservations_check2" CHECK (
        "total_price" =
        "subtotal"
        - "discount_amount"
        + "tax_amount"
        + "service_fee"
    )
);

-- CreateTable
CREATE TABLE "reservation_price_items" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "reservation_id" UUID NOT NULL,
    "item_type" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "quantity" DECIMAL(12,2) NOT NULL DEFAULT 1,
    "unit_amount" DECIMAL(12,2) NOT NULL,
    "total_amount" DECIMAL(12,2) NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "reservation_price_items_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "reservation_price_items_check" CHECK ("total_amount" = "quantity" * "unit_amount")
);

-- CreateTable
CREATE TABLE "payments" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "reservation_id" UUID NOT NULL,
    "provider" TEXT NOT NULL DEFAULT 'midtrans',
    "provider_order_id" TEXT,
    "provider_transaction_id" TEXT,
    "amount" DECIMAL(12,2) NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'IDR',
    "method" TEXT,
    "transaction_status" TEXT,
    "fraud_status" TEXT,
    "status" "payment_status" NOT NULL DEFAULT 'pending',
    "paid_at" TIMESTAMPTZ,
    "provider_response" JSONB,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "payments_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "payments_check" CHECK ("amount" > 0)
);

-- CreateTable
CREATE TABLE "reviews" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "reservation_id" UUID NOT NULL,
    "guest_id" UUID NOT NULL,
    "rating" INTEGER NOT NULL,
    "comment" TEXT,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "reviews_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "reviews_check" CHECK ("rating" BETWEEN 1 AND 5)
);

-- CreateTable
CREATE TABLE "chatbot_knowledge_base" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "hotel_id" UUID NOT NULL,
    "title" TEXT NOT NULL,
    "category" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "source_url" TEXT,
    "embedding" vector(1536),
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "updated_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "chatbot_knowledge_base_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "chatbot_knowledge_base_check" CHECK ("category" IN (
        'FAQ',
        'ROOM',
        'FACILITY',
        'POLICY',
        'LOCATION',
        'CONTACT'
    ))
);

-- CreateTable
CREATE TABLE "chatbot_conversations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID,
    "hotel_id" UUID,
    "started_at" TIMESTAMPTZ NOT NULL DEFAULT now(),
    "ended_at" TIMESTAMPTZ,

    CONSTRAINT "chatbot_conversations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "chatbot_messages" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "conversation_id" UUID NOT NULL,
    "sender" TEXT NOT NULL,
    "content" TEXT NOT NULL,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "chatbot_messages_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "chatbot_messages_check" CHECK ("sender" IN ('user','assistant'))
);

-- CreateTable
CREATE TABLE "audit_logs" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "actor_id" UUID,
    "action" TEXT NOT NULL,
    "entity_type" TEXT NOT NULL,
    "entity_id" UUID NOT NULL,
    "metadata" JSONB,
    "created_at" TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT "audit_logs_pkey" PRIMARY KEY ("id")
);

-- =========================================================
-- PHASE G — NORMAL INDEXES / UNIQUE INDEXES (Prisma-generated)
-- =========================================================

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE INDEX "idx_users_email" ON "users"("email");

-- CreateIndex
CREATE INDEX "idx_users_role" ON "users"("role");

-- CreateIndex
CREATE INDEX "idx_room_types_hotel" ON "room_types"("hotel_id");

-- CreateIndex
CREATE INDEX "idx_room_types_active" ON "room_types"("hotel_id", "is_active");

-- CreateIndex
CREATE UNIQUE INDEX "rooms_hotel_id_room_number_key" ON "rooms"("hotel_id", "room_number");

-- CreateIndex
CREATE INDEX "idx_rooms_type" ON "rooms"("room_type_id");

-- CreateIndex
CREATE INDEX "idx_rooms_hotel_status" ON "rooms"("hotel_id", "status");

-- CreateIndex
CREATE INDEX "idx_rates_room_type_dates" ON "room_type_rates"("room_type_id", "start_date", "end_date");

-- CreateIndex
CREATE INDEX "idx_reservations_room_dates" ON "reservations"("room_id", "check_in_date", "check_out_date");

-- CreateIndex
CREATE INDEX "idx_reservations_guest" ON "reservations"("guest_id");

-- CreateIndex
CREATE INDEX "idx_reservations_hotel_status" ON "reservations"("hotel_id", "status");

-- Staff dashboard: today's arrivals (DB-012).
-- CreateIndex
CREATE INDEX "idx_reservations_hotel_check_in" ON "reservations"("hotel_id", "check_in_date");

-- Staff dashboard: today's departures (DB-012).
-- CreateIndex
CREATE INDEX "idx_reservations_hotel_check_out" ON "reservations"("hotel_id", "check_out_date");

-- CreateIndex
CREATE INDEX "idx_price_items_reservation" ON "reservation_price_items"("reservation_id");

-- CreateIndex
CREATE UNIQUE INDEX "payments_provider_transaction_id_key" ON "payments"("provider_transaction_id");

-- CreateIndex
CREATE INDEX "idx_payments_reservation" ON "payments"("reservation_id");

-- CreateIndex
CREATE INDEX "idx_payments_provider_order" ON "payments"("provider_order_id");

-- One review per reservation.
-- CreateIndex
CREATE UNIQUE INDEX "uq_reviews_reservation" ON "reviews"("reservation_id");

-- CreateIndex
CREATE INDEX "idx_reviews_guest" ON "reviews"("guest_id");

-- CreateIndex
CREATE INDEX "idx_kb_hotel_category" ON "chatbot_knowledge_base"("hotel_id", "category");

-- CreateIndex
CREATE INDEX "idx_chatbot_conversations_user" ON "chatbot_conversations"("user_id");

-- CreateIndex
CREATE INDEX "idx_chatbot_messages_conv" ON "chatbot_messages"("conversation_id", "created_at");

-- CreateIndex
CREATE INDEX "idx_audit_entity" ON "audit_logs"("entity_type", "entity_id");

-- CreateIndex
CREATE INDEX "idx_audit_actor" ON "audit_logs"("actor_id", "created_at");

-- =========================================================
-- PHASE E — FOREIGN KEYS (canonical ON DELETE semantics;
-- ON UPDATE left at PostgreSQL default NO ACTION)
-- =========================================================

-- AddForeignKey
ALTER TABLE "room_types" ADD CONSTRAINT "room_types_hotel_id_fkey" FOREIGN KEY ("hotel_id") REFERENCES "hotels"("id") ON DELETE CASCADE;

-- AddForeignKey
ALTER TABLE "rooms" ADD CONSTRAINT "rooms_hotel_id_fkey" FOREIGN KEY ("hotel_id") REFERENCES "hotels"("id") ON DELETE CASCADE;

-- AddForeignKey
ALTER TABLE "rooms" ADD CONSTRAINT "rooms_room_type_id_fkey" FOREIGN KEY ("room_type_id") REFERENCES "room_types"("id") ON DELETE RESTRICT;

-- Deferred architectural decision: current canonical behavior kept.
-- AddForeignKey
ALTER TABLE "room_type_rates" ADD CONSTRAINT "room_type_rates_room_type_id_fkey" FOREIGN KEY ("room_type_id") REFERENCES "room_types"("id") ON DELETE CASCADE;

-- Deferred architectural decision: current canonical behavior kept.
-- AddForeignKey
ALTER TABLE "reservations" ADD CONSTRAINT "reservations_hotel_id_fkey" FOREIGN KEY ("hotel_id") REFERENCES "hotels"("id") ON DELETE CASCADE;

-- AddForeignKey
ALTER TABLE "reservations" ADD CONSTRAINT "reservations_guest_id_fkey" FOREIGN KEY ("guest_id") REFERENCES "users"("id") ON DELETE RESTRICT;

-- AddForeignKey
ALTER TABLE "reservations" ADD CONSTRAINT "reservations_room_id_fkey" FOREIGN KEY ("room_id") REFERENCES "rooms"("id") ON DELETE RESTRICT;

-- AddForeignKey
ALTER TABLE "reservations" ADD CONSTRAINT "reservations_room_type_id_fkey" FOREIGN KEY ("room_type_id") REFERENCES "room_types"("id") ON DELETE RESTRICT;

-- Dependent data: cascades with its reservation (DB-013).
-- AddForeignKey
ALTER TABLE "reservation_price_items" ADD CONSTRAINT "reservation_price_items_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "reservations"("id") ON DELETE CASCADE;

-- Financial history protected (DB-013).
-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "reservations"("id") ON DELETE RESTRICT;

-- Review history protected (DB-013).
-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_reservation_id_fkey" FOREIGN KEY ("reservation_id") REFERENCES "reservations"("id") ON DELETE RESTRICT;

-- Guest review history protected (DB-013).
-- AddForeignKey
ALTER TABLE "reviews" ADD CONSTRAINT "reviews_guest_id_fkey" FOREIGN KEY ("guest_id") REFERENCES "users"("id") ON DELETE RESTRICT;

-- AddForeignKey
ALTER TABLE "chatbot_knowledge_base" ADD CONSTRAINT "chatbot_knowledge_base_hotel_id_fkey" FOREIGN KEY ("hotel_id") REFERENCES "hotels"("id") ON DELETE CASCADE;

-- Optional relationships: nullable columns with SET NULL.
-- AddForeignKey
ALTER TABLE "chatbot_conversations" ADD CONSTRAINT "chatbot_conversations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL;

-- AddForeignKey
ALTER TABLE "chatbot_conversations" ADD CONSTRAINT "chatbot_conversations_hotel_id_fkey" FOREIGN KEY ("hotel_id") REFERENCES "hotels"("id") ON DELETE SET NULL;

-- Dependent data: messages cascade with their conversation.
-- AddForeignKey
ALTER TABLE "chatbot_messages" ADD CONSTRAINT "chatbot_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "chatbot_conversations"("id") ON DELETE CASCADE;

-- Audit history survives actor deletion via SET NULL.
-- AddForeignKey
ALTER TABLE "audit_logs" ADD CONSTRAINT "audit_logs_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "users"("id") ON DELETE SET NULL;

-- =========================================================
-- PHASE H — PARTIAL INDEXES (SQL-managed)
-- =========================================================

-- Reservation payment expiry lookup for pending reservations.
CREATE INDEX idx_reservations_payment_expiry
    ON "reservations"(payment_expires_at)
    WHERE status = 'pending_payment';

-- DB-011: multiple payment attempts allowed per reservation;
-- exactly one paid payment per reservation. reservation_id is
-- intentionally NOT globally unique.
CREATE UNIQUE INDEX uq_payments_one_paid
    ON "payments"(reservation_id)
    WHERE status = 'paid';

-- =========================================================
-- PHASE I — EXCLUSION CONSTRAINTS (DB-001 / DB-002 / DB-006)
-- Require btree_gist (Phase A). Half-open [start, end) ranges.
-- =========================================================

-- Prevent conflicting rate periods for the same room type.
-- Same-day boundaries do not overlap ([2026-08-01, 2026-08-15)
-- and [2026-08-15, 2026-08-31) are both allowed).
ALTER TABLE "room_type_rates"
ADD CONSTRAINT no_overlapping_rates
EXCLUDE USING gist (
    room_type_id WITH =,
    daterange(start_date, end_date, '[)') WITH &&
);

-- Prevent double booking for active reservations.
-- Same-day checkout/check-in is allowed.
ALTER TABLE "reservations"
ADD CONSTRAINT no_overlapping_bookings
EXCLUDE USING gist (
    room_id WITH =,
    daterange(check_in_date, check_out_date, '[)') WITH &&
)
WHERE (
    status IN ('pending_payment', 'confirmed', 'checked_in')
);

-- =========================================================
-- PHASE J — PGVECTOR INDEX
-- =========================================================

CREATE INDEX idx_kb_embedding
    ON "chatbot_knowledge_base"
    USING ivfflat (embedding vector_cosine_ops);

-- =========================================================
-- PHASE K — SUPABASE AUTH PROFILE TRIGGER (DB-008)
-- Depends on Supabase's auth.users schema.
-- Role always defaults to 'guest'; never read from metadata.
-- Only profile fields are copied (no credentials/secrets).
-- =========================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, email, full_name)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(
            NULLIF(NEW.raw_user_meta_data ->> 'full_name', ''),
            NULLIF(NEW.raw_user_meta_data ->> 'name', ''),
            'Guest'
        )
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;

CREATE TRIGGER trg_handle_new_user
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user();

-- =========================================================
-- UPDATED_AT TRIGGERS (database-owned; no @updatedAt in Prisma)
-- =========================================================

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_hotels_updated_at
BEFORE UPDATE ON hotels
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_room_types_updated_at
BEFORE UPDATE ON room_types
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_rooms_updated_at
BEFORE UPDATE ON rooms
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_room_type_rates_updated_at
BEFORE UPDATE ON room_type_rates
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_reservations_updated_at
BEFORE UPDATE ON reservations
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_payments_updated_at
BEFORE UPDATE ON payments
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_chatbot_kb_updated_at
BEFORE UPDATE ON chatbot_knowledge_base
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =========================================================
-- PHASE L — ROW LEVEL SECURITY (DB-007)
-- Role resolution: auth.uid() -> public.users.id -> public.users.role
-- No JWT claims, no Auth Hook. RLS is defense-in-depth.
-- hotels has no RLS (public property information only).
-- =========================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_type_rates ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservation_price_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE chatbot_knowledge_base ENABLE ROW LEVEL SECURITY;
ALTER TABLE chatbot_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE chatbot_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Guest can read own profile.
-- Required so role resolution via public.users works: without it the
-- role-lookup subqueries below see no rows (RLS default-deny) and
-- staff/admin policies would never match.
CREATE POLICY guest_own_profile_select
ON users
FOR SELECT
USING (id = auth.uid());

-- Guest can read own reservations.
CREATE POLICY guest_own_reservations_select
ON reservations
FOR SELECT
USING (guest_id = auth.uid());

-- Staff/admin can read all reservations.
-- Role is resolved from public.users.role, not from a JWT claim.
CREATE POLICY staff_admin_reservations_select
ON reservations
FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM users u
        WHERE u.id = auth.uid()
          AND u.role IN ('staff', 'admin')
    )
);

-- Guest can read own payments through reservation ownership.
CREATE POLICY guest_own_payments_select
ON payments
FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM reservations r
        WHERE r.id = payments.reservation_id
          AND r.guest_id = auth.uid()
    )
);

-- Staff/admin can read payments.
CREATE POLICY staff_admin_payments_select
ON payments
FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM users u
        WHERE u.id = auth.uid()
          AND u.role IN ('staff', 'admin')
    )
);

-- Guest can read own reviews.
CREATE POLICY guest_own_reviews_select
ON reviews
FOR SELECT
USING (guest_id = auth.uid());

-- Public/guest can read active room types.
CREATE POLICY public_active_room_types_select
ON room_types
FOR SELECT
USING (is_active = true);

-- Public/guest can read rooms only when active inventory is needed.
-- Application queries should still constrain by hotel and status.
CREATE POLICY public_rooms_select
ON rooms
FOR SELECT
USING (true);

-- Admin/staff knowledge base read; admin write should be added
-- according to the final dashboard flow.
CREATE POLICY staff_admin_kb_select
ON chatbot_knowledge_base
FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM users u
        WHERE u.id = auth.uid()
          AND u.role IN ('staff', 'admin')
    )
);

-- Users can read their own chatbot conversations.
CREATE POLICY own_chatbot_conversations_select
ON chatbot_conversations
FOR SELECT
USING (user_id = auth.uid());

CREATE POLICY own_chatbot_messages_select
ON chatbot_messages
FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM chatbot_conversations c
        WHERE c.id = chatbot_messages.conversation_id
          AND c.user_id = auth.uid()
    )
);

-- Audit logs are not guest-readable.
-- Staff/admin read policy:
CREATE POLICY staff_admin_audit_select
ON audit_logs
FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM users u
        WHERE u.id = auth.uid()
          AND u.role IN ('staff', 'admin')
    )
);
