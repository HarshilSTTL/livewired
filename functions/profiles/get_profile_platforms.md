# `get_profile_platforms`

```sql
-- Function: get_profile_platforms
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_platforms
-- Tables:   creator_platform_accounts (SELECT), platforms (SELECT), creator_profiles (SELECT)
-- Doc:      docs/api/profiles/get_profile_platforms.md

CREATE OR REPLACE FUNCTION get_profile_platforms(
    p_profile_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN

    -- ── Null guard ───────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    -- ── Profile existence check ──────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles WHERE id = p_profile_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    -- ── Fetch active platform links ──────────────────────────────────────────
    SELECT json_agg(
        json_build_object(
            'id',            cpa.id,
            'platform_id',   cpa.platform_id,
            'platform_name', p.plat_name,
            'logo_url',      p.logo_url,
            'channel_url',   cpa.channel_url,
            'is_default',    cpa.is_default
        )
        ORDER BY cpa.platform_id ASC
    )
    INTO v_result
    FROM creator_platform_accounts cpa
    LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
    WHERE cpa.profile_id = p_profile_id
      AND cpa.is_deleted = false;

    RETURN json_build_object(
        'status',  true,
        'message', 'Platform links fetched successfully',
        'data',    COALESCE(v_result, '[]'::json)
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
