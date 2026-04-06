# `02_users`

```sql
-- Table: users
-- Purpose: Core authentication and user accounts
-- Doc: docs/database/tables/02_users.md

CREATE TABLE IF NOT EXISTS public.users (
    id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at        timestamptz DEFAULT now(),
    email             text        UNIQUE,                -- unique, nullable
    is_creator        bool        DEFAULT false,         -- legacy; role_id is used by SPs
    updated_at        timestamptz DEFAULT now(),
    created_device_ip text        NULL,                  -- nullable
    updated_device_ip text        NULL,                  -- nullable
    password          text        NULL,                  -- null for Google users
    username          text        NULL,                    -- account-level username (required on new registrations, not unique)
    role_id           int8,                              -- 1 = user, 2 = creator; set by is_creator SP
    auth_provider     text        DEFAULT 'email',       -- 'email' or 'google'
    is_deleted        boolean     NOT NULL DEFAULT false, -- soft delete flag
    deleted_at        timestamptz NULL                    -- timestamp of soft delete
);

-- Note: role_id has no FK constraint enforced at DB level
-- Note: is_creator SP sets role_id = 2 (creator) or 1 (user)
-- Note: create_profile SP checks role_id = 2 before allowing profile creation
-- Migration: run once in Supabase SQL editor
--   ALTER TABLE public.users ALTER COLUMN password DROP NOT NULL;
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS auth_provider text DEFAULT 'email';
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false;
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS deleted_at timestamptz NULL;
--   ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text NULL;
--   DROP INDEX IF EXISTS users_username_key; -- remove unique constraint if previously applied
```
