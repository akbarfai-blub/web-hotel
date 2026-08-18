# Database Decision Log

## Project

Web Hotel — Single Property Hotel Booking System

## Status

Pre-Prisma Implementation

## Decision Principle

The current database architecture is fundamentally sound.
Changes below are focused on correctness, security, maintainability,
and PostgreSQL/Supabase compatibility.

The database remains PostgreSQL-first.
Prisma 7 is the application ORM and schema representation,
while PostgreSQL-specific features remain in SQL migrations where necessary.

---

# Decision Summary

| ID     | Area                | Decision                                       | Priority     | Status   |
| ------ | ------------------- | ---------------------------------------------- | ------------ | -------- |
| DB-001 | Double Booking      | Keep PostgreSQL EXCLUDE constraint             | MUST KEEP    | Approved |
| DB-002 | Date Range          | Keep `[)` half-open range                      | MUST KEEP    | Approved |
| DB-003 | Payment Status      | Add `expired`                                  | MUST FIX     | Approved |
| DB-004 | Payment Expiry Race | Define webhook-vs-expiry rule                  | MUST FIX     | Approved |
| DB-005 | Room Status         | Remove `occupied` as persisted state           | MUST FIX     | Approved |
| DB-006 | Rate Overlap        | Add PostgreSQL exclusion constraint            | MUST FIX     | Approved |
| DB-007 | RLS Role            | Resolve role from `public.users`               | MUST FIX     | Approved |
| DB-008 | Auth Profile        | Add `auth.users` → `public.users` trigger      | MUST FIX     | Approved |
| DB-009 | Price Items         | Keep price breakdown as immutable snapshot     | SHOULD FIX   | Approved |
| DB-010 | Payment Integrity   | Add payment/check constraints                  | SHOULD FIX   | Approved |
| DB-011 | Payment Attempts    | Allow multiple attempts, only one paid payment | SHOULD FIX   | Approved |
| DB-012 | Staff Queries       | Add arrival/departure indexes                  | SHOULD FIX   | Approved |
| DB-013 | FK Delete Rules     | Preserve payment/review history                | SHOULD FIX   | Approved |
| DB-014 | Payment Timestamps  | Consider expired_at / failed_at                | DEFERRED     | Deferred |
| DB-015 | Vector Index        | Prefer HNSW for small KB                       | OPTIMIZATION | Deferred |
| DB-016 | Room Maintenance    | Global maintenance for v1                      | DEFERRED     | Deferred |
| DB-017 | Booking Reference   | UUID acceptable for v1                         | DEFERRED     | Deferred |

---

# 1. Booking & Availability

## DB-001 — Double Booking Protection

Decision: KEEP.

Use PostgreSQL-level exclusion constraint:

- same physical room
- overlapping date range
- only active reservation statuses

Active statuses:

- pending_payment
- confirmed
- checked_in

Application-level availability checks are still required for UX,
but database constraint remains the final protection against race conditions.

Do not replace this with application-only validation.

---

## DB-002 — Half-Open Date Range

Decision: KEEP `[)`.

Example:

`2026-08-10 → 2026-08-12`

is represented as:

`[2026-08-10, 2026-08-12)`

Therefore:

- checkout on Aug 12
- next check-in on Aug 12

are allowed.

This matches hotel turnover behavior.

---

# 2. Payment Lifecycle

## DB-003 — Payment Expired State

Decision: ADD.

Payment status becomes:

- pending
- paid
- failed
- expired
- refunded

Reason:

Reservation expiry and payment expiry are distinct business states.

Midtrans expiry must be representable without incorrectly mapping it to `failed`.

---

## DB-004 — Payment Success After Reservation Expiry

Decision:

If a verified successful payment webhook arrives after the reservation
has already become `expired` or `cancelled`:

1. Do not restore the reservation automatically.
2. Record the payment result.
3. Initiate refund according to the payment flow.
4. Keep the reservation terminal.

This prevents an expired reservation from silently consuming inventory again.

The exact refund mechanism belongs to the application/payment layer,
not the database constraint layer.

---

# 3. Room Status

## DB-005 — Occupancy Is Derived

Decision: REMOVE `occupied` as a persisted room status.

`rooms.status` represents operational/housekeeping state only:

- available
- cleaning
- maintenance

Reservation occupancy is derived from:

- reservation status
- check-in date
- check-out date
- room_id

Do not use `rooms.status = occupied` as the source of truth for availability.

---

# 4. Room Type Rates

## DB-006 — Prevent Overlapping Rate Rules

Decision: ADD PostgreSQL exclusion constraint.

Rate ranges use half-open semantics:

`[start_date, end_date)`

The same room type must not have overlapping active rate periods.

The database must prevent conflicting rate definitions.

---

# 5. Authentication & Authorization

## DB-007 — RLS Role Resolution

Decision: Do not depend on an unsynchronized JWT `role` claim.

For v1, resolve role through:

`auth.uid() → public.users.id → public.users.role`

Use server-side authorization in addition to RLS.

RLS remains defense-in-depth.

---

## DB-008 — Supabase Auth Profile Trigger

Decision: ADD.

When a Supabase Auth user is created:

`auth.users`
→ trigger
→ `public.users`

`public.users.id` must equal `auth.users.id`.

Do not create a separate password/authentication system.

Role security:

- role always defaults to `guest`.
- role is never read from signup metadata, user metadata, or request fields.
- role changes are administrative and applied server-side afterwards.

Credential security:

- Only profile fields are copied: `id`, `email`, `full_name`.
- No password, password hash, tokens, or authentication secrets are stored.

Function security:

- `SECURITY DEFINER` is required because `public.users` has RLS enabled (DB-007) with no INSERT policy; the trigger runs as the table owner to insert the profile row.
- `search_path` is pinned to `public`.
- EXECUTE is revoked from PUBLIC (trigger-only function).

Deferred:

- `auth.users.email → public.users.email` synchronization on UPDATE is not implemented in this phase.
- Phone-only signups fail closed because `public.users.email` is NOT NULL.

---

# 6. Pricing

## DB-009 — Reservation Price Snapshot

Decision: KEEP.

Reservation totals are immutable historical snapshots.

Do not recalculate historical reservations from current room rates.

Reservation stores:

- subtotal
- discount_amount
- tax_amount
- service_fee
- total_price

`reservation_price_items` remains as detailed price breakdown.

Price items should be treated as immutable after reservation creation.

---

# 7. Payment Integrity

## DB-010 — Payment Constraints

Add:

- payment amount > 0
- price item quantity > 0
- price item unit amount >= 0
- price item total = quantity × unit amount
- discount amount <= subtotal

Cross-table business rules remain server-side.

---

## DB-011 — Multiple Payment Attempts

A reservation may have multiple payment attempts:

- expired
- failed
- retry
- paid

Only one payment may reach `paid` for a reservation.

Use a PostgreSQL partial unique index for paid payments.

---

# 8. Referential Integrity

## DB-013 — Preserve Financial & Review History

Payments and reviews must not be silently deleted when a reservation
is deleted.

Prefer restrictive delete semantics.

Guest PII deletion should use anonymization rather than deleting
historical reservation records.

---

# 9. Performance

## DB-012 — Staff Dashboard Indexes

Add indexes supporting:

- today's arrivals
- today's departures

Recommended:

- `(hotel_id, check_in_date)`
- `(hotel_id, check_out_date)`

Only add further indexes when backed by actual query patterns.

---

# 10. Deferred Decisions

The following are intentionally deferred:

- payment `expired_at`
- payment `failed_at`
- HNSW optimization
- date-scoped room maintenance
- human-readable booking reference
- advanced pricing periods
- advanced RLS optimization

These are not blockers for the first database migration.

---

# 11. PostgreSQL-Specific Features

The following remain PostgreSQL/Supabase responsibilities
and must not be forced into Prisma models:

- EXCLUDE USING GIST
- daterange
- partial indexes
- CHECK constraints where appropriate
- triggers
- RLS policies
- pgvector
- PostgreSQL extensions

Prisma remains the ORM and application schema representation.

Custom SQL migrations remain part of the database implementation.

---

# Final Decision

The database does not require a redesign.

The implementation should proceed after applying the MUST FIX
decisions and the high-value SHOULD FIX constraints.

Prisma 7 implementation should start only after this decision log
has been incorporated into the canonical database schema.
