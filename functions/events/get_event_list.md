# `get_event_list`

```sql
-- Function: get_event_list
-- Group: Events
-- Endpoint: POST /rpc/get_event_list
-- Doc: docs/api/events/get_event_list.md
--
-- Timezone design:
--   event_date + event_time are stored in the creator's local timezone (event_timezone column).
--   All output dates/times are converted to the viewer's timezone via p_timezone.
--   Conversion: (stored_local AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone
--
-- Cross-midnight end_time:
--   When event_end_time < event_time, the event runs past midnight.
--   End timestamp uses (event_date + 1) as the date for the end_time calculation.
--
-- Live vs Today:
--   LIVE  — event has end_time AND has started AND has not yet ended.
--   TODAY — all other events (no end_time, not yet started, or already ended).

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
                'profile_id',    cp.id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id AND f.is_active = true
                ),
                'event_title',   e.title,
                'event_date',    (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
                'time',          (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
                'end_time',      (((CASE WHEN e.event_end_time IS NOT NULL AND e.event_end_time < e.event_time
                                        THEN (e.event_date + 1)::text
                                        ELSE e.event_date::text
                                   END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
                'livestream',    e.livestream,
                'is_collaborative', e.is_collaborative,
                'is_recurring',  e.is_recurring,
                'collaborators', (
                    SELECT json_agg(
                        json_build_object(
                            'profile_id',   ec.profile_id,
                            'profile_name', cp_collab.profile_name,
                            'avatar',       cp_collab.avatar,
                            'status',       ec.status
                        ) ORDER BY ec.invited_at
                    )
                    FROM event_collaborators ec
                    JOIN creator_profiles cp_collab ON cp_collab.id = ec.profile_id
                    WHERE ec.event_id = COALESCE(e.parent_event_id, e.event_id)
                      AND ec.is_deleted = false
                ),
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
                    WHERE ep.event_id = CASE
                        WHEN e.is_overridden
                        THEN e.event_id
                        ELSE COALESCE(e.parent_event_id, e.event_id)
                    END
                )
            )
            ORDER BY e.event_date ASC, e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date = p_date
          AND cp.status    = 'active'
          AND e.is_deleted = false
          AND (e.is_recurring = false OR e.parent_event_id IS NOT NULL)
          AND (
              p_user_id IS NULL
              OR cp.id IN (
                  SELECT profile_id FROM follows
                  WHERE user_id = p_user_id AND is_active = true
              )
              -- Also show events where the user is an accepted collaborator
              OR COALESCE(e.parent_event_id, e.event_id) IN (
                  SELECT ec.event_id
                  FROM event_collaborators ec
                  JOIN creator_profiles cp2 ON cp2.id = ec.profile_id
                  WHERE cp2.user_id  = p_user_id
                    AND ec.status    = 'accepted'
                    AND ec.is_deleted = false
              )
          );

    -- ── TODAY ─────────────────────────────────────────────────────────────────
    ELSIF p_date = v_local_now THEN

        -- LIVE section: events that have an end_time, have started, and haven't ended yet
        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_id',    cp.id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id AND f.is_active = true
                ),
                'event_title',   e.title,
                'event_date',    (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
                'time',          (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
                'end_time',      (((CASE WHEN e.event_end_time IS NOT NULL AND e.event_end_time < e.event_time
                                        THEN (e.event_date + 1)::text
                                        ELSE e.event_date::text
                                   END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
                'livestream',    e.livestream,
                'is_collaborative', e.is_collaborative,
                'is_recurring',  e.is_recurring,
                'collaborators', (
                    SELECT json_agg(
                        json_build_object(
                            'profile_id',   ec.profile_id,
                            'profile_name', cp_collab.profile_name,
                            'avatar',       cp_collab.avatar,
                            'status',       ec.status
                        ) ORDER BY ec.invited_at
                    )
                    FROM event_collaborators ec
                    JOIN creator_profiles cp_collab ON cp_collab.id = ec.profile_id
                    WHERE ec.event_id = COALESCE(e.parent_event_id, e.event_id)
                      AND ec.is_deleted = false
                ),
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
                    WHERE ep.event_id = CASE
                        WHEN e.is_overridden
                        THEN e.event_id
                        ELSE COALESCE(e.parent_event_id, e.event_id)
                    END
                )
            )
            ORDER BY e.event_date ASC, e.event_time ASC
        )
        INTO v_live
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date = p_date
          AND cp.status     = 'active'
          AND e.is_deleted  = false
          AND (e.is_recurring = false OR e.parent_event_id IS NOT NULL)
          -- Must have an end time
          AND e.event_end_time IS NOT NULL
          -- Has started
          AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone <= NOW()
          -- Has not yet ended (cross-midnight: if end_time < start_time, use next day's date)
          AND (CASE WHEN e.event_end_time < e.event_time
                    THEN (e.event_date + 1)::text
                    ELSE e.event_date::text
               END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone >= NOW()
          AND (
              p_user_id IS NULL
              OR cp.id IN (
                  SELECT profile_id FROM follows
                  WHERE user_id = p_user_id AND is_active = true
              )
              -- Also show events where the user is an accepted collaborator
              OR COALESCE(e.parent_event_id, e.event_id) IN (
                  SELECT ec.event_id
                  FROM event_collaborators ec
                  JOIN creator_profiles cp2 ON cp2.id = ec.profile_id
                  WHERE cp2.user_id  = p_user_id
                    AND ec.status    = 'accepted'
                    AND ec.is_deleted = false
              )
          );

        -- TODAY section: events that are upcoming OR have started but have no end_time
        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_id',    cp.id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id AND f.is_active = true
                ),
                'event_title',   e.title,
                'event_date',    (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
                'time',          (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
                'end_time',      (((CASE WHEN e.event_end_time IS NOT NULL AND e.event_end_time < e.event_time
                                        THEN (e.event_date + 1)::text
                                        ELSE e.event_date::text
                                   END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
                'livestream',    e.livestream,
                'is_collaborative', e.is_collaborative,
                'is_recurring',  e.is_recurring,
                'collaborators', (
                    SELECT json_agg(
                        json_build_object(
                            'profile_id',   ec.profile_id,
                            'profile_name', cp_collab.profile_name,
                            'avatar',       cp_collab.avatar,
                            'status',       ec.status
                        ) ORDER BY ec.invited_at
                    )
                    FROM event_collaborators ec
                    JOIN creator_profiles cp_collab ON cp_collab.id = ec.profile_id
                    WHERE ec.event_id = COALESCE(e.parent_event_id, e.event_id)
                      AND ec.is_deleted = false
                ),
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
                    WHERE ep.event_id = CASE
                        WHEN e.is_overridden
                        THEN e.event_id
                        ELSE COALESCE(e.parent_event_id, e.event_id)
                    END
                )
            )
            ORDER BY e.event_date ASC, e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date = p_date
          AND cp.status    = 'active'
          AND e.is_deleted = false
          AND (e.is_recurring = false OR e.parent_event_id IS NOT NULL)
          -- Not yet started, OR started but no end_time (unknown duration)
          AND (
              -- upcoming
              (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone > NOW()
              -- started, but no end_time provided (can't determine end)
              OR (
                  (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone <= NOW()
                  AND e.event_end_time IS NULL
              )
          )
          -- Exclude events that are currently Live (avoid duplicates)
          AND NOT (
              e.event_end_time IS NOT NULL
              AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone <= NOW()
              AND (CASE WHEN e.event_end_time < e.event_time
                        THEN (e.event_date + 1)::text
                        ELSE e.event_date::text
                   END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone >= NOW()
          )
          AND (
              p_user_id IS NULL
              OR cp.id IN (
                  SELECT profile_id FROM follows
                  WHERE user_id = p_user_id AND is_active = true
              )
              -- Also show events where the user is an accepted collaborator
              OR COALESCE(e.parent_event_id, e.event_id) IN (
                  SELECT ec.event_id
                  FROM event_collaborators ec
                  JOIN creator_profiles cp2 ON cp2.id = ec.profile_id
                  WHERE cp2.user_id  = p_user_id
                    AND ec.status    = 'accepted'
                    AND ec.is_deleted = false
              )
          );

    -- ── FUTURE DATE ───────────────────────────────────────────────────────────
    ELSIF p_date > v_local_now THEN

        v_live := '[]'::json;

        SELECT json_agg(
            json_build_object(
                'event_id',      e.event_id,
                'profile_id',    cp.id,
                'profile_name',  cp.profile_name,
                'profile_pic',   cp.avatar,
                'followers',     (
                    SELECT count(*) FROM follows f
                    WHERE f.profile_id = cp.id AND f.is_active = true
                ),
                'event_title',   e.title,
                'event_date',    (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
                'time',          (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
                'end_time',      (((CASE WHEN e.event_end_time IS NOT NULL AND e.event_end_time < e.event_time
                                        THEN (e.event_date + 1)::text
                                        ELSE e.event_date::text
                                   END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
                'livestream',    e.livestream,
                'is_collaborative', e.is_collaborative,
                'is_recurring',  e.is_recurring,
                'collaborators', (
                    SELECT json_agg(
                        json_build_object(
                            'profile_id',   ec.profile_id,
                            'profile_name', cp_collab.profile_name,
                            'avatar',       cp_collab.avatar,
                            'status',       ec.status
                        ) ORDER BY ec.invited_at
                    )
                    FROM event_collaborators ec
                    JOIN creator_profiles cp_collab ON cp_collab.id = ec.profile_id
                    WHERE ec.event_id = COALESCE(e.parent_event_id, e.event_id)
                      AND ec.is_deleted = false
                ),
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
                    WHERE ep.event_id = CASE
                        WHEN e.is_overridden
                        THEN e.event_id
                        ELSE COALESCE(e.parent_event_id, e.event_id)
                    END
                )
            )
            ORDER BY e.event_date ASC, e.event_time ASC
        )
        INTO v_today
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date = p_date
          AND cp.status    = 'active'
          AND e.is_deleted = false
          AND (e.is_recurring = false OR e.parent_event_id IS NOT NULL)
          AND (
              p_user_id IS NULL
              OR cp.id IN (
                  SELECT profile_id FROM follows
                  WHERE user_id = p_user_id AND is_active = true
              )
              -- Also show events where the user is an accepted collaborator
              OR COALESCE(e.parent_event_id, e.event_id) IN (
                  SELECT ec.event_id
                  FROM event_collaborators ec
                  JOIN creator_profiles cp2 ON cp2.id = ec.profile_id
                  WHERE cp2.user_id  = p_user_id
                    AND ec.status    = 'accepted'
                    AND ec.is_deleted = false
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
