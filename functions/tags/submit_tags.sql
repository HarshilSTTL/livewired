-- Function: submit_tags
-- Group: Tags
-- Endpoint: POST /rpc/submit_tags
-- Doc: docs/api/tags/submit_tags.md
-- ⚠️ Note: Response uses 'resultFlag' instead of 'status' (differs from all other SPs)

CREATE OR REPLACE FUNCTION submit_tags(
    p_user_id UUID,
    p_tag_ids BIGINT[]
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN

    -- ── Validate USER_id ──────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object(
            'resultFlag', false,
            'message',    'USER_id is required'
        );
    END IF;

    -- ── Validate TAGid array ───────────────────────────────────
    IF p_tag_ids IS NULL OR array_length(p_tag_ids, 1) IS NULL THEN
        RETURN json_build_object(
            'resultFlag', false,
            'message',    'TAGid array is required and must not be empty'
        );
    END IF;

    -- ── Check user exists in users table ──────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM public.users WHERE id = p_user_id
    ) THEN
        RETURN json_build_object(
            'resultFlag', false,
            'message',    'User not found'
        );
    END IF;

    -- ── Check all tag_ids exist in tags table ──────────────────
    IF EXISTS (
        SELECT 1 FROM UNNEST(p_tag_ids) AS t(tag_id)
        WHERE t.tag_id NOT IN (SELECT tag_id FROM public.tags)
    ) THEN
        RETURN json_build_object(
            'resultFlag', false,
            'message',    'One or more tag IDs are invalid'
        );
    END IF;

    -- ── Delete old interests for this user ─────────────────────
    DELETE FROM public.user_interests
    WHERE user_id = p_user_id;

    -- ── Insert new interests ───────────────────────────────────
    INSERT INTO public.user_interests (user_id, tag_id)
    SELECT p_user_id, UNNEST(p_tag_ids);

    -- ── Success response ───────────────────────────────────────
    RETURN json_build_object(
        'resultFlag', true,
        'message',    'Data Updated successfully'
    );

EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object(
        'resultFlag', false,
        'message',    SQLERRM
    );

END;
$$;
