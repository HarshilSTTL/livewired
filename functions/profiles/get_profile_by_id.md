# `get_profile_by_id` (v1, v2 & v2.1)

## Version History

### v2.1 (Current — 2026-05-28)
- **Change:** Returns all 3 link groups (platforms, additional_links, custom_links) in separate response fields
- **Ordering:** Each group ordered by user drag-drop preferences from profile_link_preferences table
- **Type Field:** Each link includes type identifier ("platform", "additional_link", or "custom_link")
- **Order:** Platforms (1-4) → Additional Links (5+) → Custom Links (each in preference order)
- **Endpoint:** `POST /rpc/get_profile_by_id_v2_1`

### v2 (Previous — 2026-05-28)
- **Change:** Platforms ordered by ID (1→2→3→4: YouTube, Twitch, Kick, Rumble)
- **Reason:** Consistent platform display order on profile detail pages
- **Endpoint:** `POST /rpc/get_profile_by_id_v2`

### v1 (Deprecated)
- Returns platforms in database order (unordered)
- **Endpoint:** `POST /rpc/get_profile_by_id`

---

## V2.1 Function (Current)

```sql
-- Function: get_profile_by_id_v2_1
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_by_id_v2_1
-- Tables:   creator_profiles, creator_platform_accounts, profile_custom_links, profile_tags, follows, profile_link_preferences
-- Doc:      docs/api/profiles/get_profile_by_id.md
-- Version:  2.1 (2026-05-28)
-- Changes:  Returns all 3 link groups (platforms, additional_links, custom_links) in separate fields
--           Each group ordered by profile_link_preferences with fallback to default order
--           Each link includes type field for client-side classification
--
-- Purpose:  Returns full detail of a single profile by profile_id with links ordered by user preferences.

CREATE OR REPLACE FUNCTION get_profile_by_id_v2_1(
    p_profile_id uuid
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

    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    -- Verify profile exists and is not deleted
    SELECT id INTO v_profile_id
    FROM creator_profiles
    WHERE id     = p_profile_id
      AND status != 'deleted';

    IF v_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    SELECT json_build_object(
        'profile_id',      cp.id,
        'user_id',         cp.user_id,
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
            -- Main streaming platforms (IDs 1-4) ordered by profile_link_preferences
            SELECT COALESCE(json_agg(
                json_build_object(
                    'id',             cpa.id,
                    'platform_id',    cpa.platform_id,
                    'type',           'platform',
                    'platform_name',  p.plat_name,
                    'logo_url',       p.logo_url,
                    'channel_url',    cpa.channel_url,
                    'is_default',     cpa.is_default
                )
                ORDER BY sort_order ASC
            ), '[]'::json)
            FROM LATERAL (
                SELECT
                    cpa.id,
                    cpa.platform_id,
                    p.plat_name,
                    p.logo_url,
                    cpa.channel_url,
                    cpa.is_default,
                    COALESCE(
                        (SELECT array_position(plp.platform_ids_order, cpa.platform_id)
                         FROM profile_link_preferences plp
                         WHERE plp.profile_id = v_profile_id),
                        cpa.platform_id + 100
                    ) as sort_order
                FROM creator_platform_accounts cpa
                LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
                WHERE cpa.profile_id = v_profile_id
                  AND cpa.is_deleted = false
                  AND cpa.platform_id IN (1, 2, 3, 4)
            ) platform_list
        ),
        'additional_links', (
            -- Additional platform links (IDs 5+) ordered by profile_link_preferences
            SELECT COALESCE(json_agg(
                json_build_object(
                    'id',             cpa.id,
                    'platform_id',    cpa.platform_id,
                    'type',           'additional_link',
                    'platform_name',  p.plat_name,
                    'logo_url',       p.logo_url,
                    'channel_url',    cpa.channel_url,
                    'is_default',     cpa.is_default
                )
                ORDER BY sort_order ASC
            ), '[]'::json)
            FROM LATERAL (
                SELECT
                    cpa.id,
                    cpa.platform_id,
                    p.plat_name,
                    p.logo_url,
                    cpa.channel_url,
                    cpa.is_default,
                    COALESCE(
                        (SELECT array_position(plp.additional_ids_order, cpa.platform_id)
                         FROM profile_link_preferences plp
                         WHERE plp.profile_id = v_profile_id),
                        cpa.platform_id + 100
                    ) as sort_order
                FROM creator_platform_accounts cpa
                LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
                WHERE cpa.profile_id = v_profile_id
                  AND cpa.is_deleted = false
                  AND cpa.platform_id >= 5
            ) additional_list
        ),
        'custom_links', (
            -- Custom creator-defined links ordered by profile_link_preferences
            SELECT COALESCE(json_agg(
                json_build_object(
                    'id',             pcl.id,
                    'platform_id',    NULL,
                    'type',           'custom_link',
                    'platform_name',  pcl.platform_name,
                    'logo_url',       NULL,
                    'channel_url',    pcl.platform_url,
                    'is_default',     false
                )
                ORDER BY sort_order ASC
            ), '[]'::json)
            FROM LATERAL (
                SELECT
                    pcl.id,
                    pcl.platform_name,
                    pcl.platform_url,
                    COALESCE(
                        (SELECT array_position(plp.custom_ids_order, pcl.id)
                         FROM profile_link_preferences plp
                         WHERE plp.profile_id = v_profile_id),
                        9999
                    ) as sort_order
                FROM profile_custom_links pcl
                WHERE pcl.profile_id = v_profile_id
                  AND pcl.is_deleted = false
            ) custom_list
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
            WHERE pt.profile_id = v_profile_id
        ),
        'created_at',  cp.created_at,
        'updated_at',  cp.updated_at
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

---

## V2 Function (Previous)

```sql
-- Function: get_profile_by_id_v2
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_by_id_v2
-- Tables:   creator_profiles (SELECT), creator_platform_accounts (SELECT), profile_tags (SELECT), follows (COUNT)
-- Doc:      docs/api/profiles/get_profile_by_id.md
-- Version:  2.0 (2026-05-28)
-- Changes:  Platforms ordered by plat_id ASC (YouTube → Twitch → Kick → Rumble)
--
-- Purpose:  Returns full detail of a single profile by profile_id.
--           Used after the user selects a profile from the post-login picker.
--           Respects show_followers flag for follower count visibility.

CREATE OR REPLACE FUNCTION get_profile_by_id_v2(
    p_profile_id uuid
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

    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    -- Verify profile exists and is not deleted
    SELECT id INTO v_profile_id
    FROM creator_profiles
    WHERE id     = p_profile_id
      AND status != 'deleted';

    IF v_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    SELECT json_build_object(
        'profile_id',      cp.id,
        'user_id',         cp.user_id,
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
            WHERE pt.profile_id = v_profile_id
        ),
        'created_at',  cp.created_at,
        'updated_at',  cp.updated_at
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

---

## V1 Function (Deprecated)

```sql
-- Function: get_profile_by_id (V1 - Deprecated)
-- Platforms returned in database order (unordered)
-- Use get_profile_by_id_v2 for ordered platforms

CREATE OR REPLACE FUNCTION get_profile_by_id(
    p_profile_id uuid
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

    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    SELECT id INTO v_profile_id
    FROM creator_profiles
    WHERE id     = p_profile_id
      AND status != 'deleted';

    IF v_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    SELECT json_build_object(
        'profile_id',      cp.id,
        'user_id',         cp.user_id,
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
            WHERE pt.profile_id = v_profile_id
        ),
        'created_at',  cp.created_at,
        'updated_at',  cp.updated_at
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
