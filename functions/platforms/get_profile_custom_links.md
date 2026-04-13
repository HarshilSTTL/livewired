# `get_profile_custom_links`

```sql
-- Function: get_profile_custom_links
-- Group:    platforms
-- Endpoint: POST /rpc/get_profile_custom_links
-- Tables:   profile_custom_links (SELECT)
-- Doc:      docs/api/platforms/get_profile_custom_links.md
--
-- Purpose:  Returns all active (non-deleted) custom platform links for a
--           given creator profile. Used to populate the Custom Links section
--           on the profile edit screen and the Additional Links dropdown.

CREATE OR REPLACE FUNCTION get_profile_custom_links(
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

    -- ── Fetch active custom links ────────────────────────────────────────────
    SELECT json_agg(
        json_build_object(
            'custom_id',    pcl.id,
            'platform_name', pcl.platform_name,
            'platform_url',  pcl.platform_url,
            'is_custom',    true,
            'created_at',   pcl.created_at,
            'updated_at',   pcl.updated_at
        )
        ORDER BY pcl.created_at ASC
    )
    INTO v_result
    FROM profile_custom_links pcl
    WHERE pcl.profile_id = p_profile_id
      AND pcl.is_deleted = false;

    -- ── Return ───────────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status',  true,
        'message', 'Custom links fetched successfully',
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
