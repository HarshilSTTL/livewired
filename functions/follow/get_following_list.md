# `get_following_list`

```sql
-- Function: get_following_list
-- Group: Follow
-- Endpoint: POST /rpc/get_following_list
-- Doc: docs/api/follow/get_following_list.md

CREATE OR REPLACE FUNCTION get_following_list(
    p_user_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN
    -- Validate user_id
    IF p_user_id IS NULL THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'user_id is required'
        );
    END IF;
    -- Check user exists
    IF NOT EXISTS (
        SELECT 1 FROM public.users WHERE id = p_user_id
    ) THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'User not found'
        );
    END IF;
    -- Get all active following profiles
    SELECT json_agg(
        json_build_object(
            'profile_id',    cp.id,
            'profile_name',  cp.profile_name,
            'avatar',        cp.avatar,
            'bio',           cp.bio,
            'status',        cp.status,
            'followers',     (
                SELECT count(*)
                FROM follows f2
                WHERE f2.profile_id = cp.id
                AND f2.is_active = true
            ),
            'platforms', (
                SELECT coalesce(
                    json_agg(
                        json_build_object(
                            'platform_id',   p.plat_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url
                        )
                    ),
                    '[]'::json
                )
                FROM creator_platform_accounts cpa
                JOIN platforms p ON p.plat_id = cpa.platform_id
                WHERE cpa.profile_id = cp.id
                  AND cpa.is_deleted = false
            ),
            'followed_at',   f.created_at
        )
        ORDER BY f.created_at DESC
    )
    INTO v_result
    FROM public.follows f
    JOIN public.creator_profiles cp ON cp.id = f.profile_id
    WHERE f.user_id   = p_user_id
    AND   f.is_active = true
    AND   cp.status   = 'active';
    -- No following found
    IF v_result IS NULL THEN
        RETURN json_build_object(
            'status',  true,
            'message', 'No following found',
            'data',    '[]'::json
        );
    END IF;
    RETURN json_build_object(
        'status',  true,
        'message', 'Following list fetched successfully',
        'data',    v_result
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
