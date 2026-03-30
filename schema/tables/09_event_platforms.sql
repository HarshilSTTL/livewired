-- Table: event_platforms
-- Purpose: Links events to streaming platforms with stream URLs
-- Doc: docs/database/tables/09_event_platforms.md

CREATE TABLE IF NOT EXISTS public.event_platforms (
    id          uuid      PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id    uuid      REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
    platform_id int4,     -- ⚠️ int4 (not int8) — cast to ::bigint when joining platforms.plat_id
    stream_url  text,
    created_at  timestamp NULL DEFAULT now()  -- ⚠️ timestamp (no timezone), nullable
);

-- FK name: fk_event     → event_id    references public.event_mst.event_id
-- FK name: fk_platform  → platform_id references public.platforms.plat_id
