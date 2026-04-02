# `delete_profile`

```sql
-- Function: delete_profile
-- Group: Profiles
-- Endpoint: POST /rpc/delete_profile
-- Doc: docs/api/profiles/delete_profile.md
-- Soft delete. Sets status = 'deleted' and deleted_at = now() on the profile.
-- Also soft deletes all events belonging to this profile.
-- Ownership check: profile must belong to p_user_id.

CREATE OR REPLACE FUNCTION delete_profile(
    p_profile_id uuid,
    p_user_id    uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    IF p_profile_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_profile_id and p_user_id are required');
    END IF;

    -- Ownership + existence check
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id      = p_profile_id
          AND user_id = p_user_id
          AND status != 'deleted'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- Soft delete all events under this profile
    UPDATE event_mst
    SET    is_deleted = true,
           deleted_at = now()
    WHERE  profile_id = p_profile_id
      AND  is_deleted = false;

    -- Soft delete the profile
    UPDATE creator_profiles
    SET    status     = 'deleted',
           deleted_at = now(),
           updated_at = now()
    WHERE  id         = p_profile_id;

    RETURN json_build_object('status', true, 'message', 'Profile deleted successfully');

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
