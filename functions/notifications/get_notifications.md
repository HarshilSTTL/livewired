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
                        id,
                        title,
                        body,
                        data,
                        is_read,
                        created_at
                    FROM notifications
                    WHERE user_id    = p_user_id
                      AND created_at >= NOW() - INTERVAL '2 days'
                    ORDER BY created_at DESC
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
