-- Function: follow_creator
-- Group: Follow
-- Endpoint: POST /rpc/follow_creator
-- Doc: docs/api/follow/follow_creator.md
-- ⚠️ Note: p_device_ip is referenced in body but NOT in function signature

CREATE OR REPLACE FUNCTION follow_creator(
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
    -- Check creator profile exists and is active
    IF NOT EXISTS (
        SELECT 1 FROM public.creator_profiles
        WHERE id = p_profile_id AND status = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Creator profile not found or inactive');
    END IF;
    -- Check user is not following their own profile
    IF EXISTS (
        SELECT 1 FROM public.creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'You cannot follow your own profile');
    END IF;
    -- Check if row already exists
    IF EXISTS (
        SELECT 1 FROM public.follows
        WHERE user_id = p_user_id AND profile_id = p_profile_id
    ) THEN
        -- If inactive → re-follow
        IF EXISTS (
            SELECT 1 FROM public.follows
            WHERE user_id    = p_user_id
            AND   profile_id = p_profile_id
            AND   is_active  = false
        ) THEN
            UPDATE public.follows
            SET is_active     = true,
                unfollowed_at = null,
                created_at    = now()
            WHERE user_id    = p_user_id
            AND   profile_id = p_profile_id;
            RETURN json_build_object('status', true, 'message', 'Creator followed successfully');
        END IF;
        -- If active → already following
        RETURN json_build_object('status', false, 'message', 'You are already following this creator');
    END IF;
    -- Fresh follow → insert
    INSERT INTO public.follows (user_id, profile_id, is_active, created_at)
    VALUES (p_user_id, p_profile_id, true, now());
    -- Update device ip
    IF p_device_ip IS NOT NULL THEN
        UPDATE public.users
        SET updated_device_ip = p_device_ip,
            updated_at        = now()
        WHERE id = p_user_id;
    END IF;
    RETURN json_build_object('status', true, 'message', 'Creator followed successfully');
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
