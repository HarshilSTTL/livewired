# `add_custom_link`

```sql
-- Function: add_custom_link
-- Group:    profiles
-- Endpoint: POST /rpc/add_custom_link
-- Tables:   profile_custom_links (INSERT), creator_profiles (SELECT)
-- Doc:      docs/api/profiles/add_custom_link.md

CREATE OR REPLACE FUNCTION add_custom_link(
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

    -- ── Loop and insert each link ─────────────────────────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_links)
    LOOP
        v_platform_name := trim(v_item->>'platform_name');
        v_platform_url  := trim(v_item->>'platform_url');

        -- Skip if name or URL missing
        CONTINUE WHEN v_platform_name IS NULL OR v_platform_name = '';
        CONTINUE WHEN v_platform_url  IS NULL OR v_platform_url  = '';

        INSERT INTO profile_custom_links (
            id, profile_id, platform_name, platform_url, is_deleted
        )
        VALUES (
            gen_random_uuid(), p_profile_id, v_platform_name, v_platform_url, false
        );

        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object(
        'status',  true,
        'message', v_count || ' custom link(s) added successfully',
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
