# `update_user`

```sql
-- Function: update_user
-- Group: Auth
-- Endpoint: POST /rpc/update_user
-- Doc: docs/api/auth/update_user.md

CREATE OR REPLACE FUNCTION update_user(
    p_user_id  uuid,
    p_username text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF p_username IS NULL OR trim(p_username) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Username is required');
    END IF;

    IF length(trim(p_username)) < 3 THEN
        RETURN json_build_object('status', false, 'message', 'Username must be at least 3 characters');
    END IF;

    -- ── Verify user exists ────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE id = p_user_id AND is_deleted = false
    ) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    -- ── Update username ───────────────────────────────────────────────────────
    UPDATE users
    SET username   = trim(p_username),
        updated_at = now()
    WHERE id = p_user_id;

    -- ── Success ───────────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status',  true,
        'message', 'User updated successfully',
        'data', json_build_object(
            'user_id',  p_user_id,
            'username', trim(p_username)
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
