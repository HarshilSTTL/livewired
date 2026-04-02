# `get_profile_by_username`

```sql
-- Function: get_profile_by_username
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_by_username
-- Tables:   creator_profiles (SELECT), creator_platform_accounts (SELECT), profile_tags (SELECT), follows (COUNT)
-- Doc:      docs/api/profiles/get_profile_by_username.md
--
-- Purpose:  Returns a single profile by its unique username.
--           Used for public profile view. Respects show_followers flag.
--           Returns any status so UI can handle suspended/deleted cases.

CREATE OR REPLACE FUNCTION get_profile_by_username(
    p_username text
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile    json;
    v_profile_id uuid;
BEGIN

    IF p_username IS NULL OR trim(p_username) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Username is required');
    END IF;

    SELECT id INTO v_profile_id
    FROM creator_profiles
    WHERE username = p_username
      AND status  != 'deleted';

    IF v_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    SELECT json_build_object(
        'profile_id',      cp.id,
        'profile_name',    cp.profile_name,
        'username',        cp.username,
        'avatar',          cp.avatar,
        'bio',             cp.bio,
        'status',          cp.status,
        'show_followers',  cp.show_followers,
        'followers',       CASE
                               WHEN cp.show_followers = true THEN (
                                   SELECT count(*) FROM follows f
                                   WHERE f.profile_id = cp.id AND f.is_active = true
                               )
                               ELSE null
                           END,
        'platforms', (
            SELECT coalesce(
                json_agg(
                    json_build_object(
                        'platform_id',   cpa.platform_id,
                        'platform_name', p.plat_name,
                        'logo_url',      p.logo_url,
                        'channel_url',   cpa.channel_url,
                        'is_default',    cpa.is_default
                    )
                ),
                '[]'::json
            )
            FROM creator_platform_accounts cpa
            LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
            WHERE cpa.profile_id = cp.id
        ),
        'tags', (
            SELECT coalesce(
                json_agg(
                    json_build_object(
                        'tag_id',   t.tag_id,
                        'tag_name', t.tag_name
                    )
                ),
                '[]'::json
            )
            FROM profile_tags pt
            LEFT JOIN tags t ON t.tag_id = pt.tag_id
            WHERE pt.profile_id = cp.id
        )
    )
    INTO v_profile
    FROM creator_profiles cp
    WHERE cp.id = v_profile_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'Profile fetched successfully',
        'data',    v_profile
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
