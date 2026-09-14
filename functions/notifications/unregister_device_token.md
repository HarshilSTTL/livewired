# `unregister_device_token`

```sql
-- Function: unregister_device_token
-- Group: Notifications
-- Endpoint: POST /rpc/unregister_device_token
-- Doc: docs/api/notifications/unregister_device_token.md
-- Tables: device_tokens (UPDATE)
--
-- Call this at logout, before clearing the local session, using the same
-- FCM token that was passed to register_device_token. Soft-deletes the
-- token (is_active = false) so this device stops receiving push for this
-- account until it's registered again (e.g. on next login).

CREATE OR REPLACE FUNCTION unregister_device_token(
    p_user_id uuid,
    p_token   text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    IF p_user_id IS NULL OR p_token IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_token are required');
    END IF;

    UPDATE device_tokens
    SET is_active = false
    WHERE user_id   = p_user_id
      AND fcm_token = p_token;

    RETURN json_build_object('status', true, 'message', 'Token unregistered');

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```
