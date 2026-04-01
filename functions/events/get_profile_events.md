# `get_profile_events`

```sql
-- Function: get_profile_events
-- Group:    events
-- Endpoint: POST /rpc/get_profile_events
-- Tables:   event_mst (SELECT), event_recurring (SELECT), event_platforms (SELECT), platforms (SELECT)
-- Doc:      docs/api/events/get_profile_events.md
--
-- Purpose:  Returns all events for a specific profile for a 7-day window
--           starting from p_week_start. Used for the calendar/event list on
--           the profile view page. Events sorted by date ASC, time ASC.
--
-- Notes:
--   • Non-recurring events: returned if their exact event_date falls in the window.
--   • Recurring events: expanded dynamically from event_recurring rules —
--     a recurring event appears on every matching occurrence within the window.
--   • event_date returned for recurring events = the actual occurrence date
--     (not the original stored event_date in event_mst).
--   • event_platforms.platform_id is int4 — cast ::bigint when joining platforms.plat_id
--   • p_week_end is calculated as p_week_start + 6 days internally
--
-- Recurring expansion rules:
--   weekly : TO_CHAR(day,'Dy') = ANY(recurring_days)
--            AND (day - first_occurrence_of_day_on_or_after_start) % (7 * interval) = 0
--   first  : day is the first occurrence of that weekday in its calendar month
--            (i.e. day - 7 < first_day_of_month)
--   last   : day is the last occurrence of that weekday in its calendar month
--            (i.e. day + 7 > last_day_of_month)

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

    -- ── Fetch events: non-recurring (exact date) + recurring (expanded) ───────
    WITH

    -- All 7 days in the requested window
    week_days AS (
        SELECT d::date AS day
        FROM generate_series(p_week_start, v_week_end, '1 day'::interval) AS d
    ),

    -- Non-recurring: return as-is — event_date must fall exactly in the window
    non_recurring AS (
        SELECT
            e.event_id,
            e.title,
            e.description,
            e.event_date    AS occurrence_date,
            e.event_time,
            e.livestream,
            e.video,
            e.is_recurring
        FROM event_mst e
        WHERE e.profile_id  = p_profile_id
          AND e.is_recurring = false
          AND e.event_date  BETWEEN p_week_start AND v_week_end
    ),

    -- Recurring: expand each rule into matching days within the window
    recurring_expanded AS (
        SELECT
            e.event_id,
            e.title,
            e.description,
            wd.day          AS occurrence_date,
            e.event_time,
            e.livestream,
            e.video,
            e.is_recurring
        FROM week_days wd
        CROSS JOIN event_mst e
        JOIN event_recurring er ON er.event_id = e.event_id
        WHERE e.profile_id  = p_profile_id
          AND e.is_recurring = true
          -- Day must be within the active recurrence window
          AND wd.day >= er.recurring_start_date
          AND (er.recurring_end_date IS NULL OR wd.day <= er.recurring_end_date)
          -- Day-of-week must be in the recurring_days list (e.g. 'Mon', 'Tue')
          AND TO_CHAR(wd.day, 'Dy') = ANY(er.recurring_days)
          -- Interval / type logic
          AND (
              -- ── weekly ──────────────────────────────────────────────────────
              -- Find the first occurrence of this weekday on or after recurring_start_date,
              -- then check that (day - first_occurrence) is a multiple of (7 * interval).
              (er.recurring_type = 'weekly' AND (
                  -- first_occurrence = recurring_start_date + days_to_reach_this_weekday
                  wd.day >= (er.recurring_start_date
                      + ((7 + EXTRACT(DOW FROM wd.day)::int
                            - EXTRACT(DOW FROM er.recurring_start_date)::int) % 7))
                  AND
                  (wd.day - (er.recurring_start_date
                      + ((7 + EXTRACT(DOW FROM wd.day)::int
                            - EXTRACT(DOW FROM er.recurring_start_date)::int) % 7))
                  ) % (7 * er.recurring_interval) = 0
              ))

              OR

              -- ── first ───────────────────────────────────────────────────────
              -- True when this is the FIRST occurrence of the weekday in its month.
              -- Subtract 7 days — if that lands before the 1st of the month, no
              -- earlier same-weekday exists this month.
              (er.recurring_type = 'first' AND
               (wd.day - 7) < DATE_TRUNC('month', wd.day)::date)

              OR

              -- ── last ────────────────────────────────────────────────────────
              -- True when this is the LAST occurrence of the weekday in its month.
              -- Add 7 days — if that lands after the last day of the month, no
              -- later same-weekday exists this month.
              (er.recurring_type = 'last' AND
               (wd.day + 7) > ((DATE_TRUNC('month', wd.day) + INTERVAL '1 month')::date - 1))
          )
    ),

    -- Union both sets
    all_events AS (
        SELECT * FROM non_recurring
        UNION ALL
        SELECT * FROM recurring_expanded
    )

    SELECT json_agg(
        json_build_object(
            'event_id',     ae.event_id,
            'title',        ae.title,
            'description',  ae.description,
            'event_date',   ae.occurrence_date,
            'event_time',   ae.event_time,
            'livestream',   ae.livestream,
            'video',        ae.video,
            'is_recurring', ae.is_recurring,
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
                WHERE ep.event_id = ae.event_id
            )
        )
        ORDER BY ae.occurrence_date ASC, ae.event_time ASC
    )
    INTO v_events
    FROM all_events ae;

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
