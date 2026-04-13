# `delete_custom_link`

```sql
-- Function: delete_custom_link
-- Group:    profiles
-- Endpoint: POST /rpc/delete_custom_link
-- Tables:   profile_custom_links (UPDATE), creator_profiles (SELECT)
-- Doc:      docs/api/profiles/delete_custom_link.md

CREATE OR REPLACE FUNCTION delete_custom_link(
    p_id      uuid,
    p_user_id uuid
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

    -- ── Soft delete ──────────────────────────────────────────────────────────
    UPDATE profile_custom_links
    SET is_deleted = true,
        deleted_at = now()
    WHERE id = p_id
      AND is_deleted = false;

    RETURN json_build_object(
        'status',  true,
        'message', 'Custom link deleted successfully'
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
