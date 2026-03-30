-- Table: user_preferred_platforms
-- Purpose: User's selected streaming platforms from onboarding
-- Doc: docs/database/tables/11_user_preferred_platforms.md

CREATE TABLE IF NOT EXISTS public.user_preferred_platforms (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        REFERENCES public.users(id),
    platform_id int8        REFERENCES public.platforms(plat_id),
    created_at  timestamptz DEFAULT now()
);

-- FK name: user_preferred_platforms_user_id_fkey     → user_id     references public.users.id
-- FK name: user_preferred_platforms_platform_id_fkey → platform_id references public.platforms.plat_id

-- Note: platform_id is int8 here (unlike event_platforms.platform_id which is int4)
-- Note: submit_platform does DELETE + INSERT (replace-all), not append
