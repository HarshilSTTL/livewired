# `create_profile`

```sql
-- Function: create_profile
-- Group: Profile
-- Endpoint: POST /rpc/create_profile
-- Doc: docs/api/profiles/create_profile.md

CREATE OR REPLACE FUNCTION create_profile(
    p_user_id        uuid,
    p_profile_name   text,
    p_username       text,
    p_avatar         text     DEFAULT null,
    p_bio            text     DEFAULT null,
    p_is_default     boolean  DEFAULT false,
    p_status         text     DEFAULT 'active',
    p_show_followers boolean  DEFAULT true,
    p_platforms      jsonb    DEFAULT null,
    p_tag_ids        bigint[] DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile_id   uuid;
    v_platform     jsonb;
    v_platform_id  bigint;
    v_channel_url  text;
    v_is_default   boolean;
BEGIN

    -- ── User existence check ──────────────────────────────────────────────────
    -- Any registered user can create a creator profile.
    IF NOT EXISTS (
        SELECT 1 FROM users WHERE id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    IF p_profile_name IS NULL OR trim(p_profile_name) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Profile name is required');
    END IF;

    IF p_username IS NULL OR trim(p_username) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Username is required');
    END IF;

    IF p_status NOT IN ('active', 'suspended', 'deleted') THEN
        RETURN json_build_object('status', false, 'message', 'Invalid status');
    END IF;

    IF EXISTS (SELECT 1 FROM creator_profiles WHERE username = p_username) THEN
        RETURN json_build_object('status', false, 'message', 'Username already taken');
    END IF;

    IF EXISTS (SELECT 1 FROM creator_profiles WHERE profile_name = p_profile_name) THEN
        RETURN json_build_object('status', false, 'message', 'Profile name already taken');
    END IF;

    IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
            WHERE NOT EXISTS (
                SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint
            )
        ) THEN
            RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
        END IF;

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
            WHERE pl->>'channel_url' IS NULL OR trim(pl->>'channel_url') = ''
        ) THEN
            RETURN json_build_object('status', false, 'message', 'Channel URL is required for each platform');
        END IF;
    END IF;

    IF p_tag_ids IS NOT NULL AND array_length(p_tag_ids, 1) > 0 THEN
        IF array_length(p_tag_ids, 1) > 10 THEN
            RETURN json_build_object('status', false, 'message', 'Maximum 10 tags allowed');
        END IF;

        IF EXISTS (
            SELECT 1 FROM unnest(p_tag_ids) AS t(tag_id)
            WHERE t.tag_id NOT IN (SELECT tag_id FROM tags)
        ) THEN
            RETURN json_build_object('status', false, 'message', 'One or more tag IDs are invalid');
        END IF;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM creator_profiles WHERE user_id = p_user_id) THEN
        p_is_default := true;
    END IF;

    IF p_is_default = true THEN
        UPDATE creator_profiles SET is_default = false WHERE user_id = p_user_id;
    END IF;

    INSERT INTO creator_profiles (
        id, user_id, profile_name, username,
        avatar, bio, is_default, status,
        show_followers, created_at, updated_at
    )
    VALUES (
        gen_random_uuid(), p_user_id, p_profile_name, p_username,
        p_avatar, p_bio, p_is_default, p_status,
        p_show_followers, now(), now()
    )
    RETURNING id INTO v_profile_id;

    -- ── Auto-promote user to creator role ─────────────────────────────────────
    -- Creating a profile makes the user a creator — set role_id = 2.
    UPDATE users SET role_id = 2, updated_at = now() WHERE id = p_user_id;

    IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
        FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
        LOOP
            v_platform_id := (v_platform->>'platform_id')::bigint;
            v_channel_url := v_platform->>'channel_url';
            v_is_default  := coalesce((v_platform->>'is_default')::boolean, false);

            INSERT INTO creator_platform_accounts (
                id, profile_id, platform_id, channel_url, username, is_default
            )
            VALUES (
                gen_random_uuid(), v_profile_id, v_platform_id,
                v_channel_url, p_username, v_is_default
            );
        END LOOP;
    END IF;

    IF p_tag_ids IS NOT NULL AND array_length(p_tag_ids, 1) > 0 THEN
        INSERT INTO profile_tags (id, profile_id, tag_id)
        SELECT gen_random_uuid(), v_profile_id, unnest(p_tag_ids);
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Profile created successfully',
        'data', json_build_object(
            'profile_id',     v_profile_id,
            'show_followers', p_show_followers
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
