# `register_device_token`

> **Already live in production, undocumented until now.** The version below is
> the existing function (`p_token`, not `p_fcm_token` — kept as-is to avoid
> breaking existing callers) with two additions: a user-existence check, and
> reassigning a token to the new owner if the same physical device logs into
> a different account. Confirmed live signature: `register_device_token(p_user_id uuid, p_token text, p_platform text DEFAULT 'android'::text)`.

```sql
-- Function: register_device_token
-- Group: Notifications
-- Endpoint: POST /rpc/register_device_token
-- Doc: docs/api/notifications/register_device_token.md
-- Tables: device_tokens (INSERT/UPDATE)
--
-- Call this after the app obtains an FCM token — on first launch (once OS push
-- permission is granted) and again whenever Firebase rotates the token
-- (onTokenRefresh). Upserts on (user_id, fcm_token) so repeat calls with the
-- same token (e.g. every app start) don't create duplicate rows.
--
-- Requires: UNIQUE (user_id, fcm_token) on device_tokens — already present in
-- production as device_tokens_user_id_fcm_token_key. Also requires the
-- is_active column added in schema/tables/20_device_tokens.md.

CREATE OR REPLACE FUNCTION register_device_token(
    p_user_id  uuid,
    p_token    text,
    p_platform text DEFAULT 'android'::text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_user_id IS NULL OR p_token IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_token are required');
    END IF;

    -- ── Verify user exists ────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE id = p_user_id AND is_deleted = false
    ) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    -- ── Upsert token ──────────────────────────────────────────────────────────
    -- is_active reset to true on conflict in case this token was previously
    -- soft-deleted (e.g. re-registering after being marked dead, or moving back
    -- to this user after a brief switch).
    INSERT INTO device_tokens (user_id, fcm_token, platform, is_active)
    VALUES (p_user_id, p_token, p_platform, true)
    ON CONFLICT (user_id, fcm_token)
    DO UPDATE SET platform = EXCLUDED.platform, is_active = true;

    -- ── Soft-delete this token under any other user ──────────────────────────
    -- A device that logs into a different account must move its token to the
    -- new user — otherwise the previous account keeps receiving push on it.
    UPDATE device_tokens
    SET is_active = false
    WHERE fcm_token = p_token
      AND user_id  <> p_user_id;

    -- ── Success ───────────────────────────────────────────────────────────────
    RETURN json_build_object('status', true, 'message', 'Token registered');

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```
