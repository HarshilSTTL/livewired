# `manage_profile_platform`

```sql
-- Function: manage_profile_platform
-- Group:    profiles
-- Endpoint: POST /rpc/manage_profile_platform
-- Tables:   creator_platform_accounts (INSERT · UPDATE · soft-DELETE), creator_profiles (SELECT), platforms (SELECT)
-- Doc:      docs/api/profiles/manage_profile_platform.md
--
-- Behaviour:
--   • Replace-aware: compares sent list vs DB to decide insert / update / soft-delete.
--   • id present in item  → UPDATE channel_url on that row.
--   • id null in item     → INSERT new row.
--   • Row in DB but not in sent list → soft-delete (is_deleted = true, deleted_at = now()).
--   • p_platforms = []   → soft-deletes all existing platform links for the profile.
--   • Ownership enforced: profile must belong to p_user_id.

CREATE OR REPLACE FUNCTION manage_profile_platform(
    p_profile_id uuid,
    p_user_id    uuid,
    p_platforms  jsonb  DEFAULT '[]'::jsonb
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_item        jsonb;
    v_id          uuid;
    v_platform_id bigint;
    v_channel_url text;
    v_sent_ids    uuid[];
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

    -- ── Validate each item in the list ───────────────────────────────────────
    IF jsonb_array_length(p_platforms) > 0 THEN

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS itm
            WHERE (itm->>'id') IS NULL
              AND (itm->>'platform_id') IS NULL
        ) THEN
            RETURN json_build_object('status', false, 'message', 'platform_id is required for new platform links');
        END IF;

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS itm
            WHERE itm->>'channel_url' IS NULL OR trim(itm->>'channel_url') = ''
        ) THEN
            RETURN json_build_object('status', false, 'message', 'channel_url is required for each platform link');
        END IF;

    END IF;

    -- ── Build array of sent IDs (for soft-delete comparison) ─────────────────
    SELECT array_agg((itm->>'id')::uuid)
    INTO v_sent_ids
    FROM jsonb_array_elements(p_platforms) AS itm
    WHERE itm->>'id' IS NOT NULL;

    -- ── Soft-delete rows not in the sent list ────────────────────────────────
    UPDATE creator_platform_accounts
    SET is_deleted = true,
        deleted_at = now()
    WHERE profile_id  = p_profile_id
      AND is_deleted  = false
      AND (
          v_sent_ids IS NULL
          OR id != ALL(v_sent_ids)
      );

    -- ── Insert or update each item ───────────────────────────────────────────
    IF jsonb_array_length(p_platforms) > 0 THEN
        FOR v_item IN SELECT * FROM jsonb_array_elements(p_platforms)
        LOOP
            v_id          := (v_item->>'id')::uuid;
            v_platform_id := (v_item->>'platform_id')::bigint;
            v_channel_url := trim(v_item->>'channel_url');

            IF v_id IS NOT NULL THEN
                -- UPDATE existing row
                UPDATE creator_platform_accounts
                SET channel_url = v_channel_url
                WHERE id         = v_id
                  AND profile_id = p_profile_id
                  AND is_deleted = false;
            ELSE
                -- Validate platform exists before insert
                IF NOT EXISTS (
                    SELECT 1 FROM platforms WHERE plat_id = v_platform_id
                ) THEN
                    CONTINUE;
                END IF;

                -- INSERT new row
                INSERT INTO creator_platform_accounts (
                    id, profile_id, platform_id, channel_url, is_deleted
                )
                VALUES (
                    gen_random_uuid(), p_profile_id, v_platform_id, v_channel_url, false
                );
            END IF;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Platform links updated successfully',
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
