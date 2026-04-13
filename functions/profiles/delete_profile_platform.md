# `delete_profile_platform`

```sql
-- Function: delete_profile_platform
-- Group:    profiles
-- Endpoint: POST /rpc/delete_profile_platform
-- Tables:   creator_platform_accounts (UPDATE), creator_profiles (SELECT)
-- Doc:      docs/api/profiles/delete_profile_platform.md

CREATE OR REPLACE FUNCTION delete_profile_platform(
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
        RETURN json_build_object('status', false, 'message', 'Platform link ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    -- ── Ownership check + existence check ────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM creator_platform_accounts cpa
        JOIN creator_profiles cp ON cp.id = cpa.profile_id
        WHERE cpa.id = p_id
          AND cpa.is_deleted = false
          AND cp.user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Platform link not found or access denied');
    END IF;

    -- ── Soft delete ──────────────────────────────────────────────────────────
    UPDATE creator_platform_accounts
    SET is_deleted = true,
        deleted_at = now()
    WHERE id = p_id
      AND is_deleted = false;

    RETURN json_build_object(
        'status',  true,
        'message', 'Platform link deleted successfully'
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
