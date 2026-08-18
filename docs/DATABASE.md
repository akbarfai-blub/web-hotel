-- =========================================================
-- Web Hotel - Optimized Database Schema
-- PostgreSQL / Supabase / pgvector
-- Version: 2.0
-- =========================================================
--
-- Design principles:
-- 1. Supabase Auth is the source of identity.
-- 2. public.users stores application profile/role only.
-- 3. PostgreSQL is source of truth for inventory and transactions.
-- 4. Reservation pricing is stored as a transaction snapshot.
-- 5. Exclusion constraint protects against overlapping bookings.
-- 6. Payment confirmation is driven by verified webhook.
-- 7. RLS is defense-in-depth, not a replacement for server authorization.
-- =========================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "vector";
CREATE EXTENSION IF NOT EXISTS "btree_gist";

-- =========================================================
-- 1. HOTEL
-- =========================================================

CREATE TABLE hotels (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    address TEXT,
    city TEXT,
    check_in_time TIME NOT NULL DEFAULT '14:00',
    check_out_time TIME NOT NULL DEFAULT '12:00',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =========================================================
-- 2. USERS / APPLICATION PROFILE
-- Supabase Auth owns credentials.
-- Do NOT store password_hash here.
-- Ideally users.id is linked to auth.users.id.
-- =========================================================

CREATE TYPE user_role AS ENUM ('guest', 'staff', 'admin');

CREATE TABLE users (
    id UUID PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    phone TEXT,
    full_name TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'guest',
    identity_number_encrypted TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_role ON users(role);

-- =========================================================
-- 3. ROOM TYPES & ROOMS
-- =========================================================

CREATE TABLE room_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hotel_id UUID NOT NULL REFERENCES hotels(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    base_price NUMERIC(12,2) NOT NULL CHECK (base_price >= 0),
    max_occupancy INT NOT NULL DEFAULT 2 CHECK (max_occupancy > 0),
    size_sqm NUMERIC(6,2) CHECK (size_sqm IS NULL OR size_sqm > 0),
    amenities JSONB NOT NULL DEFAULT '[]'::jsonb,
    images JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_room_types_hotel ON room_types(hotel_id);
CREATE INDEX idx_room_types_active ON room_types(hotel_id, is_active);

-- rooms.status represents OPERATIONAL / HOUSEKEEPING state only.
-- Occupancy is NOT persisted here; it is derived from reservations
-- (room_id + active reservation status + check_in/check_out dates).
-- A room can be operationally 'available' yet still unavailable for a
-- specific date range because an active reservation exists.
-- Availability is computed by the booking engine from reservations.
CREATE TABLE rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hotel_id UUID NOT NULL REFERENCES hotels(id) ON DELETE CASCADE,
    room_type_id UUID NOT NULL REFERENCES room_types(id) ON DELETE RESTRICT,
    room_number TEXT NOT NULL,
    floor INT,
    status TEXT NOT NULL DEFAULT 'available'
        CHECK (status IN ('available','maintenance','cleaning')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (hotel_id, room_number)
);

CREATE INDEX idx_rooms_type ON rooms(room_type_id);
CREATE INDEX idx_rooms_hotel_status ON rooms(hotel_id, status);

-- =========================================================
-- 4. ROOM TYPE RATES
-- Seasonal/dynamic pricing.
-- Date range is inclusive.
-- Application layer should prevent conflicting rate rules
-- for the same room type/date range.
-- =========================================================

CREATE TABLE room_type_rates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_type_id UUID NOT NULL REFERENCES room_types(id) ON DELETE CASCADE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    price_override NUMERIC(12,2) NOT NULL CHECK (price_override >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (end_date >= start_date)
);

CREATE INDEX idx_rates_room_type_dates
    ON room_type_rates(room_type_id, start_date, end_date);

-- =========================================================
-- 5. RESERVATIONS
-- =========================================================

CREATE TYPE reservation_status AS ENUM (
    'pending_payment',
    'confirmed',
    'checked_in',
    'checked_out',
    'cancelled',
    'no_show',
    'expired'
);

CREATE TABLE reservations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hotel_id UUID NOT NULL REFERENCES hotels(id) ON DELETE CASCADE,
    guest_id UUID NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE RESTRICT,
    room_type_id UUID NOT NULL REFERENCES room_types(id) ON DELETE RESTRICT,

    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    guests_count INT NOT NULL DEFAULT 1 CHECK (guests_count > 0),

    -- Transaction price snapshot
    subtotal NUMERIC(12,2) NOT NULL CHECK (subtotal >= 0),
    discount_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    tax_amount NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    service_fee NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (service_fee >= 0),
    total_price NUMERIC(12,2) NOT NULL CHECK (total_price >= 0),

    currency TEXT NOT NULL DEFAULT 'IDR',
    status reservation_status NOT NULL DEFAULT 'pending_payment',

    special_requests TEXT,

    -- Payment reservation lock/expiration
    payment_expires_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CHECK (check_out_date > check_in_date),
    CHECK (
        total_price =
        subtotal
        - discount_amount
        + tax_amount
        + service_fee
    )
);

CREATE INDEX idx_reservations_room_dates
    ON reservations(room_id, check_in_date, check_out_date);

CREATE INDEX idx_reservations_guest
    ON reservations(guest_id);

CREATE INDEX idx_reservations_hotel_status
    ON reservations(hotel_id, status);

CREATE INDEX idx_reservations_payment_expiry
    ON reservations(payment_expires_at)
    WHERE status = 'pending_payment';

-- Prevent double booking for active reservations.
-- Date range uses [check_in, check_out), so same-day checkout/check-in
-- is allowed.
ALTER TABLE reservations
ADD CONSTRAINT no_overlapping_bookings
EXCLUDE USING gist (
    room_id WITH =,
    daterange(check_in_date, check_out_date, '[)') WITH &&
)
WHERE (
    status IN ('pending_payment', 'confirmed', 'checked_in')
);

-- =========================================================
-- 6. RESERVATION PRICE ITEMS
-- Optional detailed pricing snapshot for audit/reporting.
-- =========================================================

CREATE TABLE reservation_price_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id UUID NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
    item_type TEXT NOT NULL
        CHECK (item_type IN ('room_charge', 'tax', 'service_fee', 'discount', 'other')),
    description TEXT NOT NULL,
    quantity NUMERIC(12,2) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_amount NUMERIC(12,2) NOT NULL,
    total_amount NUMERIC(12,2) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_price_items_reservation
    ON reservation_price_items(reservation_id);

-- =========================================================
-- 7. PAYMENTS
-- Payment status is updated by verified provider webhook.
-- =========================================================

CREATE TYPE payment_status AS ENUM (
    'pending',
    'paid',
    'failed',
    'expired',
    'refunded'
);

CREATE TABLE payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id UUID NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,

    provider TEXT NOT NULL DEFAULT 'midtrans',
    provider_order_id TEXT,
    provider_transaction_id TEXT UNIQUE,

    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    currency TEXT NOT NULL DEFAULT 'IDR',

    method TEXT,
    transaction_status TEXT,
    fraud_status TEXT,

    status payment_status NOT NULL DEFAULT 'pending',
    paid_at TIMESTAMPTZ,

    -- Keep provider payload only if needed for reconciliation/debugging.
    -- Never store card credentials or sensitive payment authentication data.
    provider_response JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_payments_reservation
    ON payments(reservation_id);

CREATE INDEX idx_payments_provider_order
    ON payments(provider_order_id);

-- =========================================================
-- 8. REVIEWS
-- =========================================================

CREATE TABLE reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reservation_id UUID NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
    guest_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX uq_reviews_reservation
    ON reviews(reservation_id);

CREATE INDEX idx_reviews_guest
    ON reviews(guest_id);

-- =========================================================
-- 9. CHATBOT KNOWLEDGE BASE
-- =========================================================

CREATE TABLE chatbot_knowledge_base (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hotel_id UUID NOT NULL REFERENCES hotels(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    category TEXT NOT NULL
        CHECK (category IN (
            'FAQ',
            'ROOM',
            'FACILITY',
            'POLICY',
            'LOCATION',
            'CONTACT'
        )),
    content TEXT NOT NULL,
    source_url TEXT,
    embedding VECTOR(1536),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_kb_hotel_category
    ON chatbot_knowledge_base(hotel_id, category);

CREATE INDEX idx_kb_embedding
    ON chatbot_knowledge_base
    USING ivfflat (embedding vector_cosine_ops);

-- =========================================================
-- 10. CHATBOT CONVERSATIONS & MESSAGES
-- =========================================================

CREATE TABLE chatbot_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    hotel_id UUID REFERENCES hotels(id) ON DELETE SET NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at TIMESTAMPTZ
);

CREATE INDEX idx_chatbot_conversations_user
    ON chatbot_conversations(user_id);

CREATE TABLE chatbot_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL
        REFERENCES chatbot_conversations(id) ON DELETE CASCADE,
    sender TEXT NOT NULL CHECK (sender IN ('user','assistant')),
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_chatbot_messages_conv
    ON chatbot_messages(conversation_id, created_at);

-- =========================================================
-- 11. AUDIT LOG
-- =========================================================

CREATE TABLE audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_entity
    ON audit_logs(entity_type, entity_id);

CREATE INDEX idx_audit_actor
    ON audit_logs(actor_id, created_at);

-- =========================================================
-- 12. UPDATED_AT HELPER
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
-- 13. ROW LEVEL SECURITY
-- =========================================================
--
-- Important:
-- The exact role-claim implementation depends on Supabase Auth setup.
-- Do not assume a client-provided role is trustworthy.
-- The policies below are a baseline and should be adapted to the
-- final JWT/custom-claims configuration.
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

-- Guest can read own reservations.
CREATE POLICY guest_own_reservations_select
ON reservations
FOR SELECT
USING (guest_id = auth.uid());

-- Staff/admin can read all reservations.
CREATE POLICY staff_admin_reservations_select
ON reservations
FOR SELECT
USING (
    (auth.jwt() ->> 'role') IN ('staff', 'admin')
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
    (auth.jwt() ->> 'role') IN ('staff', 'admin')
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
    (auth.jwt() ->> 'role') IN ('staff', 'admin')
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
    (auth.jwt() ->> 'role') IN ('staff', 'admin')
);

-- =========================================================
-- 14. SECURITY NOTES
-- =========================================================
--
-- 1. Use Supabase Auth for credentials; no password_hash column.
-- 2. Identity numbers must be encrypted in application layer.
-- 3. Service role key must never be exposed to browser/client.
-- 4. Reservation creation/update should happen through server-side
--    application logic, not arbitrary client INSERT/UPDATE.
-- 5. Payment webhook must verify provider authenticity and be idempotent.
-- 6. Server must recalculate price before creating reservation.
-- 7. RLS policies must be tested with guest/staff/admin identities.
-- 8. Provider response must never contain card credentials.
-- 9. Consider retention/deletion workflows for personal data.
-- 10. Add rate limiting to authentication, booking, webhook and chatbot
--     endpoints at the application/edge layer.
-- =========================================================
