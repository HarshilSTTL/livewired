# `06_creator_platform_accounts`

```sql
-- Table: creator_platform_accounts
-- Purpose: Links a creator profile to their accounts on streaming platforms
-- Doc: docs/database/tables/06_creator_platform_accounts.md

CREATE TABLE IF NOT EXISTS public.creator_platform_accounts (
    id          uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id  uuid      NOT NULL REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
    platform_id int8      NOT NULL REFERENCES public.platforms(plat_id),
    channel_url text      NULL,      -- nullable at DB level; required by create_profile SP when platforms provided
    username    text      NULL,      -- nullable; defaults to profile username in create_profile SP
    is_default  boolean   DEFAULT false,
    is_deleted  boolean   NOT NULL DEFAULT false,  -- soft delete flag
    deleted_at  timestamp NULL                     -- set when is_deleted = true
);

-- Migration (run once in Supabase SQL editor):
--   ALTER TABLE public.creator_platform_accounts
--       ADD COLUMN is_deleted boolean NOT NULL DEFAULT false,
--       ADD COLUMN deleted_at timestamp NULL;
```
