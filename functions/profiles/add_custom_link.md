# `add_custom_link`

```sql
-- Function: add_custom_link
-- Group:    profiles
-- Endpoint: POST /rpc/add_custom_link
-- Tables:   profile_custom_links (INSERT), creator_profiles (SELECT)
-- Doc:      docs/api/profiles/add_custom_link.md

CREATE OR REPLACE FUNCTION add_custom_link(
    p_profile_id   uuid,
    p_user_id      uuid,
    p_profile_name text,
    p_profile_url  text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_new_id uuid;
BEGIN

    -- ── Null guards ──────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF p_profile_name IS NULL OR trim(p_profile_name) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Link name is required');
    END IF;

    IF p_profile_url IS NULL OR trim(p_profile_url) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Link URL is required');
    END IF;

    -- ── Ownership check ──────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- ── Insert ───────────────────────────────────────────────────────────────
    INSERT INTO profile_custom_links (
        id, profile_id, profile_name, profile_url, is_deleted
    )
    VALUES (
        gen_random_uuid(), p_profile_id, trim(p_profile_name), trim(p_profile_url), false
    )
    RETURNING id INTO v_new_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'Custom link added successfully',
        'data', json_build_object(
            'id', v_new_id
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
