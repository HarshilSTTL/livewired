# `update_custom_link`

```sql
-- Function: update_custom_link
-- Group:    profiles
-- Endpoint: POST /rpc/update_custom_link
-- Tables:   profile_custom_links (UPDATE), creator_profiles (SELECT)
-- Doc:      docs/api/profiles/update_custom_link.md

CREATE OR REPLACE FUNCTION update_custom_link(
    p_id           uuid,
    p_user_id      uuid,
    p_profile_name text,
    p_profile_url  text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- ── Null guards ──────────────────────────────────────────────────────────
    IF p_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Custom link ID is required');
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

    -- ── Ownership check + existence check ────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM profile_custom_links pcl
        JOIN creator_profiles cp ON cp.id = pcl.profile_id
        WHERE pcl.id = p_id
          AND pcl.is_deleted = false
          AND cp.user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Custom link not found or access denied');
    END IF;

    -- ── Update ───────────────────────────────────────────────────────────────
    UPDATE profile_custom_links
    SET profile_name = trim(p_profile_name),
        profile_url  = trim(p_profile_url),
        updated_at   = now()
    WHERE id = p_id
      AND is_deleted = false;

    RETURN json_build_object(
        'status',  true,
        'message', 'Custom link updated successfully'
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
