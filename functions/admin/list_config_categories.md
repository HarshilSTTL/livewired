# `list_config_categories`

```sql
-- Function: list_config_categories
-- Group: Admin
-- Endpoint: POST /rpc/list_config_categories
-- Doc: docs/api/admin/system_config.md
-- Purpose: List all config categories for admin UI tabs/groups.
--
-- Parameters:
--   p_user_id - Caller's user ID (for admin auth check)
--
-- Returns: JSON array of categories with count

CREATE OR REPLACE FUNCTION list_config_categories(p_user_id uuid)
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
            SELECT json_agg(
                json_build_object(
                    'category', category,
                    'count', COUNT(*),
                    'updated_at', MAX(updated_at)
                )
                ORDER BY category
            )
            FROM system_config
            WHERE NOT is_sensitive
            GROUP BY category
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
  "data": [
    {
      "category": "auth",
      "count": 7,
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    {
      "category": "event",
      "count": 4,
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    {
      "category": "platform",
      "count": 3,
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    ...
  ]
}
```
