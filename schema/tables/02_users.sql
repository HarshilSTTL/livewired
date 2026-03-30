-- Table: users
-- Purpose: Core authentication and user accounts
-- Doc: docs/database/tables/02_users.md

CREATE TABLE IF NOT EXISTS public.users (
    id                int8        PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    created_at        timestamptz DEFAULT now(),
    email             text        UNIQUE,                -- unique, nullable
    is_creator        bool        DEFAULT false,
    updated_at        timestamptz DEFAULT now(),
    created_device_ip text        NULL,                  -- nullable
    updated_device_ip text        NULL,                  -- nullable
    password          text
);

-- Note: No role_id FK — creator status is tracked via is_creator boolean
