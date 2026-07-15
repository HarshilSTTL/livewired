# `login`

> ⚠️ **DEPRECATED — not used.** Auth is handled entirely by Supabase Auth
> (`supabase.auth.signInWithPassword()`). This RPC compares plain-text
> passwords against `public.users.password` — a column Supabase Auth doesn't
> populate or maintain — and is not called from the mobile app or anywhere
> else. Kept only for historical reference — do not wire this up.

```sql
-- Function: login
-- Group: Auth
-- Endpoint: POST /rpc/login
-- Doc: docs/api/auth/login.md

CREATE OR REPLACE FUNCTION login(
    p_email    text,
    p_password text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user record;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_email IS NULL OR trim(p_email) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Email is required');
    END IF;

    IF p_password IS NULL OR trim(p_password) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Password is required');
    END IF;

    -- ── Fetch user ────────────────────────────────────────────────────────────
    SELECT id, email, password, username
    INTO v_user
    FROM users
    WHERE email      = p_email
      AND is_deleted = false
    LIMIT 1;

    -- ── User not found ────────────────────────────────────────────────────────
    IF v_user IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Invalid email or password');
    END IF;

    -- ── Password mismatch ─────────────────────────────────────────────────────
    IF v_user.password <> p_password THEN
        RETURN json_build_object('status', false, 'message', 'Invalid email or password');
    END IF;

    -- ── Success ───────────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status',  true,
        'message', 'Login successful',
        'data', json_build_object(
            'user_id',  v_user.id,
            'email',    v_user.email,
            'username', v_user.username
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
