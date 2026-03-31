# `get_followers_list`

```sql
-- Function: get_followers_list
-- Group: Follow
-- Endpoint: POST /rpc/get_followers_list
-- Doc: docs/api/follow/get_followers_list.md

CREATE OR REPLACE FUNCTION get_followers_list(
    p_profile_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN
    -- Validate profile_id
    IF p_profile_id IS NULL THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'profile_id is required'
        );
    END IF;
    -- Check profile exists
    IF NOT EXISTS (
        SELECT 1 FROM public.creator_profiles
        WHERE id = p_profile_id
    ) THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Profile not found'
        );
    END IF;
    -- Get all active followers
    SELECT json_agg(
        json_build_object(
            'user_id',     u.id,
            'email',       u.email,
            'followed_at', f.created_at
        )
        ORDER BY f.created_at DESC
    )
    INTO v_result
    FROM public.follows f
    JOIN public.users u ON u.id = f.user_id
    WHERE f.profile_id = p_profile_id
    AND   f.is_active  = true;
    -- No followers found
    IF v_result IS NULL THEN
        RETURN json_build_object(
            'status',          true,
            'message',         'No followers found',
            'total_followers', 0,
            'data',            '[]'::json
        );
    END IF;
    RETURN json_build_object(
        'status',          true,
        'message',         'Followers list fetched successfully',
        'total_followers', (
            SELECT count(*)
            FROM public.follows
            WHERE profile_id = p_profile_id
            AND   is_active  = true
        ),
        'data', v_result
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
