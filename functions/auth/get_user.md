# `get_user` (v1 & v2)

## Version History

### v2 (Current — 2026-08-24)
- **Change:** Adds `is_push_enabled` to the response
- **Reason:** Needed by the Settings screen to render the push-notification toggle, and by clients calling `update_push_preference`
- **Endpoint:** `POST /rpc/get_user_v2`

### v1 (Deprecated)
- Returns `user_id`, `username`, `email`, `is_email_verified`, `onboarding_completed` — no push fields
- **Endpoint:** `POST /rpc/get_user`

---

## V2 Function (Current)

```sql
-- Function: get_user_v2
-- Group: Auth
-- Endpoint: POST /rpc/get_user_v2
-- Doc: docs/api/auth/get_user.md
-- Version: 2.0 (2026-08-24)
-- Changes: Adds is_push_enabled to the response

CREATE OR REPLACE FUNCTION get_user_v2(
    p_user_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user record;
BEGIN

    -- ── Null guard ────────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    -- ── Fetch user ────────────────────────────────────────────────────────────
    SELECT id, email, username, is_email_verified, onboarding_completed, is_push_enabled
    INTO v_user
    FROM users
    WHERE id         = p_user_id
      AND is_deleted = false
    LIMIT 1;

    -- ── Not found ─────────────────────────────────────────────────────────────
    IF v_user IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    -- ── Success ───────────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status',  true,
        'message', 'User fetched successfully',
        'data', json_build_object(
            'user_id',              v_user.id,
            'username',             v_user.username,
            'email',                v_user.email,
            'is_email_verified',    v_user.is_email_verified,
            'onboarding_completed', v_user.onboarding_completed,
            'is_push_enabled',      v_user.is_push_enabled
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

---

## V1 Function (Deprecated)

```sql
-- Function: get_user (V1 - Deprecated)
-- Group: Auth
-- Endpoint: POST /rpc/get_user
-- Doc: docs/api/auth/get_user.md
-- Use get_user_v2 for is_push_enabled

CREATE OR REPLACE FUNCTION get_user(
    p_user_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user record;
BEGIN

    -- ── Null guard ────────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    -- ── Fetch user ────────────────────────────────────────────────────────────
    SELECT id, email, username, is_email_verified, onboarding_completed
    INTO v_user
    FROM users
    WHERE id         = p_user_id
      AND is_deleted = false
    LIMIT 1;

    -- ── Not found ─────────────────────────────────────────────────────────────
    IF v_user IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    -- ── Success ───────────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status',  true,
        'message', 'User fetched successfully',
        'data', json_build_object(
            'user_id',              v_user.id,
            'username',             v_user.username,
            'email',                v_user.email,
            'is_email_verified',    v_user.is_email_verified,
            'onboarding_completed', v_user.onboarding_completed
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
