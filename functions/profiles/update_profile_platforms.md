# `update_profile_platforms`

```sql
-- Function: update_profile_platforms
-- Group:    profiles
-- Endpoint: POST /rpc/update_profile_platforms
-- Tables:   creator_platform_accounts (DELETE + INSERT)
-- Doc:      docs/api/profiles/update_profile_platforms.md
--
-- Behaviour:
--   • Dedicated SP for managing a creator's additional platform links.
--   • Replace-all: deletes all existing rows then inserts the new list.
--   • p_platforms = []        → clears all platform accounts.
--   • p_platforms = [{...}]   → replaces with the provided list.
--   • p_platforms = null      → returns error (required for this SP).
--   • Ownership enforced: profile must belong to p_user_id.

CREATE OR REPLACE FUNCTION update_profile_platforms(
    p_profile_id uuid,
    p_user_id    uuid,
    p_platforms  jsonb  DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_platform      jsonb;
    v_platform_id   bigint;
    v_channel_url   text;
    v_plat_default  boolean;
    v_final_username text;
BEGIN

    -- ── Null guards ──────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF p_platforms IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Platforms list is required');
    END IF;

    -- ── Ownership check ──────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- ── Platform validation (if non-empty) ───────────────────────────────────
    IF jsonb_array_length(p_platforms) > 0 THEN

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

    -- ── Fetch current username for creator_platform_accounts ─────────────────
    SELECT username INTO v_final_username
    FROM creator_profiles WHERE id = p_profile_id;

    -- ── Replace all platforms (DELETE + INSERT) ──────────────────────────────
    DELETE FROM creator_platform_accounts WHERE profile_id = p_profile_id;

    IF jsonb_array_length(p_platforms) > 0 THEN
        FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
        LOOP
            v_platform_id  := (v_platform->>'platform_id')::bigint;
            v_channel_url  := v_platform->>'channel_url';
            v_plat_default := coalesce((v_platform->>'is_default')::boolean, false);

            INSERT INTO creator_platform_accounts (
                id, profile_id, platform_id, channel_url, username, is_default
            )
            VALUES (
                gen_random_uuid(), p_profile_id, v_platform_id,
                v_channel_url, v_final_username, v_plat_default
            );
        END LOOP;
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Profile platforms updated successfully',
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
