# `get_profile_events`

```sql
-- Function: get_profile_events
-- Group:    events
-- Endpoint: POST /rpc/get_profile_events
-- Tables:   event_mst (SELECT), event_platforms (SELECT), platforms (SELECT)
-- Doc:      docs/api/events/get_profile_events.md
--
-- Purpose:  Returns all events for a specific profile for a 7-day window
--           starting from p_week_start. Filtered strictly by p_profile_id.
--
-- Recurring event design:
--   create_event pre-generates child rows in event_mst — one row per occurrence.
--   Each child row has parent_event_id set to the parent template event_id.
--   This SP returns child rows (parent_event_id IS NOT NULL) which already have
--   the correct event_date for their specific occurrence.
--   Parent template rows (parent_event_id IS NULL, is_recurring = true) are excluded.
--
--   event_platforms rows exist only on the parent event.
--   The platforms subquery resolves via COALESCE(parent_event_id, event_id),
--   so both recurring child rows and non-recurring events resolve correctly.
--
-- ⚠️ event_platforms.platform_id is int4 — cast ::bigint when joining platforms.plat_id

CREATE OR REPLACE FUNCTION get_profile_events(
    p_profile_id  uuid,
    p_week_start  date,
    p_timezone    text DEFAULT 'UTC'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_week_end  date;
    v_events    json;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_week_start IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Week start date is required');
    END IF;

    -- ── Existence check ───────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles WHERE id = p_profile_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    -- ── Calculate week end (7 days inclusive) ─────────────────────────────────
    v_week_end := p_week_start + interval '6 days';

    -- ── Fetch events ──────────────────────────────────────────────────────────
    -- Include:
    --   • Non-recurring events  (is_recurring = false, parent_event_id = NULL)
    --   • Recurring occurrences (is_recurring = true,  parent_event_id IS NOT NULL)
    -- Exclude:
    --   • Recurring parent/template rows (is_recurring = true, parent_event_id IS NULL)
    SELECT json_agg(
        json_build_object(
            'event_id',        e.event_id,
            'parent_event_id', e.parent_event_id,
            'title',           e.title,
            'description',     e.description,
            'event_date',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
            'event_time',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
            'event_end_time',  (((e.event_date::text || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
            'livestream',      e.livestream,
            'video',           e.video,
            'is_recurring',    e.is_recurring,
            'platforms', (
                SELECT COALESCE(
                    json_agg(
                        json_build_object(
                            'platform_id',   p.plat_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url,
                            'stream_url',    ep.stream_url
                        )
                        ORDER BY p.plat_name ASC
                    ),
                    '[]'::json
                )
                FROM event_platforms ep
                LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                -- Recurring children have no event_platforms of their own —
                -- resolve to the parent's event_id to inherit its platforms.
                WHERE ep.event_id = COALESCE(e.parent_event_id, e.event_id)
            )
        )
        ORDER BY e.event_date ASC, e.event_time ASC
    )
    INTO v_events
    FROM event_mst e
    WHERE e.profile_id = p_profile_id
      AND (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date
          BETWEEN p_week_start AND v_week_end
      AND e.is_deleted = false
      AND (e.is_recurring = false OR e.parent_event_id IS NOT NULL);

    RETURN json_build_object(
        'status',  true,
        'message', 'Events fetched successfully',
        'data', json_build_object(
            'week_start', p_week_start,
            'week_end',   v_week_end,
            'events',     COALESCE(v_events, '[]'::json)
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
