# `get_platforms`

```sql
-- Function: get_platforms
-- Group:    platforms
-- Endpoint: POST /rpc/get_platforms
-- Tables:   platforms (SELECT)
-- Doc:      docs/api/platforms/get_platforms.md
--
-- Purpose:  Returns list of all available platforms (YouTube, Twitch, Kick, Rumble)
--           with platform ID, name, and logo URL.
--           Used for profile setup, event creation, and platform selection UI.

CREATE OR REPLACE FUNCTION get_platforms()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_platforms json;
BEGIN

    -- ── Fetch all platforms ───────────────────────────────────────────────────
    SELECT json_agg(
        json_build_object(
            'plat_id',   p.plat_id,
            'plat_name', p.plat_name,
            'logo_url',  p.logo_url
        )
        
        ORDER BY p.plat_id ASC
    )
    INTO v_platforms
    FROM platforms p
WHERE p.plat_id IN (1,2,3,4);
    RETURN json_build_object(
        'status',  true,
        'message', 'Platforms fetched successfully',
        'data', json_build_object(
            'platforms', COALESCE(v_platforms, '[]'::json)
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
