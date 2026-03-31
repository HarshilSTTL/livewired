# `10_follows`

```sql
-- Table: follows
-- Purpose: User → creator profile follow relationships (soft delete pattern)
-- Doc: docs/database/tables/10_follows.md

CREATE TABLE IF NOT EXISTS public.follows (
    id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid        REFERENCES public.users(id),
    profile_id    uuid        REFERENCES public.creator_profiles(id),
    created_at    timestamptz NULL DEFAULT now(),   -- nullable
    is_active     bool        DEFAULT true,
    unfollowed_at timestamptz NULL                  -- nullable; set on unfollow
);

-- FK name: fk_user    → user_id    references public.users.id
-- FK name: fk_profile → profile_id references public.creator_profiles.id

-- Soft delete rules:
-- Follow:    INSERT (is_active=true, unfollowed_at=null)
-- Unfollow:  UPDATE SET is_active=false, unfollowed_at=now()
-- Re-follow: UPDATE SET is_active=true, unfollowed_at=null, created_at=now()
```
