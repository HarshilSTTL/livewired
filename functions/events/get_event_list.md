# `get_event_list`

```sql
-- Function: get_event_list
-- Group: Events
-- Endpoint: POST /rpc/get_event_list
-- Doc: docs/api/events/get_event_list.md

CREATE OR REPLACE FUNCTION get_event_list(
    p_user_id   uuid DEFAULT null,
    p_date      date DEFAULT CURRENT_DATE,
    p_device_ip text DEFAULT null
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_live  json;
    v_today json;
BEGIN

    -- ── PAST DATE ─────────────────────────────────────────────
    -- Edge case — should never happen from app
    -- live  = empty
    -- today = all events of that day (for reference only)
    IF p_date < CURRENT_DATE THEN

        v_live  := '[]'::json;

        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'username',      cp.username,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id
                    AND   f.is_active  = true
                ),
                'event_title',   e.title,
                'event_date',    e.event_date,
                'time',          e.event_time,
                'livestream',    e.livestream,
                'is_recurring',  e.is_recurring,
                'streaming', (
                    SELECT coalesce(
                        json_agg(
                            json_build_object(
                                'platform_id',   p.plat_id,
                                'platform_name', p.plat_name,
                                'logo_url',      p.logo_url,
                                'streaming_url', ep.stream_url
                            )
                        ),
                        '[]'::json
                    )
                    FROM event_platforms ep
                    LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                    WHERE ep.event_id = e.event_id
                )
            )
            ORDER BY e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_date = p_date
        AND   cp.status    = 'active'
        -- ── Follow filter ──────────────────────────────────────
        AND (
            p_user_id IS NULL
            OR cp.id IN (
                SELECT profile_id FROM follows
                WHERE  user_id    = p_user_id
                AND    is_active  = true
            )
        );

    -- ── TODAY ─────────────────────────────────────────────────
    ELSIF p_date = CURRENT_DATE THEN

        -- LIVE section
        -- Events that are currently streaming right now
        -- livestream = true AND started (event_time <= now)
        -- AND not yet ended (within 3 hours of start time)
        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'username',      cp.username,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id
                    AND   f.is_active  = true
                ),
                'event_title',   e.title,
                'event_date',    e.event_date,
                'time',          e.event_time,
                'livestream',    e.livestream,
                'is_recurring',  e.is_recurring,
                'streaming', (
                    SELECT coalesce(
                        json_agg(
                            json_build_object(
                                'platform_id',   p.plat_id,
                                'platform_name', p.plat_name,
                                'logo_url',      p.logo_url,
                                'streaming_url', ep.stream_url
                            )
                        ),
                        '[]'::json
                    )
                    FROM event_platforms ep
                    LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                    WHERE ep.event_id = e.event_id
                )
            )
            ORDER BY e.event_time ASC
        )
        INTO v_live
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_date = CURRENT_DATE
        AND   e.livestream = true
        AND   cp.status    = 'active'
        -- Started → event_time has passed
        AND   e.event_time <= current_time
        -- Not terminated → within 3 hours of start time
        AND   e.event_time >= (current_time - interval '3 hours')
        -- ── Follow filter ──────────────────────────────────────
        AND (
            p_user_id IS NULL
            OR cp.id IN (
                SELECT profile_id FROM follows
                WHERE  user_id    = p_user_id
                AND    is_active  = true
            )
        );

        -- TODAY section
        -- Upcoming events that have NOT started yet
        -- Excludes terminated events (started more than 3 hours ago)
        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'username',      cp.username,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id
                    AND   f.is_active  = true
                ),
                'event_title',   e.title,
                'event_date',    e.event_date,
                'time',          e.event_time,
                'livestream',    e.livestream,
                'is_recurring',  e.is_recurring,
                'streaming', (
                    SELECT coalesce(
                        json_agg(
                            json_build_object(
                                'platform_id',   p.plat_id,
                                'platform_name', p.plat_name,
                                'logo_url',      p.logo_url,
                                'streaming_url', ep.stream_url
                            )
                        ),
                        '[]'::json
                    )
                    FROM event_platforms ep
                    LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                    WHERE ep.event_id = e.event_id
                )
            )
            ORDER BY e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_date = CURRENT_DATE
        AND   cp.status    = 'active'
        -- Not yet started
        AND   e.event_time > current_time
        -- ── Follow filter ──────────────────────────────────────
        AND (
            p_user_id IS NULL
            OR cp.id IN (
                SELECT profile_id FROM follows
                WHERE  user_id    = p_user_id
                AND    is_active  = true
            )
        );

    -- ── FUTURE DATE ───────────────────────────────────────────
    -- live  = always empty
    -- today = all events scheduled for that day
    ELSIF p_date > CURRENT_DATE THEN

        v_live := '[]'::json;

        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'username',      cp.username,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id
                    AND   f.is_active  = true
                ),
                'event_title',   e.title,
                'event_date',    e.event_date,
                'time',          e.event_time,
                'livestream',    e.livestream,
                'is_recurring',  e.is_recurring,
                'streaming', (
                    SELECT coalesce(
                        json_agg(
                            json_build_object(
                                'platform_id',   p.plat_id,
                                'platform_name', p.plat_name,
                                'logo_url',      p.logo_url,
                                'streaming_url', ep.stream_url
                            )
                        ),
                        '[]'::json
                    )
                    FROM event_platforms ep
                    LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                    WHERE ep.event_id = e.event_id
                )
            )
            ORDER BY e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_date = p_date
        AND   cp.status    = 'active'
        -- ── Follow filter ──────────────────────────────────────
        AND (
            p_user_id IS NULL
            OR cp.id IN (
                SELECT profile_id FROM follows
                WHERE  user_id    = p_user_id
                AND    is_active  = true
            )
        );

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Event list fetched successfully',
        'data', json_build_object(
            'live',  coalesce(v_live,  '[]'::json),
            'today', coalesce(v_today, '[]'::json)
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
```
