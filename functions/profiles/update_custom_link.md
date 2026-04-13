# `update_custom_link`

```sql
-- Function: update_custom_link
-- Group:    profiles
-- Endpoint: POST /rpc/update_custom_link
-- Tables:   profile_custom_links (UPDATE), creator_profiles (SELECT)
-- Doc:      docs/api/profiles/update_custom_link.md

CREATE OR REPLACE FUNCTION update_custom_link(
    p_profile_id uuid,
    p_user_id    uuid,
    p_links      jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item          jsonb;
    v_id            uuid;
    v_platform_name text;
    v_platform_url  text;
    v_count         int := 0;
BEGIN

    -- ── Null guards ──────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF p_links IS NULL OR jsonb_array_length(p_links) = 0 THEN
        RETURN json_build_object('status', false, 'message', 'Links list is required');
    END IF;

    -- ── Ownership check ──────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- ── Loop and update each link ─────────────────────────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_links)
    LOOP
        v_id            := (v_item->>'id')::uuid;
        v_platform_name := trim(v_item->>'platform_name');
        v_platform_url  := trim(v_item->>'platform_url');

        -- Skip if id missing
        CONTINUE WHEN v_id IS NULL;

        -- Skip if name or URL missing
        CONTINUE WHEN v_platform_name IS NULL OR v_platform_name = '';
        CONTINUE WHEN v_platform_url  IS NULL OR v_platform_url  = '';

        -- Only update rows that belong to this profile and are not deleted
        UPDATE profile_custom_links
        SET platform_name = v_platform_name,
            platform_url  = v_platform_url,
            updated_at    = now()
        WHERE id         = v_id
          AND profile_id = p_profile_id
          AND is_deleted = false;

        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object(
        'status',  true,
        'message', v_count || ' custom link(s) updated successfully',
        'data',    json_build_object('count', v_count)
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
