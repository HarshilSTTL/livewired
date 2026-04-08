# `update_event`

```sql
-- Function: update_event
-- Group: Events
-- Endpoint: POST /rpc/update_event
-- Doc: docs/api/events/update_event.md
-- COALESCE pattern — only fields that are passed (non-null) are updated.
-- p_platforms: null = don't touch | [] = clear all | [...] = replace all

CREATE OR REPLACE FUNCTION update_event(
    p_event_id    uuid,
    p_user_id     uuid,
    p_title       text    DEFAULT NULL,
    p_description text    DEFAULT NULL,
    p_event_date  date    DEFAULT NULL,
    p_event_time  time    DEFAULT NULL,
    p_timezone    text    DEFAULT NULL,
    p_livestream  boolean DEFAULT NULL,
    p_video       boolean DEFAULT NULL,
    p_platforms   jsonb   DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_platform     jsonb;
    v_current_date date;
    v_current_time time;
    v_event_utc    timestamptz;
    v_utc_date     date;
    v_utc_time     time;
BEGIN

    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- Ownership check: event must belong to a profile owned by p_user_id
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- Validate platforms if provided and non-empty
    IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
            WHERE NOT EXISTS (
                SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint
            )
        ) THEN
            RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
        END IF;

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
            WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
        ) THEN
            RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
        END IF;
    END IF;

    -- ── Timezone conversion for date/time update ─────────────────────────────
    -- If either date or time is being updated and timezone is provided, convert to UTC
    IF (p_event_date IS NOT NULL OR p_event_time IS NOT NULL) AND p_timezone IS NOT NULL THEN
        SELECT event_date, event_time INTO v_current_date, v_current_time
        FROM event_mst WHERE event_id = p_event_id;

        v_event_utc := (
            COALESCE(p_event_date, v_current_date)::text || ' ' ||
            COALESCE(p_event_time, v_current_time)::text
        )::timestamp AT TIME ZONE p_timezone;

        v_utc_date := v_event_utc::date;
        v_utc_time := v_event_utc::time;
    ELSE
        v_utc_date := p_event_date;
        v_utc_time := p_event_time;
    END IF;

    -- Update event_mst — COALESCE keeps existing values for null params
    UPDATE event_mst
    SET title          = COALESCE(p_title,       title),
        description    = COALESCE(p_description, description),
        event_date     = COALESCE(v_utc_date,    event_date),
        event_time     = COALESCE(v_utc_time,    event_time),
        event_timezone = COALESCE(p_timezone,    event_timezone),
        livestream     = COALESCE(p_livestream,  livestream),
        video          = COALESCE(p_video,       video),
        updated_at     = now()
    WHERE event_id     = p_event_id;

    -- Replace platforms only if p_platforms was explicitly passed
    IF p_platforms IS NOT NULL THEN
        DELETE FROM event_platforms WHERE event_id = p_event_id;

        IF jsonb_array_length(p_platforms) > 0 THEN
            FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
            LOOP
                INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                VALUES (
                    gen_random_uuid(),
                    p_event_id,
                    (v_platform->>'platform_id')::int4,
                    v_platform->>'stream_url',
                    now()
                );
            END LOOP;
        END IF;
    END IF;

    RETURN json_build_object('status', true, 'message', 'Event updated successfully');

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```
