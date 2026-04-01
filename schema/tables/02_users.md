# `02_users`

```sql
-- Table: users
-- Purpose: Core authentication and user accounts
-- Doc: docs/database/tables/02_users.md

CREATE TABLE IF NOT EXISTS public.users (
    id                int8        PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    created_at        timestamptz DEFAULT now(),
    email             text        UNIQUE,                -- unique, nullable
    is_creator        bool        DEFAULT false,         -- legacy; role_id is used by SPs
    updated_at        timestamptz DEFAULT now(),
    created_device_ip text        NULL,                  -- nullable
    updated_device_ip text        NULL,                  -- nullable
    password          text        NULL,                  -- null for Google users
    role_id           int8,                              -- 1 = user, 2 = creator; set by is_creator SP
    auth_provider     text        DEFAULT 'email'        -- 'email' or 'google'
);

-- Note: role_id has no FK constraint enforced at DB level
-- Note: is_creator SP sets role_id = 2 (creator) or 1 (user)
-- Note: create_profile SP checks role_id = 2 before allowing profile creation
```
