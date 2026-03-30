-- Function: unfollow_creator
-- Group: Follow
-- Endpoint: POST /rpc/unfollow_creator
-- Doc: docs/api/follow/unfollow_creator.md

CREATE OR REPLACE FUNCTION unfollow_creator(
    p_user_id    UUID,
    p_profile_id UUID
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Validate user_id
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'user_id is required');
    END IF;
    -- Validate profile_id
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'profile_id is required');
    END IF;
    -- Check user exists
    IF NOT EXISTS (
        SELECT 1 FROM public.users WHERE id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;
    -- Check if actually following
    IF NOT EXISTS (
        SELECT 1 FROM public.follows
        WHERE user_id    = p_user_id
        AND   profile_id = p_profile_id
        AND   is_active  = true
    ) THEN
        RETURN json_build_object('status', false, 'message', 'You are not following this creator');
    END IF;
    -- Soft delete → unfollow
    UPDATE public.follows
    SET is_active     = false,
        unfollowed_at = now()
    WHERE user_id    = p_user_id
    AND   profile_id = p_profile_id;
    RETURN json_build_object('status', true, 'message', 'Creator unfollowed successfully');
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
