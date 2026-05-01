# `get_event_by_id`

```sql
-- Function: get_event_by_id
-- Group: Events
-- Endpoint: POST /rpc/get_event_by_id
-- Doc: docs/api/events/get_event_by_id.md

CREATE OR REPLACE FUNCTION get_event_by_id(
    p_event_id uuid,
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

    IF p_event_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id is required');
    END IF;

    SELECT json_build_object(
        'event_id',        e.event_id,
        'profile_id',      e.profile_id,
        'parent_event_id', e.parent_event_id,
        'title',           e.title,
        'description',     e.description,
        'event_date',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
        'event_time',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_end_time',  (((e.event_date::text || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_timezone',  e.event_timezone,
        'livestream',      e.livestream,
        'video',           e.video,
        'is_recurring',    e.is_recurring,
        'created_at',      e.created_at,
        'creator', json_build_object(
            'profile_id',   cp.id,
            'profile_name', cp.profile_name,
            'avatar',       cp.avatar
        ),
        'platforms', (
            SELECT COALESCE(
                json_agg(json_build_object(
                    'platform_id',   p.plat_id,
                    'platform_name', p.plat_name,
                    'logo_url',      p.logo_url,
                    'stream_url',    ep.stream_url
                )),
                '[]'::json
            )
            FROM event_platforms ep
            JOIN platforms p ON p.plat_id = ep.platform_id::bigint
            -- Child events inherit platforms from parent
            WHERE ep.event_id = COALESCE(e.parent_event_id, e.event_id)
        ),
        'recurring', (
            SELECT json_build_object(
                'recurring_type',       er.recurring_type,
                'recurring_days',       er.recurring_days,
                'recurring_interval',   er.recurring_interval,
                'recurring_start_date', er.recurring_start_date,
                'recurring_end_date',   er.recurring_end_date
            )
            FROM event_recurring er
            WHERE er.event_id = COALESCE(e.parent_event_id, e.event_id)
        )
    )
    INTO v_result
    FROM event_mst e
    JOIN creator_profiles cp ON cp.id = e.profile_id
    WHERE e.event_id   = p_event_id
      AND e.is_deleted = false;

    IF v_result IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event not found');
    END IF;

    RETURN json_build_object('status', true, 'data', v_result);

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
