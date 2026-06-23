# `update_config`

```sql
-- Function: update_config
-- Group: Admin
-- Endpoint: POST /rpc/update_config
-- Doc: docs/api/admin/system_config.md
-- Purpose: Update a config value. Admin-only.
--
-- Parameters:
--   p_config_key - Key to update (e.g. 'max_collaborators_per_event')
--   p_config_value - New value as text
--   p_user_id - Caller's user ID (for admin auth check)
--
-- Returns: JSON success/error response

CREATE OR REPLACE FUNCTION update_config(
    p_config_key text,
    p_config_value text,
    p_user_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin boolean;
    v_key_exists boolean;
BEGIN
    -- Check if user is admin
    SELECT (role_id = 1) INTO v_is_admin
    FROM users
    WHERE id = p_user_id;

    IF NOT v_is_admin THEN
        RETURN json_build_object('status', false, 'message', 'Admin access required');
    END IF;

    -- Validate inputs
    IF p_config_key IS NULL OR trim(p_config_key) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Config key is required');
    END IF;

    IF p_config_value IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Config value is required');
    END IF;

    -- Check if key exists
    SELECT EXISTS (
        SELECT 1 FROM system_config WHERE config_key = p_config_key
    ) INTO v_key_exists;

    IF NOT v_key_exists THEN
        RETURN json_build_object('status', false, 'message', 'Config key not found: ' || p_config_key);
    END IF;

    -- Update the config
    UPDATE system_config
    SET config_value = p_config_value,
        updated_at = now()
    WHERE config_key = p_config_key;

    RETURN json_build_object(
        'status', true,
        'message', 'Config updated successfully',
        'data', json_build_object(
            'config_key', p_config_key,
            'config_value', p_config_value,
            'updated_at', now()
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```

---

## Usage examples

**Update max collaborators:**
```json
POST /rpc/update_config
{
  "p_config_key": "max_collaborators_per_event",
  "p_config_value": "10",
  "p_user_id": "uuid-here"
}
```

**Update email expiry:**
```json
POST /rpc/update_config
{
  "p_config_key": "email_verification_expiry_hours",
  "p_config_value": "48",
  "p_user_id": "uuid-here"
}
```

**Update default platforms (JSON):**
```json
POST /rpc/update_config
{
  "p_config_key": "default_platforms",
  "p_config_value": "[1,2,3,4]",
  "p_user_id": "uuid-here"
}
```
