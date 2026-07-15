# `02_users`

```sql
-- Table: users
-- Purpose: Core authentication and user accounts
-- Doc: docs/database/tables/02_users.md

CREATE TABLE IF NOT EXISTS public.users (
    id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),  -- same UUID as auth.users.id
    created_at         timestamptz DEFAULT now(),
    email              text        UNIQUE,                -- unique, nullable
    is_creator         bool        DEFAULT false,         -- legacy; role_id is used by SPs
    updated_at         timestamptz DEFAULT now(),
    created_device_ip  text        NULL,                  -- nullable
    updated_device_ip  text        NULL,                  -- nullable
    username           text        NULL,                    -- account-level username (required on new registrations, not unique)
    role_id            int8,                              -- 1 = user, 2 = creator; set by is_creator SP
    auth_provider      text        DEFAULT 'email',       -- 'email' or 'google'
    is_email_verified  boolean     NOT NULL DEFAULT false, -- synced from auth.users.email_confirmed_at via handle_email_verified trigger
    onboarding_completed boolean   NOT NULL DEFAULT false, -- true once user finishes OR skips the platform/tag onboarding screens
    is_deleted         boolean     NOT NULL DEFAULT false, -- soft delete flag
    deleted_at         timestamptz NULL                    -- timestamp of soft delete
);

-- Note: onboarding_completed is set true by submit_platform, submit_tags, and
--       skip_onboarding — NOT inferred from the presence of user_preferred_platforms/
--       user_interests rows, since a user can legitimately skip onboarding and have
--       zero rows in either table. See functions/platforms/submit_platform.md,
--       functions/tags/submit_tags.md, functions/auth/skip_onboarding.md.
-- Note: role_id has no FK constraint enforced at DB level
-- Note: is_creator SP sets role_id = 2 (creator) or 1 (user)
-- Note: create_profile SP checks role_id = 2 before allowing profile creation
-- Note: password column removed (2026-07-13) — Supabase Auth (auth.users) now owns
--       password storage/hashing entirely. See functions/auth/register.md,
--       functions/auth/signup.md, functions/auth/login.md — all deprecated.
-- Note: id is not a formal FK to auth.users.id (existing rows predate the migration
--       and would fail the constraint check) — the relationship is enforced going
--       forward only by the handle_new_auth_user trigger.
--       See functions/auth/handle_new_auth_user.md and functions/auth/handle_email_verified.md.
--
-- Migration: run once in Supabase SQL editor (historical — already applied 2026-07-13)
--   ALTER TABLE public.users DROP COLUMN IF EXISTS password;
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_email_verified boolean NOT NULL DEFAULT false;
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS auth_provider text DEFAULT 'email';
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false;
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS deleted_at timestamptz NULL;
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text NULL;
--   DROP INDEX IF EXISTS users_username_key; -- remove unique constraint if previously applied
--
-- Migration: run once in Supabase SQL editor (new — 2026-07-15)
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS onboarding_completed boolean NOT NULL DEFAULT false;
```
