# `get_all_configs`

```sql
-- Function: get_all_configs
-- Group: Admin
-- Endpoint: POST /rpc/get_all_configs
-- Doc: docs/api/admin/system_config.md
-- Purpose: Fetch all configs (or by category) for admin dashboard.
--          Only non-sensitive configs are returned.
--
-- Parameters:
--   p_user_id - Caller's user ID (for admin auth check)
--   p_category - Optional filter by category (auth, event, platform, etc.)
--
-- Returns: JSON with status + all configs grouped by category

CREATE OR REPLACE FUNCTION get_all_configs(p_user_id uuid, p_category text DEFAULT NULL)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_is_admin boolean;
BEGIN
    -- Check if user is admin
    SELECT (role_id = 1) INTO v_is_admin
    FROM users
    WHERE id = p_user_id;

    IF NOT v_is_admin THEN
        RETURN json_build_object('status', false, 'message', 'Admin access required');
    END IF;

    RETURN json_build_object(
        'status', true,
        'data', (
            SELECT json_object_agg(config_key, 
                json_build_object(
                    'value', config_value,
                    'type', data_type,
                    'category', category,
                    'description', description,
                    'updated_at', updated_at
                )
            )
            FROM system_config
            WHERE (p_category IS NULL OR category = p_category)
              AND NOT is_sensitive
            ORDER BY category, config_key
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```

---

## Response format

```json
{
  "status": true,
  "data": {
    "email_verification_enabled": {
      "value": "true",
      "type": "boolean",
      "category": "auth",
      "description": "Require email verification on signup",
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    "max_collaborators_per_event": {
      "value": "5",
      "type": "integer",
      "category": "event",
      "description": "Maximum collaborators per event",
      "updated_at": "2026-06-23T10:00:00+00:00"
    }
    ...
  }
}
```
