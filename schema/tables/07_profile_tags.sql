-- Table: profile_tags
-- Purpose: Junction table — links creator profiles to interest/category tags
-- Doc: docs/database/tables/07_profile_tags.md

CREATE TABLE IF NOT EXISTS public.profile_tags (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id uuid NULL REFERENCES public.creator_profiles(id) ON DELETE CASCADE,  -- nullable
    tag_id     int8 NULL REFERENCES public.tags(tag_id)                              -- nullable
);
