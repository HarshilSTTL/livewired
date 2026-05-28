# `get_unread_notification_count`

```sql
-- Function: get_unread_notification_count (V2 - Current)
-- Group: Notifications
-- Endpoint: POST /rpc/get_unread_notification_count
-- Doc: docs/api/notifications/get_unread_notification_count.md
-- Version: 2.0 (2026-05-28)
-- Changes: Synced with get_notifications_v2 for consistency (no 2-day limit)
-- Returns the count of unread notifications for the authenticated user.

CREATE OR REPLACE FUNCTION get_unread_notification_count(
    p_user_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count bigint;
BEGIN

    -- ── Null guard ────────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id is required');
    END IF;

    -- ── Count unread ──────────────────────────────────────────────────────────
    SELECT COUNT(*)
    INTO v_count
    FROM notifications
    WHERE user_id    = p_user_id
      AND is_read    = false
      AND is_cleared = false;

    RETURN json_build_object(
        'status',  true,
        'message', 'Unread notification count fetched successfully',
        'data',    json_build_object('unread_count', v_count)
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
