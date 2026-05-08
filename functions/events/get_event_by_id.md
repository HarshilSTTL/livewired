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
        'event_end_time',  (((CASE WHEN e.event_end_time IS NOT NULL AND e.event_end_time < e.event_time
                                   THEN (e.event_date + 1)::text
                                   ELSE e.event_date::text
                              END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_timezone',  e.event_timezone,
        'livestream',      e.livestream,
        'video',           e.video,
        'is_collaborative', e.is_collaborative,
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
            -- If this child has its own event_platforms rows (set via 'this' scope update),
            -- use them. Otherwise fall back to the parent's platforms.
            WHERE ep.event_id = CASE
                WHEN EXISTS (SELECT 1 FROM event_platforms ep2 WHERE ep2.event_id = e.event_id)
                THEN e.event_id
                ELSE COALESCE(e.parent_event_id, e.event_id)
            END
        ),
        'collaborators', (
            SELECT COALESCE(
                json_agg(json_build_object(
                    'profile_id',   cp2.id,
                    'profile_name', cp2.profile_name,
                    'avatar',       cp2.avatar,
                    'status',       ec.status,
                    'invited_at',   ec.invited_at,
                    'responded_at', ec.responded_at
                )),
                '[]'::json
            )
            FROM event_collaborators ec
            JOIN creator_profiles cp2 ON cp2.id = ec.profile_id
            WHERE ec.event_id  = COALESCE(e.parent_event_id, e.event_id)
              AND ec.is_deleted = false
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
