# `mark_notifications_read`

```sql
-- Function: mark_notifications_read
-- Group: Notifications
-- Endpoint: POST /rpc/mark_notifications_read
-- Doc: docs/api/notifications/mark_notifications_read.md
--
-- Marks notifications as read for the authenticated user.
-- p_notification_ids = null  → mark ALL unread notifications as read
-- p_notification_ids = [...]  → mark only those specific IDs as read (must belong to this user)

CREATE OR REPLACE FUNCTION mark_notifications_read(
    p_user_id           uuid,
    p_notification_ids  uuid[] DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updated_count int;
BEGIN

    -- ── Null guard ────────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id is required');
    END IF;

    -- ── Mark as read ──────────────────────────────────────────────────────────
    IF p_notification_ids IS NULL THEN

        -- Mark ALL unread notifications for this user as read
        UPDATE notifications
        SET    is_read = true
        WHERE  user_id = p_user_id
          AND  is_read = false;

        GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    ELSE

        -- Mark only the specified notification IDs as read
        -- Security: user_id filter ensures users can only mark their own notifications
        UPDATE notifications
        SET    is_read = true
        WHERE  user_id = p_user_id
          AND  id      = ANY(p_notification_ids)
          AND  is_read = false;

        GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_updated_count || ' notification(s) marked as read'
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
