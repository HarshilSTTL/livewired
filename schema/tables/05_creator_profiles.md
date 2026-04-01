# `05_creator_profiles`

```sql
-- Table: creator_profiles
-- Purpose: Public creator profiles (one user can have multiple)
-- Doc: docs/database/tables/05_creator_profiles.md

CREATE TABLE IF NOT EXISTS public.creator_profiles (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    profile_name   text        NOT NULL,
    username       text        NOT NULL UNIQUE,   -- globally unique
    avatar         text        NULL,              -- nullable
    bio            text        NULL,              -- nullable
    is_default     boolean     DEFAULT false,
    status         text        DEFAULT 'active',  -- active | suspended | deleted
    show_followers boolean     DEFAULT true,
    created_at     timestamptz DEFAULT now(),
    updated_at     timestamptz DEFAULT now()
);
```
