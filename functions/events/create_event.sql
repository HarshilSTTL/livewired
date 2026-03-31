-- Function: create_event
-- Group:    events
-- Endpoint: POST /rpc/create_event
-- Tables:   event_mst (INSERT), event_platforms (INSERT)
-- Doc:      docs/api/events/create_event.md
--
-- Notes:
--   • event_platforms.platform_id is int4 — cast (pl->>'platform_id')::int4 on INSERT.
--   • Validate platform IDs against platforms.plat_id (int8) using ::bigint cast.
--   • Ownership check: profile must exist, belong to p_user_id, and be 'active'.
--   • p_platforms null → no event_platforms rows created.
--   • p_platforms [] empty array → no event_platforms rows created.

CREATE OR REPLACE FUNCTION create_event(
    p_profile_id   uuid,
    p_user_id      uuid,
    p_title        text,
    p_event_link   text,
    p_event_date   date,
    p_event_time   time,
    p_description  text     DEFAULT null,
    p_livestream   boolean  DEFAULT false,
    p_video        boolean  DEFAULT false,
    p_is_recurring boolean  DEFAULT false,
    p_platforms    jsonb    DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_id    uuid;
    v_platform    jsonb;
    v_platform_id bigint;
    v_stream_url  text;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    -- ── Ownership + active check ───────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id AND status = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found, access denied, or profile is not active');
    END IF;

    -- ── Required field validation ──────────────────────────────────────────────
    IF p_title IS NULL OR trim(p_title) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Event title is required');
    END IF;

    IF p_event_link IS NULL OR trim(p_event_link) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Event link is required');
    END IF;

    IF p_event_date IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event date is required');
    END IF;

    IF p_event_time IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event time is required');
    END IF;

    -- ── Platform validation (if provided and non-empty) ────────────────────────
    IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN

        -- All platform_ids must exist in platforms table
        -- Validate against int8 (plat_id), cast from jsonb text
        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
            WHERE NOT EXISTS (
                SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint
            )
        ) THEN
            RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
        END IF;

        -- stream_url required for every platform entry
        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
            WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
        ) THEN
            RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
        END IF;

    END IF;

    -- ── Insert into event_mst ─────────────────────────────────────────────────
    INSERT INTO event_mst (
        event_id, profile_id, title, description,
        event_link, event_date, event_time,
        livestream, video, is_recurring,
        created_at, updated_at
    )
    VALUES (
        gen_random_uuid(), p_profile_id, p_title, p_description,
        p_event_link, p_event_date, p_event_time,
        COALESCE(p_livestream, false), COALESCE(p_video, false), COALESCE(p_is_recurring, false),
        now(), now()
    )
    RETURNING event_id INTO v_event_id;

    -- ── Insert into event_platforms ───────────────────────────────────────────
    -- ⚠️ platform_id column is int4 — cast ::int4 on INSERT
    IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
        FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
        LOOP
            v_platform_id := (v_platform->>'platform_id')::bigint;
            v_stream_url  := v_platform->>'stream_url';

            INSERT INTO event_platforms (
                id, event_id, platform_id, stream_url, created_at
            )
            VALUES (
                gen_random_uuid(), v_event_id, v_platform_id::int4, v_stream_url, now()
            );
        END LOOP;
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Event created successfully',
        'data', json_build_object(
            'event_id', v_event_id
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
