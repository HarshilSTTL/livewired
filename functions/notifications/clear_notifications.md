# `clear_notifications`

```sql
-- Function: clear_notifications
-- Group: Notifications
-- Endpoint: POST /rpc/clear_notifications
-- Doc: docs/api/notifications/clear_notifications.md
--
-- Clears (hides) notifications for the authenticated user.
-- p_notification_ids = null  → clear ALL notifications (not yet cleared)
-- p_notification_ids = [...]  → clear only those specific IDs (must belong to this user)

CREATE OR REPLACE FUNCTION clear_notifications(
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

    -- ── Clear notifications ───────────────────────────────────────────────────
    IF p_notification_ids IS NULL THEN

        -- Clear ALL notifications for this user that are not yet cleared
        UPDATE notifications
        SET    is_cleared = true
        WHERE  user_id = p_user_id
          AND  is_cleared = false;

        GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    ELSE

        -- Clear only the specified notification IDs
        -- Security: user_id filter ensures users can only clear their own notifications
        UPDATE notifications
        SET    is_cleared = true
        WHERE  user_id = p_user_id
          AND  id      = ANY(p_notification_ids)
          AND  is_cleared = false;

        GET DIAGNOSTICS v_updated_count = ROW_COUNT;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_updated_count || ' notification(s) cleared'
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
