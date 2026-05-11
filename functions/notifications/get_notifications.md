# `get_notifications`

```sql
-- Function: get_notifications
-- Group: Notifications
-- Endpoint: POST /rpc/get_notifications
-- Doc: docs/api/notifications/get_notifications.md
-- Returns the user's notifications from the past 2 days, latest first.

CREATE OR REPLACE FUNCTION get_notifications(
    p_user_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- ── Null guard ────────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id is required');
    END IF;

    -- ── Return notifications from past 2 days ─────────────────────────────────
    RETURN json_build_object(
        'status',  true,
        'message', 'Notifications fetched successfully',
        'data',    COALESCE(
            (
                SELECT json_agg(row_to_json(n))
                FROM (
                    SELECT
                        n.id,
                        n.title,
                        n.body,
                        n.data,
                        n.is_read,
                        n.created_at,
                        cp.profile_name,
                        cp.avatar
                    FROM notifications n
                    LEFT JOIN creator_profiles cp ON cp.id = (
                        COALESCE(
                            (n.data->>'profile_id'),
                            (n.data->>'invited_by_profile_id'),
                            (n.data->>'responding_profile_id')
                        )
                    )::uuid
                    WHERE n.user_id    = p_user_id
                      AND n.created_at >= NOW() - INTERVAL '2 days'
                    ORDER BY n.created_at DESC
                ) n
            ),
            '[]'::json
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
