# `get_user`

```sql
-- Function: get_user
-- Group: Auth
-- Endpoint: POST /rpc/get_user
-- Doc: docs/api/auth/get_user.md

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
    SELECT id, email, username
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
            'user_id',  v_user.id,
            'username', v_user.username,
            'email',    v_user.email
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
