# `14_profile_custom_links`

```sql
-- Table: profile_custom_links
-- Purpose: Stores creator-defined custom platform links (name + URL) per profile.
--          Visible only to the profile owner via get_all_platforms (p_profile_id).
--          Supports soft delete — rows are never hard-deleted.
-- Doc: docs/database/tables/14_profile_custom_links.md

CREATE TABLE IF NOT EXISTS public.profile_custom_links (
    id           uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id   uuid      NOT NULL REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
    profile_name text      NOT NULL,   -- user-defined platform name e.g. "Amazon", "Cashapp"
    profile_url  text      NOT NULL,   -- full URL for the link
    is_deleted   boolean   NOT NULL DEFAULT false,  -- soft delete flag
    deleted_at   timestamp NULL,                    -- set when is_deleted = true
    created_at   timestamp NULL DEFAULT now(),
    updated_at   timestamp NULL DEFAULT now()
);

-- FK: fk_profile → profile_id references public.creator_profiles.id
```
