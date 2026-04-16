# `google_auth`

```sql
-- Function: google_auth
-- Group:    auth
-- Endpoint: POST /rpc/google_auth
-- Tables:   users (SELECT + INSERT)
-- Doc:      docs/api/auth/google_auth.md
--
-- Purpose:  Handles both Google signup and Google login in a single call.
--           Called from Flutter AFTER Supabase OAuth succeeds and the
--           email is confirmed.
--
-- Logic:
--   • If a user with this email already exists → return their user_id  (login)
--   • If no user with this email exists        → insert new row         (signup)
--     password = NULL  (Google users have no password)
--     auth_provider = 'google'
--     username = p_username if provided, NULL otherwise (can be set later)
--
-- Note: If the email exists with auth_provider = 'email' (registered via
--       email/password), the same account is returned — no duplicate created.

CREATE OR REPLACE FUNCTION google_auth(
    p_email    text,
    p_username text DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id uuid;
BEGIN

    -- ── Null / empty guard ────────────────────────────────────────────────────
    IF p_email IS NULL OR trim(p_email) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Email is required');
    END IF;

    -- ── Check if active user already exists ───────────────────────────────────
    -- Deleted accounts have their email anonymized in delete_account, so a
    -- lookup by real email will never match a deleted row.
    SELECT id INTO v_user_id
    FROM users
    WHERE lower(email) = lower(trim(p_email))
      AND is_deleted   = false
    LIMIT 1;

    IF v_user_id IS NOT NULL THEN
        -- ── Existing active user → Google login ───────────────────────────────
        RETURN json_build_object(
            'status',  true,
            'message', 'Login successful',
            'data', json_build_object(
                'user_id', v_user_id
            )
        );
    END IF;

    -- ── No active account found → Google signup (fresh account) ──────────────
    -- If the user previously deleted their account, their email was anonymized
    -- in public.users, so this INSERT always creates a brand new UUID with
    -- no association to any old profiles or events.
    INSERT INTO users (email, password, username, auth_provider, created_at, updated_at)
    VALUES (
        trim(p_email),
        NULL,
        CASE WHEN p_username IS NULL OR trim(p_username) = '' THEN NULL ELSE trim(p_username) END,
        'google',
        now(),
        now()
    )
    RETURNING id INTO v_user_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'Account created successfully',
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
