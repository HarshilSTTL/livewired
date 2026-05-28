# `get_profile_by_userid` (v1, v2 & v2.1)

## Version History

### v2.1 (Current — 2026-05-28)
- **Change:** Platforms, additional links, and custom links ordered by user preferences
- **Reason:** Respects user's drag-drop reordering across all profiles
- **Endpoint:** `POST /rpc/get_profile_by_userid_v2_1`

### v2 (Previous — 2026-05-28)
- **Change:** Platforms ordered by ID (1→2→3→4)
- **Reason:** Consistent platform display order on profile detail pages
- **Endpoint:** `POST /rpc/get_profile_by_userid_v2`

### v1 (Deprecated)
- Returns platforms in database order (unordered)
- **Endpoint:** `POST /rpc/get_profile_by_userid`

---

## V2.1 Function (Current)

```sql
-- Function: get_profile_by_userid_v2_1
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_by_userid_v2_1
-- Tables:   creator_profiles, creator_platform_accounts, profile_custom_links, profile_tags, follows, profile_link_preferences
-- Doc:      docs/api/profiles/get_profile_by_userid.md
-- Version:  2.1 (2026-05-28)
-- Changes:  Uses profile_link_preferences for custom ordering of platforms, additional links, and custom links
--
-- Purpose:  Returns ALL profiles belonging to a given user_id with links ordered by user preferences.
--           Used for the "Select Profile" dropdown and profile switcher in the app.
--           Default profile is always first (ORDER BY is_default DESC).

CREATE OR REPLACE FUNCTION get_profile_by_userid_v2_1(
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
                -- Returns platforms, additional links, and custom links in preference order
                SELECT coalesce(json_agg(link_obj ORDER BY sort_order), '[]'::json)
                FROM (
                    -- Platforms (IDs 1-4) ordered by preferences
                    SELECT
                        json_build_object(
                            'platform_id',   cpa.platform_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url,
                            'channel_url',   cpa.channel_url,
                            'is_default',    cpa.is_default
                        ) as link_obj,
                        COALESCE(
                            (SELECT array_position(plp.platform_ids_order, cpa.platform_id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = cp.id),
                            9999
                        ) as sort_order,
                        1 as group_priority
                    FROM creator_platform_accounts cpa
                    LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
                    WHERE cpa.profile_id = cp.id
                      AND cpa.is_deleted = false
                      AND cpa.platform_id IN (1, 2, 3, 4)
                    
                    UNION ALL
                    
                    -- Additional links (IDs 5+) ordered by preferences
                    SELECT
                        json_build_object(
                            'platform_id',   cpa.platform_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url,
                            'channel_url',   cpa.channel_url,
                            'is_default',    cpa.is_default
                        ) as link_obj,
                        COALESCE(
                            (SELECT array_position(plp.additional_ids_order, cpa.platform_id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = cp.id),
                            9999
                        ) as sort_order,
                        2 as group_priority
                    FROM creator_platform_accounts cpa
                    LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
                    WHERE cpa.profile_id = cp.id
                      AND cpa.is_deleted = false
                      AND cpa.platform_id >= 5
                    
                    UNION ALL
                    
                    -- Custom links ordered by preferences
                    SELECT
                        json_build_object(
                            'platform_id',   NULL,
                            'platform_name', pcl.platform_name,
                            'logo_url',      NULL,
                            'channel_url',   pcl.platform_url,
                            'is_default',    false
                        ) as link_obj,
                        COALESCE(
                            (SELECT array_position(plp.custom_ids_order, pcl.id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = cp.id),
                            9999
                        ) as sort_order,
                        3 as group_priority
                    FROM profile_custom_links pcl
                    WHERE pcl.profile_id = cp.id
                      AND pcl.is_deleted = false
                ) all_links
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

---

## V2 Function (Previous)

```sql
-- Function: get_profile_by_userid_v2
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_by_userid_v2
-- Tables:   creator_profiles (SELECT), creator_platform_accounts (SELECT), profile_tags (SELECT), follows (COUNT)
-- Doc:      docs/api/profiles/get_profile_by_userid.md
-- Version:  2.0 (2026-05-28)
-- Changes:  Platforms ordered by plat_id ASC
--
-- Purpose:  Returns ALL profiles belonging to a given user_id.
--           Used for the "Select Profile" dropdown and profile switcher in the app.
--           Returns all statuses (active, suspended, deleted) so the creator sees their full list.
--           Default profile is always first (ORDER BY is_default DESC).

CREATE OR REPLACE FUNCTION get_profile_by_userid_v2(
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
                        ORDER BY p.plat_id ASC
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

---

## V1 Function (Deprecated)

```sql
-- Function: get_profile_by_userid (V1 - Deprecated)
-- Platforms returned in database order (unordered)
-- Use get_profile_by_userid_v2 for ordered platforms

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
