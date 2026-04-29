# `update_profile`

```sql
-- Function: update_profile
-- Group:    profiles
-- Endpoint: POST /rpc/update_profile
-- Tables:   creator_profiles (UPDATE), creator_platform_accounts (UPSERT), profile_tags (DELETE+INSERT)
-- Doc:      docs/api/profiles/update_profile.md
--
-- Behaviour:
--   • COALESCE pattern — only updates fields that are explicitly passed (non-null).
--   • p_platforms = non-null  → upsert: UPDATE existing row if platform_id matches, INSERT if not found.
--   • p_platforms = null      → platforms are NOT touched.
--   • p_platforms = []        → no platform changes (nothing inserted or deleted).
--   • Same semantics apply to p_tag_ids.
--   • Ownership enforced: profile must belong to p_user_id.

CREATE OR REPLACE FUNCTION update_profile(
    p_profile_id          uuid,
    p_user_id             uuid,
    p_profile_name        text     DEFAULT null,
    p_avatar              text     DEFAULT null,
    p_bio                 text     DEFAULT null,
    p_is_default          boolean  DEFAULT null,
    p_status              text     DEFAULT null,
    p_show_followers      boolean  DEFAULT null,
    p_twitch_by_default   boolean  DEFAULT null,
    p_kick_by_default     boolean  DEFAULT null,
    p_platforms           jsonb    DEFAULT null,
    p_tag_ids             bigint[] DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_platform       jsonb;
    v_platform_id    bigint;
    v_channel_url    text;
    v_plat_default   boolean;
BEGIN

    -- ── Null guards ──────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    -- ── Ownership check ──────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- ── Profile name validation (if provided) ────────────────────────────────
    IF p_profile_name IS NOT NULL AND trim(p_profile_name) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Profile name cannot be empty');
    END IF;

    IF p_profile_name IS NOT NULL AND EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE profile_name = p_profile_name AND id != p_profile_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile name already taken');
    END IF;

    -- ── Status validation (if provided) ──────────────────────────────────────
    IF p_status IS NOT NULL AND p_status NOT IN ('active', 'suspended', 'deleted') THEN
        RETURN json_build_object('status', false, 'message', 'Invalid status');
    END IF;

    -- ── Platform validation (if provided and non-empty) ──────────────────────
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

    -- ── Tag validation (if provided and non-empty) ───────────────────────────
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

    -- ── is_default: unset other profiles first ───────────────────────────────
    IF p_is_default = true THEN
        UPDATE creator_profiles
        SET is_default = false
        WHERE user_id = p_user_id AND id != p_profile_id;
    END IF;

    -- ── Update creator_profiles ───────────────────────────────────────────────
    UPDATE creator_profiles SET
        profile_name        = COALESCE(p_profile_name,       profile_name),
        avatar              = COALESCE(p_avatar,             avatar),
        bio                 = COALESCE(p_bio,                bio),
        is_default          = COALESCE(p_is_default,         is_default),
        status              = COALESCE(p_status,             status),
        show_followers      = COALESCE(p_show_followers,     show_followers),
        twitch_by_default   = COALESCE(p_twitch_by_default,  twitch_by_default),
        kick_by_default     = COALESCE(p_kick_by_default,    kick_by_default),
        updated_at          = now()
    WHERE id = p_profile_id;

    -- ── Upsert platforms (if p_platforms is not null) ─────────────────────────
    IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN

        FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
        LOOP
            v_platform_id  := (v_platform->>'platform_id')::bigint;
            v_channel_url  := v_platform->>'channel_url';
            v_plat_default := coalesce((v_platform->>'is_default')::boolean, false);

            -- UPDATE existing active row if found, else INSERT new row
            IF EXISTS (
                SELECT 1 FROM creator_platform_accounts
                WHERE profile_id  = p_profile_id
                  AND platform_id = v_platform_id
                  AND is_deleted  = false
            ) THEN
                UPDATE creator_platform_accounts
                SET
                    channel_url = v_channel_url,
                    is_default  = v_plat_default
                WHERE profile_id  = p_profile_id
                  AND platform_id = v_platform_id
                  AND is_deleted  = false;
            ELSE
                INSERT INTO creator_platform_accounts (
                    id, profile_id, platform_id, channel_url, is_default
                )
                VALUES (
                    gen_random_uuid(), p_profile_id, v_platform_id,
                    v_channel_url, v_plat_default
                );
            END IF;
        END LOOP;

    END IF;

    -- ── Replace tags (if p_tag_ids is not null) ───────────────────────────────
    IF p_tag_ids IS NOT NULL THEN

        DELETE FROM profile_tags WHERE profile_id = p_profile_id;

        IF array_length(p_tag_ids, 1) > 0 THEN
            INSERT INTO profile_tags (id, profile_id, tag_id)
            SELECT gen_random_uuid(), p_profile_id, unnest(p_tag_ids);
        END IF;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Profile updated successfully',
        'data', json_build_object(
            'profile_id', p_profile_id
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
