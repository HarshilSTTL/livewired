# `delete_account`

```sql
-- Function: delete_account
-- Group: Auth
-- Endpoint: POST /rpc/delete_account
-- Doc: docs/api/auth/delete_account.md
-- Soft delete on public.users, creator_profiles, event_mst.
-- Hard delete on auth.users — frees the email/OAuth identity so the user
-- can re-register cleanly and prevents silent re-login via Google OAuth.
-- Required by Google Play and Apple App Store policies.

CREATE OR REPLACE FUNCTION delete_account(
    p_user_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id is required');
    END IF;

    -- Check user exists and is not already deleted
    IF NOT EXISTS (
        SELECT 1 FROM users
        WHERE id         = p_user_id
          AND is_deleted = false
    ) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    -- Soft delete all events across all profiles
    UPDATE event_mst
    SET    is_deleted = true,
           deleted_at = now()
    WHERE  profile_id IN (
               SELECT id FROM creator_profiles WHERE user_id = p_user_id
           )
      AND  is_deleted = false;

    -- Soft delete all profiles
    UPDATE creator_profiles
    SET    status     = 'deleted',
           deleted_at = now(),
           updated_at = now()
    WHERE  user_id    = p_user_id
      AND  status    != 'deleted';

    -- Soft delete the user row + anonymize the email
    -- Anonymizing the email frees it from the UNIQUE constraint so the user
    -- can re-register with the same address as a completely fresh account
    -- (new UUID, no old profiles/events attached).
    UPDATE users
    SET    is_deleted  = true,
           deleted_at  = now(),
           updated_at  = now(),
           email       = 'deleted_' || p_user_id::text || '@deleted.invalid'
    WHERE  id          = p_user_id;

    -- Hard delete from auth.users
    -- Frees the email/OAuth identity so Supabase Auth does not block re-registration
    -- and Google OAuth cannot silently re-authenticate a deleted account.
    DELETE FROM auth.users WHERE id = p_user_id;

    RETURN json_build_object('status', true, 'message', 'Account deleted successfully');

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
