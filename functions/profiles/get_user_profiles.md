# `get_user_profiles`

```sql
-- Function: get_user_profiles
-- Group:    profiles
-- Endpoint: POST /rpc/get_user_profiles
-- Tables:   creator_profiles (SELECT)
-- Doc:      docs/api/profiles/get_user_profiles.md
--
-- Purpose:  Lightweight profile list for post-login profile selector.
--           Returns only profile_id, profile_name, avatar, is_default.
--           No platforms, no tags, no follower counts.
--           Default profile is first in array.

CREATE OR REPLACE FUNCTION get_user_profiles(
    p_user_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    SELECT json_agg(
        json_build_object(
            'profile_id',   cp.id,
            'profile_name', cp.profile_name,
            'avatar',       cp.avatar,
            'is_default',   cp.is_default
        )
        ORDER BY cp.is_default DESC, cp.created_at ASC
    )
    INTO v_result
    FROM creator_profiles cp
    WHERE cp.user_id = p_user_id
    AND   cp.status  = 'active';

    RETURN json_build_object(
        'status',  true,
        'message', 'Profiles fetched successfully',
        'data', json_build_object(
            'profiles', coalesce(v_result, '[]'::json)
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
