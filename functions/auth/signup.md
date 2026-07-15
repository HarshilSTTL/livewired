# `signup`

> ⚠️ **DEPRECATED — not used.** Auth is handled entirely by Supabase Auth
> (`supabase.auth.signUp()`), which creates the `auth.users` row, hashes the
> password, and sends the verification email natively. This RPC bypasses
> Supabase Auth entirely (raw insert into `public.users`, plain-text password,
> no verification) and is not called from the mobile app or anywhere else.
> Kept only for historical reference — do not wire this up.

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
    v_user_id uuid;
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

    -- ── Duplicate email check (active accounts only) ──────────────────────────
    -- Deleted accounts have their email anonymized in delete_account, so a
    -- lookup by real email will never match a deleted row.
    IF EXISTS (
        SELECT 1 FROM users
        WHERE lower(email) = lower(trim(p_email))
          AND is_deleted   = false
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Email already exists');
    END IF;

    -- ── Insert fresh user ─────────────────────────────────────────────────────
    -- Re-registering after deletion always lands here (email was anonymized on
    -- deletion), so a new UUID is created and no old data is attached.
    INSERT INTO users (email, password, username, created_device_ip, updated_device_ip)
    VALUES (trim(p_email), p_password, trim(p_username), p_ip, p_ip)
    RETURNING id INTO v_user_id;

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
