# PRISMA-004 — Closure Report

## 1. Status

**COMPLETE / PASS**

Phase: PRISMA-004 — Apply & Verify Initial Migration on Supabase

## 2. Objective

Apply the approved initial Prisma migration to the Supabase PostgreSQL
database, verify full catalog parity with the canonical database design
(`docs/database-schema.sql`), verify Auth/RLS architecture (DB-007,
DB-008), resolve any security findings discovered during verification,
and behaviorally test critical constraints via rolled-back smoke tests.

## 3. Migration History

| # | Migration | Purpose | Result |
|---|-----------|---------|--------|
| 1 | `prisma/migrations/20260822000000_init/migration.sql` | Initial database migration | Applied successfully to Supabase |
| 2 | `prisma/migrations/20260822010000_restrict_handle_new_user_execute/migration.sql` | Security hardening — revokes EXECUTE privilege on `public.handle_new_user()` from `anon`, `authenticated`, and `service_role` | Applied successfully to Supabase |

## 4. Migration Application Result

```
2 migrations found in prisma/migrations
Database schema is up to date!
```

Prisma validation:

```
The schema at prisma\schema.prisma is valid.
```

## 5. Catalog Verification

### Extensions

- pgcrypto
- vector
- btree_gist

Actual verified versions:

- btree_gist 1.7
- pgcrypto 1.3
- vector 0.8.2

### Tables

- 13/13 verified

### Columns / Types

- Verified.
- UUID, DATE, TIMESTAMPTZ, TIME, JSONB, ENUM, NUMERIC precision/scale,
  and vector types verified.
- Financial NUMERIC precision/scale verified.

### Foreign Keys

- 17/17 verified.
- `update_rule` is NO ACTION across all verified FKs.
- Delete rules match the canonical design.

### CHECK Constraints

- 14/14 verified.

Important CHECK behavior verified:

- `check_out_date > check_in_date`
- `end_date > start_date`
- `discount_amount <= subtotal`
- `total_price = subtotal - discount_amount + tax_amount + service_fee`
- payment amount > 0
- `quantity * unit_amount = total_amount`
- rating between 1 and 5
- valid room status values
- valid chatbot sender/category values

### Indexes

- Normal indexes verified.
- Unique indexes verified.
- Partial indexes verified.
- Payment one-paid uniqueness verified (`uq_payments_one_paid`).
- Reservation payment-expiry index verified
  (`idx_reservations_payment_expiry`).

### EXCLUDE Constraints

- 2/2 verified:
  - `no_overlapping_bookings`
  - `no_overlapping_rates`
- daterange uses `[)` semantics.
- Booking exclusion applies to active reservation statuses.

### pgvector

- `idx_kb_embedding` verified.
- USING ivfflat.
- vector_cosine_ops.
- vector extension available.

## 6. Auth / RLS Verification

### RLS

- 12/12 target tables have RLS enabled.

### Policies

- 12/12 verified.

### Role Resolution

```
auth.uid()
→ public.users.id
→ public.users.role
```

No `auth.jwt()` role resolution is used.

### handle_new_user()

- Exists.
- SECURITY DEFINER.
- SET search_path = public.
- Does not read role from user metadata.
- Profile role uses database default guest behavior.

### Auth Trigger

- auth.users
- AFTER INSERT
- trg_handle_new_user
- executes handle_new_user()

### updated_at

- set_updated_at() verified.
- NEW.updated_at = now().
- 8/8 BEFORE UPDATE triggers verified.

## 7. Security Finding & Resolution

**Verified fact (security finding discovered during E-3):**
`anon` and `authenticated` initially had EXECUTE privilege on
`public.handle_new_user()`.

**Security resolution:**
A second migration was created and applied:

`20260822010000_restrict_handle_new_user_execute`

Final expected ACL on `public.handle_new_user()`:

| Role | Privilege |
|------|-----------|
| postgres | EXECUTE |
| anon | NO EXECUTE |
| authenticated | NO EXECUTE |
| service_role | NO EXECUTE |
| PUBLIC | NO EXECUTE |

## 8. Constraint Smoke Test

All smoke tests were executed inside transactions and rolled back.

Tests passed:

- [x] valid reservation → accepted
- [x] overlapping booking → rejected
- [x] adjacent booking using `[)` → accepted
- [x] overlapping rate → rejected
- [x] multiple payment attempts → accepted
- [x] second paid payment → rejected
- [x] invalid payment amount → rejected
- [x] invalid reservation price item total → rejected
- [x] discount greater than subtotal → rejected
- [x] invalid reservation total_price → rejected

No smoke-test fixture data was intentionally left in the database.

## 9. Final Repository State

```
git status --short:
?? prisma/migrations/

git diff --check: clean / no output
```

The migrations are currently uncommitted. They are not committed as
part of this closure task.

## 10. What Was Not Done

The following were intentionally **not** performed in PRISMA-004:

- No commit of the migration files.
- No modification of `prisma/schema.prisma`.
- No modification of any existing migration after application.
- No changes to RLS policies beyond the documented security
  hardening migration.
- No changes to PostgreSQL functions/triggers beyond the documented
  security hardening migration.
- No changes to application source code.
- No destructive database commands (`migrate reset`, `db push`).

## 11. Acceptance Criteria

- [x] Initial migration applied successfully to Supabase.
- [x] Security hardening migration applied successfully to Supabase.
- [x] Prisma reports schema up to date; 2 migrations found.
- [x] `npx prisma validate` passes.
- [x] Extensions verified: pgcrypto, vector, btree_gist (with versions).
- [x] 13/13 tables verified.
- [x] Column types verified, including financial NUMERIC precision/scale.
- [x] 17/17 foreign keys verified; update_rule NO ACTION; delete rules canonical.
- [x] 14/14 CHECK constraints verified with key behaviors tested.
- [x] Normal, unique, and partial indexes verified.
- [x] 2/2 EXCLUDE constraints verified with `[)` semantics.
- [x] pgvector index verified (ivfflat, vector_cosine_ops).
- [x] 12/12 RLS-enabled tables verified; 12/12 policies verified.
- [x] Role resolution via public.users confirmed; no JWT claim dependency.
- [x] handle_new_user() verified (SECURITY DEFINER, pinned search_path).
- [x] Auth trigger trg_handle_new_user verified.
- [x] updated_at function and 8/8 triggers verified.
- [x] Security finding identified, resolved, final ACL confirmed.
- [x] 10/10 constraint smoke tests passed inside rolled-back transactions.
- [x] No fixture data left in the database.
- [x] No source-of-truth or application files modified.

## 12. Final Closure

PRISMA-004 is officially CLOSED.
The Supabase database has been applied, catalog-verified,
Auth/RLS-verified, security-hardened, and behaviorally tested.

## 13. Handoff to PRISMA-005

Handoff:
PRISMA-005 can begin from this verified database foundation.
