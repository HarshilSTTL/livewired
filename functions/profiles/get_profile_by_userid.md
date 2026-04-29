# `get_profile_by_userid`

```sql
-- Function: get_profile_by_userid
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_by_userid
-- Tables:   creator_profiles (SELECT), creator_platform_accounts (SELECT), profile_tags (SELECT), follows (COUNT)
-- Doc:      docs/api/profiles/get_profile_by_userid.md
--
-- Purpose:  Returns ALL profiles belonging to a given user_id.
--           Used for the "Select Profile" dropdown and profile switcher in the app.
--           Returns all statuses (active, suspended, deleted) so the creator sees their full list.
--           Default profile is always first (ORDER BY is_default DESC).

CREATE OR REPLACE FUNCTION get_profile_by_userid(
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

    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND is_deleted = false) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    SELECT json_agg(
        json_build_object(
            'profile_id',      cp.id,
            'profile_name',    cp.profile_name,
            'username',        cp.username,
            'avatar',          cp.avatar,
            'bio',             cp.bio,
            'is_default',      cp.is_default,
            'status',          cp.status,
            'show_followers',     cp.show_followers,
            'twitch_by_default',  cp.twitch_by_default,
            'kick_by_default',    cp.kick_by_default,
            'followers',          CASE
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
                  AND cpa.is_deleted = false
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
        ORDER BY cp.is_default DESC, cp.created_at ASC
    )
    INTO v_result
    FROM creator_profiles cp
    WHERE cp.user_id = p_user_id
      AND cp.status != 'deleted';

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
