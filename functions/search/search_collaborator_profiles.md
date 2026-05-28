# `search_collaborator_profiles` (v1 & v2)

## Version History

### v2 (Current — 2026-05-28)
- **Change:** Platforms filtered to main streaming platforms only (IDs 1-4)
- **Reason:** Consistent with search_profiles_v2; cleaner UX for collaborator picker
- **Endpoint:** `POST /rpc/search_collaborator_profiles_v2`

### v1 (Deprecated — 2026-05-15 and earlier)
- Returns all platforms without filtering
- **Endpoint:** `POST /rpc/search_collaborator_profiles` (kept for backwards compatibility)

---

## V2 Function (Current)

```sql
-- Function: search_collaborator_profiles_v2
-- Group:    Search
-- Endpoint: POST /rpc/search_collaborator_profiles_v2
-- Requires: pg_trgm extension
-- Doc:      docs/api/search/search_collaborator_profiles.md
-- Version:  2.0 (2026-05-28)
-- Changes:  Filters platforms to main streaming platforms (IDs 1-4)
--
-- Searches active creator profiles for use in the collaborator picker.
-- Always excludes p_exclude_profile_id (the creating/inviting profile).
-- If p_event_id is provided, also excludes profiles already invited
-- (pending or accepted, non-deleted) to that event.

CREATE OR REPLACE FUNCTION search_collaborator_profiles_v2(
    p_keyword            text,
    p_exclude_profile_id uuid,
    p_event_id           uuid    DEFAULT null,
    p_limit              int     DEFAULT 20
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

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_keyword IS NULL OR trim(p_keyword) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Search keyword is required');
    END IF;

    IF length(trim(p_keyword)) < 2 THEN
        RETURN json_build_object('status', false, 'message', 'Search keyword must be at least 2 characters');
    END IF;

    IF p_exclude_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_exclude_profile_id is required');
    END IF;

    v_keyword := trim(p_keyword);

    SELECT json_agg(result) INTO v_profiles
    FROM (
        SELECT json_build_object(
            'profile_id',   cp.id,
            'profile_name', cp.profile_name,
            'avatar',       cp.avatar,
            'bio',          cp.bio,
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
          -- Always exclude the creating/inviting profile
          AND cp.id != p_exclude_profile_id
          -- If event_id provided: exclude already-invited profiles (pending/accepted, non-deleted)
          AND (
              p_event_id IS NULL
              OR cp.id NOT IN (
                  SELECT ec.profile_id
                  FROM event_collaborators ec
                  WHERE ec.event_id   = p_event_id
                    AND ec.status     IN ('pending', 'accepted')
                    AND ec.is_deleted = false
              )
          )
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
        RETURN json_build_object('status', true, 'message', 'No profiles found', 'data', '[]'::json);
    END IF;

    RETURN json_build_object('status', true, 'message', 'Profiles fetched successfully', 'data', v_profiles);

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```

---

## V1 Function (Deprecated)

```sql
-- Function: search_collaborator_profiles (V1 - Deprecated)
-- Returns all platforms (no filtering)
-- Use search_collaborator_profiles_v2 for new implementations

CREATE OR REPLACE FUNCTION search_collaborator_profiles(
    p_keyword            text,
    p_exclude_profile_id uuid,
    p_event_id           uuid    DEFAULT null,
    p_limit              int     DEFAULT 20
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
        RETURN json_build_object('status', false, 'message', 'Search keyword is required');
    END IF;

    IF length(trim(p_keyword)) < 2 THEN
        RETURN json_build_object('status', false, 'message', 'Search keyword must be at least 2 characters');
    END IF;

    IF p_exclude_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_exclude_profile_id is required');
    END IF;

    v_keyword := trim(p_keyword);

    SELECT json_agg(result) INTO v_profiles
    FROM (
        SELECT json_build_object(
            'profile_id',   cp.id,
            'profile_name', cp.profile_name,
            'avatar',       cp.avatar,
            'bio',          cp.bio,
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
          AND cp.id != p_exclude_profile_id
          AND (
              p_event_id IS NULL
              OR cp.id NOT IN (
                  SELECT ec.profile_id
                  FROM event_collaborators ec
                  WHERE ec.event_id   = p_event_id
                    AND ec.status     IN ('pending', 'accepted')
                    AND ec.is_deleted = false
              )
          )
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
        RETURN json_build_object('status', true, 'message', 'No profiles found', 'data', '[]'::json);
    END IF;

    RETURN json_build_object('status', true, 'message', 'Profiles fetched successfully', 'data', v_profiles);

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```
