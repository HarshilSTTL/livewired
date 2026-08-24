# `update_push_preference`

```sql
-- Function: update_push_preference
-- Group: Notifications
-- Endpoint: POST /rpc/update_push_preference
-- Doc: docs/api/notifications/update_push_preference.md
-- Tables: users (UPDATE)
--
-- Toggles the account-level push notification preference. Checked by the
-- `push` Edge Function before it sends any FCM message — see
-- supabase/functions/push/index.ts.
--
-- Note: this does NOT touch device_tokens. In-app notifications (the
-- `notifications` table / get_notifications) are unaffected by this flag —
-- only the push delivery is gated.

CREATE OR REPLACE FUNCTION update_push_preference(
    p_user_id        uuid,
    p_push_enabled   boolean
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id is required');
    END IF;

    IF p_push_enabled IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_push_enabled is required');
    END IF;

    -- ── Verify user exists ────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE id = p_user_id AND is_deleted = false
    ) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    -- ── Update preference ─────────────────────────────────────────────────────
    UPDATE users
    SET is_push_enabled = p_push_enabled,
        updated_at      = now()
    WHERE id = p_user_id;

    -- ── Success ───────────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status',  true,
        'message', 'Push preference updated successfully',
        'data', json_build_object(
            'user_id',         p_user_id,
            'is_push_enabled', p_push_enabled
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
