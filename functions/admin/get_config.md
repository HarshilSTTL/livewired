# `get_config`

```sql
-- Function: get_config
-- Group: Admin
-- Doc: docs/api/admin/system_config.md
-- Purpose: Read a single config value by key. Used internally by other SPs.
--
-- Parameters:
--   p_key     - Config key to fetch (e.g. 'email_verification_expiry_hours')
--   p_default - Fallback value if key not found
--
-- Returns: Config value as text, or p_default if not found

CREATE OR REPLACE FUNCTION get_config(p_key text, p_default text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_value text;
BEGIN
    SELECT config_value INTO v_value
    FROM system_config
    WHERE config_key = p_key;
    
    RETURN COALESCE(v_value, p_default);
END;
$$;
```

---

## Usage in other SPs

**Example 1: Get integer value**
```sql
v_max_collabs := (get_config('max_collaborators_per_event', '5'))::int;
```

**Example 2: Get interval**
```sql
v_token_expiry := now() + (get_config('email_verification_expiry_hours', '24') || ' hours')::INTERVAL;
```

**Example 3: Get JSON array**
```sql
v_default_platforms := (get_config('default_platforms', '[]'))::jsonb;
```

**Example 4: Get boolean**
```sql
v_verification_required := (get_config('email_verification_enabled', 'true'))::boolean;
```
