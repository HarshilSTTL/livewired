# `get_event_dates`

```sql
-- Function: get_event_dates
-- Group: Events
-- Endpoint: POST /rpc/get_event_dates
-- Doc: docs/api/events/get_event_dates.md

CREATE OR REPLACE FUNCTION get_event_dates(
    p_user_id  uuid,
    p_year     int,
    p_month    int,
    p_timezone text DEFAULT 'UTC'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF p_year IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Year is required');
    END IF;

    IF p_month IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Month is required');
    END IF;

    IF p_month < 1 OR p_month > 12 THEN
        RETURN json_build_object('status', false, 'message', 'Month must be between 1 and 12');
    END IF;

    -- ── Fetch event dates ─────────────────────────────────────────────────────
    SELECT COALESCE(
        json_agg(
            json_build_object(
                'date',  row_data.event_date,
                'count', row_data.event_count
            )
            ORDER BY row_data.event_date
        ),
        '[]'::json
    )
    INTO v_result
    FROM (
        SELECT
            (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date::text AS event_date,
            COUNT(*)::int AS event_count
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        JOIN follows f           ON f.profile_id = cp.id
        WHERE f.user_id    = p_user_id
          AND f.is_active  = true
          AND e.is_deleted = false
          AND EXTRACT(YEAR  FROM (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date) = p_year
          AND EXTRACT(MONTH FROM (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date) = p_month
        GROUP BY (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE 'UTC') AT TIME ZONE p_timezone)::date
    ) row_data;

    -- ── Success ───────────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status',  true,
        'message', 'Event dates fetched successfully',
        'data',    v_result
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
