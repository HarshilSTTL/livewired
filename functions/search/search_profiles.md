# `search_profiles` (v1 & v2)

## Version History

### v2 (Current — 2026-05-28)
- **Change:** Platforms filtered to main streaming platforms only (IDs 1-4: YouTube, Twitch, Kick, Rumble)
- **Reason:** Search results show cleaner platform icons without custom/additional links
- **Breaking:** No — adds filtering to existing query
- **Endpoint:** `POST /rpc/search_profiles_v2`

### v1 (Deprecated — 2026-05-15 and earlier)
- Original version returning all platforms
- **Endpoint:** `POST /rpc/search_profiles` (kept for backwards compatibility)
- **Deprecation Note:** Use v2 for new implementations

---

## V2 Function (Current)

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
