# `get_event_list`

```sql
-- Function: get_event_list
-- Group: Events
-- Endpoint: POST /rpc/get_event_list
-- Doc: docs/api/events/get_event_list.md

CREATE OR REPLACE FUNCTION get_event_list(
    p_user_id   uuid DEFAULT null,
    p_date      date DEFAULT CURRENT_DATE,
    p_timezone  text DEFAULT 'UTC',
    p_device_ip text DEFAULT null
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_live      json;
    v_today     json;
    v_local_now date;
BEGIN

    -- ── Viewer's current local date ───────────────────────────────────────────
    v_local_now := (NOW() AT TIME ZONE p_timezone)::date;

    -- ── PAST DATE ─────────────────────────────────────────────────────────────
    IF p_date < v_local_now THEN

        v_live := '[]'::json;

        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'username',      cp.username,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id AND f.is_active = true
                ),
                'event_title',   e.title,
                'event_date',    (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date,
                'time',          (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::time,
                'livestream',    e.livestream,
                'is_recurring',  e.is_recurring,
                'platforms', (
                    SELECT coalesce(
                        json_agg(json_build_object(
                            'platform_id',   p.plat_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url,
                            'streaming_url', ep.stream_url
                        )),
                        '[]'::json
                    )
                    FROM event_platforms ep
                    LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                    WHERE ep.event_id = COALESCE(e.parent_event_id, e.event_id)
                )
            )
            ORDER BY e.event_date ASC, e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date = p_date
          AND cp.status    = 'active'
          AND e.is_deleted = false
          AND (
              p_user_id IS NULL
              OR cp.id IN (
                  SELECT profile_id FROM follows
                  WHERE user_id = p_user_id AND is_active = true
              )
          );

    -- ── TODAY ─────────────────────────────────────────────────────────────────
    ELSIF p_date = v_local_now THEN

        -- LIVE section: events that have started (UTC) and within 3 hours of start
        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'username',      cp.username,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id AND f.is_active = true
                ),
                'event_title',   e.title,
                'event_date',    (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date,
                'time',          (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::time,
                'livestream',    e.livestream,
                'is_recurring',  e.is_recurring,
                'platforms', (
                    SELECT coalesce(
                        json_agg(json_build_object(
                            'platform_id',   p.plat_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url,
                            'streaming_url', ep.stream_url
                        )),
                        '[]'::json
                    )
                    FROM event_platforms ep
                    LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                    WHERE ep.event_id = COALESCE(e.parent_event_id, e.event_id)
                )
            )
            ORDER BY e.event_date ASC, e.event_time ASC
        )
        INTO v_live
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date = p_date
          AND e.livestream  = true
          AND cp.status     = 'active'
          AND e.is_deleted  = false
          -- Has started (UTC comparison)
          AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC' <= NOW()
          -- Not terminated — within 3 hours of start
          AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC' >= NOW() - interval '3 hours'
          AND (
              p_user_id IS NULL
              OR cp.id IN (
                  SELECT profile_id FROM follows
                  WHERE user_id = p_user_id AND is_active = true
              )
          );

        -- TODAY section: upcoming events that have NOT started yet
        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'username',      cp.username,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id AND f.is_active = true
                ),
                'event_title',   e.title,
                'event_date',    (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date,
                'time',          (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::time,
                'livestream',    e.livestream,
                'is_recurring',  e.is_recurring,
                'platforms', (
                    SELECT coalesce(
                        json_agg(json_build_object(
                            'platform_id',   p.plat_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url,
                            'streaming_url', ep.stream_url
                        )),
                        '[]'::json
                    )
                    FROM event_platforms ep
                    LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                    WHERE ep.event_id = COALESCE(e.parent_event_id, e.event_id)
                )
            )
            ORDER BY e.event_date ASC, e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date = p_date
          AND cp.status    = 'active'
          AND e.is_deleted = false
          -- Not yet started (UTC comparison)
          AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC' > NOW()
          AND (
              p_user_id IS NULL
              OR cp.id IN (
                  SELECT profile_id FROM follows
                  WHERE user_id = p_user_id AND is_active = true
              )
          );

    -- ── FUTURE DATE ───────────────────────────────────────────────────────────
    ELSIF p_date > v_local_now THEN

        v_live := '[]'::json;

        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'username',      cp.username,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id AND f.is_active = true
                ),
                'event_title',   e.title,
                'event_date',    (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date,
                'time',          (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::time,
                'livestream',    e.livestream,
                'is_recurring',  e.is_recurring,
                'platforms', (
                    SELECT coalesce(
                        json_agg(json_build_object(
                            'platform_id',   p.plat_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url,
                            'streaming_url', ep.stream_url
                        )),
                        '[]'::json
                    )
                    FROM event_platforms ep
                    LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                    WHERE ep.event_id = COALESCE(e.parent_event_id, e.event_id)
                )
            )
            ORDER BY e.event_date ASC, e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date = p_date
          AND cp.status    = 'active'
          AND e.is_deleted = false
          AND (
              p_user_id IS NULL
              OR cp.id IN (
                  SELECT profile_id FROM follows
                  WHERE user_id = p_user_id AND is_active = true
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
