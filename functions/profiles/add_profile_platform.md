# `add_profile_platform`

```sql
-- Function: add_profile_platform
-- Group:    profiles
-- Endpoint: POST /rpc/add_profile_platform
-- Tables:   creator_platform_accounts (INSERT/UPDATE), creator_profiles (SELECT), platforms (SELECT)
-- Doc:      docs/api/profiles/add_profile_platform.md

CREATE OR REPLACE FUNCTION add_profile_platform(
    p_profile_id uuid,
    p_user_id    uuid,
    p_platforms  jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item        jsonb;
    v_platform_id bigint;
    v_channel_url text;
    v_count       int := 0;
BEGIN

    -- ── Null guards ──────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF p_platforms IS NULL OR jsonb_array_length(p_platforms) = 0 THEN
        RETURN json_build_object('status', false, 'message', 'Platforms list is required');
    END IF;

    -- ── Ownership check ──────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- ── Loop and upsert each platform ─────────────────────────────────────────
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_platforms)
    LOOP
        v_platform_id := (v_item->>'platform_id')::bigint;
        v_channel_url := trim(v_item->>'channel_url');

        -- Skip if platform_id or channel_url missing
        CONTINUE WHEN v_platform_id IS NULL;
        CONTINUE WHEN v_channel_url IS NULL OR v_channel_url = '';

        -- Skip if platform does not exist in platforms table
        CONTINUE WHEN NOT EXISTS (
            SELECT 1 FROM platforms WHERE plat_id = v_platform_id
        );

        -- Upsert: UPDATE if active row exists, INSERT if not
        IF EXISTS (
            SELECT 1 FROM creator_platform_accounts
            WHERE profile_id = p_profile_id
              AND platform_id = v_platform_id
              AND is_deleted = false
        ) THEN
            UPDATE creator_platform_accounts
            SET channel_url = v_channel_url
            WHERE profile_id = p_profile_id
              AND platform_id = v_platform_id
              AND is_deleted = false;
        ELSE
            INSERT INTO creator_platform_accounts (
                id, profile_id, platform_id, channel_url, is_deleted
            )
            VALUES (
                gen_random_uuid(), p_profile_id, v_platform_id, v_channel_url, false
            );
        END IF;

        v_count := v_count + 1;
    END LOOP;

    RETURN json_build_object(
        'status',  true,
        'message', v_count || ' platform link(s) saved successfully',
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
