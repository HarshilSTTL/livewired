# `get_profile_events`

```sql
-- Function: get_profile_events
-- Group:    events
-- Endpoint: POST /rpc/get_profile_events
-- Tables:   event_mst (SELECT), event_platforms (SELECT), event_recurring (SELECT), platforms (SELECT)
-- Doc:      docs/api/events/get_profile_events.md
--
-- Purpose:  Returns all events for a specific profile for a 7-day window
--           starting from p_week_start. Used for the calendar/event list on
--           the profile view page. Events sorted by date ASC, time ASC.
--
-- Notes:
--   • event_platforms.platform_id is int4 — cast ::bigint when joining platforms.plat_id
--   • p_week_end is calculated as p_week_start + 6 days internally
--   • Recurring events included — is_recurring flag returned so UI can show ↻ icon

CREATE OR REPLACE FUNCTION get_profile_events(
    p_profile_id  uuid,
    p_week_start  date
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_week_end date;
    v_events   json;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_week_start IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Week start date is required');
    END IF;

    -- ── Ownership/existence check ─────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles WHERE id = p_profile_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    -- ── Calculate week end (7 days inclusive) ─────────────────────────────────
    v_week_end := p_week_start + interval '6 days';

    -- ── Fetch events for the week ─────────────────────────────────────────────
    SELECT json_agg(
        json_build_object(
            'event_id',     e.event_id,
            'title',        e.title,
            'description',  e.description,
            'event_date',   e.event_date,
            'event_time',   e.event_time,
            'livestream',   e.livestream,
            'video',        e.video,
            'is_recurring', e.is_recurring,
            'platforms', (
                SELECT coalesce(
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
                WHERE ep.event_id = e.event_id
            )
        )
        ORDER BY e.event_date ASC, e.event_time ASC
    )
    INTO v_events
    FROM event_mst e
    WHERE e.profile_id  = p_profile_id
    AND   e.event_date >= p_week_start
    AND   e.event_date <= v_week_end;

    RETURN json_build_object(
        'status',  true,
        'message', 'Events fetched successfully',
        'data', json_build_object(
            'week_start', p_week_start,
            'week_end',   v_week_end,
            'events',     coalesce(v_events, '[]'::json)
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
