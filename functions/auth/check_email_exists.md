# `check_email_exists`

```sql
-- Function: check_email_exists
-- Group: Auth
-- Endpoint: POST /rpc/check_email_exists
-- Doc: docs/api/auth/check_email_exists.md

CREATE OR REPLACE FUNCTION check_email_exists(
    p_email text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_exists boolean;
BEGIN

    -- ── Null guard ────────────────────────────────────────────────────────────
    IF p_email IS NULL OR trim(p_email) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Email is required');
    END IF;

    -- ── Lookup (case-insensitive, ignore soft-deleted accounts) ───────────────
    SELECT EXISTS (
        SELECT 1
        FROM users
        WHERE lower(email) = lower(trim(p_email))
          AND is_deleted   = false
    )
    INTO v_exists;

    IF NOT v_exists THEN
        RETURN json_build_object('status', false, 'message', 'Please enter a valid email');
    END IF;

    RETURN json_build_object('status', true, 'message', 'Email found');

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;

-- Must be callable before login (forgot-password screen)
GRANT EXECUTE ON FUNCTION check_email_exists(text) TO anon, authenticated;
```
