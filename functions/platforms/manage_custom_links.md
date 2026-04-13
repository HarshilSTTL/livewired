# `manage_custom_links`

```sql
-- Function: manage_custom_links
-- Group:    platforms
-- Endpoint: POST /rpc/manage_custom_links
-- Tables:   profile_custom_links (INSERT · UPDATE · soft-DELETE), creator_profiles (SELECT)
-- Doc:      docs/api/platforms/manage_custom_links.md
--
-- Behaviour:
--   • Replace-aware: compares sent list vs DB to decide insert / update / soft-delete.
--   • id present in item  → UPDATE that row (platform_name, platform_url, updated_at).
--   • id null in item     → INSERT new row.
--   • Row in DB but not in sent list → soft-delete (is_deleted = true, deleted_at = now()).
--   • p_links = []        → soft-deletes all existing custom links for the profile.
--   • Ownership enforced: profile must belong to p_user_id.

CREATE OR REPLACE FUNCTION manage_custom_links(
    p_profile_id uuid,
    p_user_id    uuid,
    p_links      jsonb  DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_link         jsonb;
    v_id           uuid;
    v_name         text;
    v_url          text;
    v_sent_ids     uuid[];
BEGIN

    -- ── Null guards ──────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF p_links IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Links list is required');
    END IF;

    -- ── Ownership check ──────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- ── Validate each item in the list ───────────────────────────────────────
    IF jsonb_array_length(p_links) > 0 THEN

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_links) AS lnk
            WHERE lnk->>'platform_name' IS NULL OR trim(lnk->>'platform_name') = ''
        ) THEN
            RETURN json_build_object('status', false, 'message', 'Platform name is required for each link');
        END IF;

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_links) AS lnk
            WHERE lnk->>'platform_url' IS NULL OR trim(lnk->>'platform_url') = ''
        ) THEN
            RETURN json_build_object('status', false, 'message', 'URL is required for each link');
        END IF;

    END IF;

    -- ── Build array of sent IDs (for soft-delete comparison) ─────────────────
    SELECT array_agg((lnk->>'id')::uuid)
    INTO v_sent_ids
    FROM jsonb_array_elements(p_links) AS lnk
    WHERE lnk->>'id' IS NOT NULL;

    -- ── Soft-delete rows not in the sent list ────────────────────────────────
    UPDATE profile_custom_links
    SET
        is_deleted = true,
        deleted_at = now(),
        updated_at = now()
    WHERE profile_id = p_profile_id
      AND is_deleted = false
      AND (
          v_sent_ids IS NULL
          OR id != ALL(v_sent_ids)
      );

    -- ── Insert or update each item ───────────────────────────────────────────
    IF jsonb_array_length(p_links) > 0 THEN
        FOR v_link IN SELECT * FROM jsonb_array_elements(p_links)
        LOOP
            v_id   := (v_link->>'id')::uuid;
            v_name := trim(v_link->>'platform_name');
            v_url  := trim(v_link->>'platform_url');

            IF v_id IS NOT NULL THEN
                -- UPDATE existing row
                UPDATE profile_custom_links
                SET
                    platform_name = v_name,
                    platform_url  = v_url,
                    updated_at   = now()
                WHERE id         = v_id
                  AND profile_id = p_profile_id
                  AND is_deleted = false;
            ELSE
                -- INSERT new row
                INSERT INTO profile_custom_links (
                    id, profile_id, platform_name, platform_url,
                    is_deleted, created_at, updated_at
                )
                VALUES (
                    gen_random_uuid(), p_profile_id, v_name, v_url,
                    false, now(), now()
                );
            END IF;
        END LOOP;
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Custom links updated successfully',
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
