# `get_profile_by_id` (v1 & v2)

## Version History

### v2 (Current — 2026-05-28)
- **Change:** Platforms ordered by ID (1→2→3→4: YouTube, Twitch, Kick, Rumble)
- **Reason:** Consistent platform display order on profile detail pages
- **Endpoint:** `POST /rpc/get_profile_by_id_v2`

### v1 (Deprecated)
- Returns platforms in database order (unordered)
- **Endpoint:** `POST /rpc/get_profile_by_id`

---

## V2 Function (Current)

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
            WHERE pt.profile_id = cp.id
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
            WHERE pt.profile_id = cp.id
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
