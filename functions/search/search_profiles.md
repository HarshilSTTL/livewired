# `search_profiles` (v1, v2 & v2.1)

## Version History

### v2.1 (Current — 2026-05-28)
- **Change:** Returns all 3 link groups (platforms, additional_links, custom_links) in separate response fields
- **Ordering:** Each group ordered by user drag-drop preferences from profile_link_preferences table
- **Type Field:** Each link includes type identifier ("platform", "additional_link", or "custom_link")
- **Endpoint:** `POST /rpc/search_profiles_v2_1`

### v2 (Previous — 2026-05-28)
- **Change:** Platforms filtered to main streaming platforms only (IDs 1-4: YouTube, Twitch, Kick, Rumble)
- **Reason:** Search results show cleaner platform icons without custom/additional links
- **Endpoint:** `POST /rpc/search_profiles_v2`

### v1 (Deprecated — 2026-05-15 and earlier)
- Original version returning all platforms
- **Endpoint:** `POST /rpc/search_profiles` (kept for backwards compatibility)
- **Deprecation Note:** Use v2.1 for new implementations

---

## V2.1 Function (Current)

```sql
-- Function: search_profiles_v2_1
-- Group: Search
-- Endpoint: POST /rpc/search_profiles_v2_1
-- Requires: pg_trgm extension
-- Doc: docs/api/search/search_profiles.md
-- Version: 2.1 (2026-05-28)
-- Changes: Returns all 3 link groups (platforms, additional_links, custom_links) in separate fields
--          Each group ordered by user preferences with fallback to ID order
--          Each link includes type field for client-side classification

CREATE OR REPLACE FUNCTION search_profiles_v2_1(
    p_keyword text,
    p_limit   int DEFAULT 20
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profiles json;
    v_keyword  text;
BEGIN

    IF p_keyword IS NULL OR trim(p_keyword) = '' THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Search keyword is required'
        );
    END IF;

    IF length(trim(p_keyword)) < 2 THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Search keyword must be at least 2 characters'
        );
    END IF;

    v_keyword := trim(p_keyword);

    SELECT json_agg(result) INTO v_profiles
    FROM (
        SELECT json_build_object(
            'profile_id',    cp.id,
            'profile_name',  cp.profile_name,
            'avatar',        cp.avatar,
            'bio',           cp.bio,
            'followers', CASE
                             WHEN cp.show_followers = true THEN (
                                 SELECT count(*) FROM follows f
                                 WHERE f.profile_id = cp.id AND f.is_active = true
                             )
                             ELSE null
                         END,
            'platforms', (
                -- Main streaming platforms (IDs 1-4) ordered by profile_link_preferences
                SELECT coalesce(json_agg(
                    json_build_object(
                        'platform_id',   p.plat_id,
                        'type',          'platform',
                        'platform_name', p.plat_name,
                        'logo_url',      p.logo_url
                    )
                    ORDER BY sort_order ASC
                ), '[]'::json)
                FROM (
                    SELECT
                        p.plat_id,
                        p.plat_name,
                        p.logo_url,
                        COALESCE(
                            (SELECT array_position(plp.platform_ids_order, p.plat_id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = cp.id),
                            p.plat_id + 100
                        ) as sort_order
                    FROM creator_platform_accounts cpa
                    JOIN platforms p ON p.plat_id = cpa.platform_id
                    WHERE cpa.profile_id = cp.id
                      AND cpa.is_deleted = false
                      AND p.plat_id IN (1, 2, 3, 4)
                ) platform_list
            ),
            'additional_links', (
                -- Additional platform links (IDs 5+) ordered by profile_link_preferences
                SELECT coalesce(json_agg(
                    json_build_object(
                        'platform_id',   p.plat_id,
                        'type',          'additional_link',
                        'platform_name', p.plat_name,
                        'logo_url',      p.logo_url
                    )
                    ORDER BY sort_order ASC
                ), '[]'::json)
                FROM (
                    SELECT
                        p.plat_id,
                        p.plat_name,
                        p.logo_url,
                        COALESCE(
                            (SELECT array_position(plp.additional_ids_order, p.plat_id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = cp.id),
                            p.plat_id + 100
                        ) as sort_order
                    FROM creator_platform_accounts cpa
                    JOIN platforms p ON p.plat_id = cpa.platform_id
                    WHERE cpa.profile_id = cp.id
                      AND cpa.is_deleted = false
                      AND p.plat_id >= 5
                ) additional_list
            ),
            'custom_links', (
                -- Custom creator-defined links ordered by profile_link_preferences
                SELECT coalesce(json_agg(
                    json_build_object(
                        'platform_id',   NULL,
                        'type',          'custom_link',
                        'platform_name', pcl.platform_name,
                        'logo_url',      NULL
                    )
                    ORDER BY sort_order ASC
                ), '[]'::json)
                FROM (
                    SELECT
                        pcl.platform_name,
                        COALESCE(
                            (SELECT array_position(plp.custom_ids_order, pcl.id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = cp.id),
                            9999
                        ) as sort_order
                    FROM profile_custom_links pcl
                    WHERE pcl.profile_id = cp.id
                      AND pcl.is_deleted = false
                ) custom_list
            ),
            'match_score', GREATEST(
                word_similarity(v_keyword, cp.profile_name),
                word_similarity(v_keyword, coalesce(cp.bio, ''))
            )
        ) AS result,
        GREATEST(
            word_similarity(v_keyword, cp.profile_name),
            word_similarity(v_keyword, coalesce(cp.bio, ''))
        ) AS score
        FROM creator_profiles cp
        WHERE cp.status = 'active'
        AND (
            cp.profile_name ILIKE '%' || v_keyword || '%'
            OR cp.bio        ILIKE '%' || v_keyword || '%'
            OR word_similarity(v_keyword, cp.profile_name) > 0.3
            OR word_similarity(v_keyword, coalesce(cp.bio, '')) > 0.3
        )
        ORDER BY score DESC
        LIMIT p_limit
    ) sub;

    IF v_profiles IS NULL THEN
        RETURN json_build_object(
            'status',  true,
            'message', 'No profiles found',
            'data',    '[]'::json
        );
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Profiles fetched successfully',
        'data',    v_profiles
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
-- Function: search_profiles_v2
-- Group: Search
-- Endpoint: POST /rpc/search_profiles_v2
-- Requires: pg_trgm extension
-- Doc: docs/api/search/search_profiles.md
-- Version: 2.0 (2026-05-28)
-- Changes: Filters platforms to main streaming platforms (IDs 1-4)

CREATE OR REPLACE FUNCTION search_profiles_v2(
    p_keyword text,
    p_limit   int DEFAULT 20
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profiles json;
    v_keyword  text;
BEGIN

    IF p_keyword IS NULL OR trim(p_keyword) = '' THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Search keyword is required'
        );
    END IF;

    IF length(trim(p_keyword)) < 2 THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Search keyword must be at least 2 characters'
        );
    END IF;

    v_keyword := trim(p_keyword);

    SELECT json_agg(result) INTO v_profiles
    FROM (
        SELECT json_build_object(
            'profile_id',    cp.id,
            'profile_name',  cp.profile_name,
            'avatar',        cp.avatar,
            'bio',           cp.bio,
            'followers', CASE
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
                  AND p.plat_id IN (1, 2, 3, 4)
            ),
            'match_score', GREATEST(
                word_similarity(v_keyword, cp.profile_name),
                word_similarity(v_keyword, coalesce(cp.bio, ''))
            )
        ) AS result,
        GREATEST(
            word_similarity(v_keyword, cp.profile_name),
            word_similarity(v_keyword, coalesce(cp.bio, ''))
        ) AS score
        FROM creator_profiles cp
        WHERE cp.status = 'active'
        AND (
            cp.profile_name ILIKE '%' || v_keyword || '%'
            OR cp.bio        ILIKE '%' || v_keyword || '%'
            OR word_similarity(v_keyword, cp.profile_name) > 0.3
            OR word_similarity(v_keyword, coalesce(cp.bio, '')) > 0.3
        )
        ORDER BY score DESC
        LIMIT p_limit
    ) sub;

    IF v_profiles IS NULL THEN
        RETURN json_build_object(
            'status',  true,
            'message', 'No profiles found',
            'data',    '[]'::json
        );
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Profiles fetched successfully',
        'data',    v_profiles
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

## V1 Function (Deprecated — Kept for Backwards Compatibility)

```sql
-- Function: search_profiles (V1 - Deprecated)
-- Group: Search
-- Endpoint: POST /rpc/search_profiles
-- Requires: pg_trgm extension
-- Deprecation Date: 2026-05-28
-- Recommendation: Use search_profiles_v2 for new implementations
-- Note: Returns ALL platforms (no filtering)

CREATE OR REPLACE FUNCTION search_profiles(
    p_keyword text,
    p_limit   int DEFAULT 20
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profiles json;
    v_keyword  text;
BEGIN

    IF p_keyword IS NULL OR trim(p_keyword) = '' THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Search keyword is required'
        );
    END IF;

    IF length(trim(p_keyword)) < 2 THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Search keyword must be at least 2 characters'
        );
    END IF;

    v_keyword := trim(p_keyword);

    SELECT json_agg(result) INTO v_profiles
    FROM (
        SELECT json_build_object(
            'profile_id',    cp.id,
            'profile_name',  cp.profile_name,
            'avatar',        cp.avatar,
            'bio',           cp.bio,
            'followers', CASE
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
            'match_score', GREATEST(
                word_similarity(v_keyword, cp.profile_name),
                word_similarity(v_keyword, coalesce(cp.bio, ''))
            )
        ) AS result,
        GREATEST(
            word_similarity(v_keyword, cp.profile_name),
            word_similarity(v_keyword, coalesce(cp.bio, ''))
        ) AS score
        FROM creator_profiles cp
        WHERE cp.status = 'active'
        AND (
            cp.profile_name ILIKE '%' || v_keyword || '%'
            OR cp.bio        ILIKE '%' || v_keyword || '%'
            OR word_similarity(v_keyword, cp.profile_name) > 0.3
            OR word_similarity(v_keyword, coalesce(cp.bio, '')) > 0.3
        )
        ORDER BY score DESC
        LIMIT p_limit
    ) sub;

    IF v_profiles IS NULL THEN
        RETURN json_build_object(
            'status',  true,
            'message', 'No profiles found',
            'data',    '[]'::json
        );
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Profiles fetched successfully',
        'data',    v_profiles
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
