# `reorder_social_links_v2`

```sql
-- Function: reorder_social_links_v2
-- Group: Profiles
-- Endpoint: POST /rpc/reorder_social_links_v2
-- Doc: docs/api/profiles/reorder_social_links.md
-- Version: 2.0 (2026-05-28)
-- Purpose: Save drag-drop reordering for platforms, additional links, and custom links

CREATE OR REPLACE FUNCTION reorder_social_links_v2(
    p_profile_id          uuid,
    p_platform_ids        int[] DEFAULT ARRAY[]::int[],
    p_additional_ids      int[] DEFAULT ARRAY[]::int[],
    p_custom_ids          uuid[] DEFAULT ARRAY[]::uuid[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN

    -- ── Validate profile exists ────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Profile ID is required'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM creator_profiles WHERE id = p_profile_id) THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Profile not found'
        );
    END IF;

    -- ── Upsert into profile_link_preferences ───────────────────────────────
    INSERT INTO profile_link_preferences (
        profile_id,
        platform_ids_order,
        additional_ids_order,
        custom_ids_order
    )
    VALUES (
        p_profile_id,
        p_platform_ids,
        p_additional_ids,
        p_custom_ids
    )
    ON CONFLICT (profile_id) DO UPDATE SET
        platform_ids_order = p_platform_ids,
        additional_ids_order = p_additional_ids,
        custom_ids_order = p_custom_ids;

    -- ── Build response ─────────────────────────────────────────────────────
    SELECT json_build_object(
        'profile_id',           p_profile_id,
        'platform_ids_order',   p_platform_ids,
        'additional_ids_order', p_additional_ids,
        'custom_ids_order',     p_custom_ids
    )
    INTO v_result
    FROM profile_link_preferences
    WHERE profile_id = p_profile_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'Links reordered successfully',
        'data',    v_result
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
