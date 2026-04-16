# `signup`

```sql
-- Function: signup
-- Group: Auth
-- Endpoint: POST /rpc/signup
-- Doc: docs/api/auth/signup.md

CREATE OR REPLACE FUNCTION signup(
    p_email    text,
    p_password text,
    p_username text,
    p_ip       text DEFAULT '::1'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id   uuid;
    v_is_deleted boolean;
BEGIN

    -- ── Email validation ──────────────────────────────────────────────────────
    IF p_email IS NULL OR trim(p_email) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Email is required');
    END IF;

    -- ── Password validation ───────────────────────────────────────────────────
    IF p_password IS NULL OR trim(p_password) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Password is required');
    END IF;

    -- ── Username validation ───────────────────────────────────────────────────
    IF p_username IS NULL OR trim(p_username) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Username is required');
    END IF;

    IF length(trim(p_username)) < 3 THEN
        RETURN json_build_object('status', false, 'message', 'Username must be at least 3 characters');
    END IF;

    -- ── Email check: active or soft-deleted? ──────────────────────────────────
    SELECT id, is_deleted INTO v_user_id, v_is_deleted
    FROM users
    WHERE lower(email) = lower(trim(p_email))
    LIMIT 1;

    IF FOUND AND v_is_deleted = false THEN
        -- Active account exists — block registration
        RETURN json_build_object('status', false, 'message', 'Email already exists');
    END IF;

    IF FOUND AND v_is_deleted = true THEN
        -- Previously deleted account — reactivate with new credentials
        UPDATE users
        SET    password          = p_password,
               username         = trim(p_username),
               is_deleted       = false,
               deleted_at       = null,
               updated_at       = now(),
               updated_device_ip = p_ip
        WHERE  id               = v_user_id;
    ELSE
        -- Brand new user — insert fresh row
        INSERT INTO users (email, password, username, created_device_ip, updated_device_ip)
        VALUES (trim(p_email), p_password, trim(p_username), p_ip, p_ip)
        RETURNING id INTO v_user_id;
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Registration successful',
        'user_id', v_user_id
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong in signup',
            'error',   SQLERRM
        );
END;
$$;
```
