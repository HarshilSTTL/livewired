# `register`

```sql
-- Function: register
-- Group: Auth
-- Endpoint: POST /rpc/register
-- Doc: docs/api/auth/register.md

CREATE OR REPLACE FUNCTION register(
    p_email              text,
    p_password           text,
    p_username           text,
    p_created_device_ip  text DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id uuid;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_email IS NULL OR trim(p_email) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Email is required');
    END IF;

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

    IF EXISTS (
        SELECT 1 FROM users WHERE lower(username) = lower(trim(p_username))
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Username already taken');
    END IF;

    -- ── Duplicate email check ─────────────────────────────────────────────────
    IF EXISTS (
        SELECT 1 FROM users WHERE email = p_email
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Email already exists');
    END IF;

    -- ── Insert new user ───────────────────────────────────────────────────────
    INSERT INTO users (email, password, username, created_device_ip, updated_device_ip)
    VALUES (p_email, p_password, trim(p_username), p_created_device_ip, p_created_device_ip)
    RETURNING id INTO v_user_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'User registered successfully',
        'data', json_build_object(
            'user_id', v_user_id
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
