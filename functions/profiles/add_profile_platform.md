# `add_profile_platform`

```sql
-- Function: add_profile_platform
-- Group:    profiles
-- Endpoint: POST /rpc/add_profile_platform
-- Tables:   creator_platform_accounts (INSERT), creator_profiles (SELECT), platforms (SELECT)
-- Doc:      docs/api/profiles/add_profile_platform.md

CREATE OR REPLACE FUNCTION add_profile_platform(
    p_profile_id  uuid,
    p_user_id     uuid,
    p_platform_id bigint,
    p_channel_url text
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

    IF p_platform_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Platform ID is required');
    END IF;

    IF p_channel_url IS NULL OR trim(p_channel_url) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Channel URL is required');
    END IF;

    -- ── Ownership check ──────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- ── Platform validation ──────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM platforms WHERE plat_id = p_platform_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Platform ID is invalid');
    END IF;

    -- ── Insert ───────────────────────────────────────────────────────────────
    INSERT INTO creator_platform_accounts (
        id, profile_id, platform_id, channel_url, is_deleted
    )
    VALUES (
        gen_random_uuid(), p_profile_id, p_platform_id, trim(p_channel_url), false
    )
    RETURNING id INTO v_new_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'Platform link added successfully',
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
