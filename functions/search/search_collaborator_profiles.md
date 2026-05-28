# `search_collaborator_profiles` (v1, v2 & v2.1)

## Version History

### v2.1 (Current — 2026-05-28)
- **Change:** Platforms ordered by user preferences from profile_link_preferences
- **Reason:** Respects user's drag-drop reordering in collaborator picker
- **Endpoint:** `POST /rpc/search_collaborator_profiles_v2_1`

### v2 (Previous — 2026-05-28)
- **Change:** Platforms filtered to main streaming platforms only (IDs 1-4)
- **Reason:** Consistent with search_profiles_v2; cleaner UX for collaborator picker
- **Endpoint:** `POST /rpc/search_collaborator_profiles_v2`

### v1 (Deprecated — 2026-05-15 and earlier)
- Returns all platforms without filtering
- **Endpoint:** `POST /rpc/search_collaborator_profiles` (kept for backwards compatibility)

---

## V2.1 Function (Current)

```sql
-- Function: search_collaborator_profiles_v2_1
-- Group:    Search
-- Endpoint: POST /rpc/search_collaborator_profiles_v2_1
-- Requires: pg_trgm extension
-- Doc:      docs/api/search/search_collaborator_profiles.md
-- Version:  2.1 (2026-05-28)
-- Changes:  Platforms ordered by user preferences (profile_link_preferences)
--
-- Searches active creator profiles for use in the collaborator picker.
-- Always excludes p_exclude_profile_id (the creating/inviting profile).
-- If p_event_id is provided, also excludes profiles already invited
-- (pending or accepted, non-deleted) to that event.

CREATE OR REPLACE FUNCTION search_collaborator_profiles_v2_1(
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
                -- Platforms ordered by user preferences
                SELECT coalesce(
                    json_agg(
                        json_build_object(
                            'platform_id',   p.plat_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url
                        )
                        ORDER BY sort_order ASC
                    ),
                    '[]'::json
                )
                FROM (
                    SELECT
                        p.plat_id,
                        p.plat_name,
                        p.logo_url,
                        COALESCE(
                            (SELECT array_position(plp.platform_ids_order, p.plat_id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = cp.id),
                            p.plat_id + 100  -- fallback to ID order if no preferences
                        ) as sort_order
                    FROM creator_platform_accounts cpa
                    JOIN platforms p ON p.plat_id = cpa.platform_id
                    WHERE cpa.profile_id = cp.id
                      AND cpa.is_deleted = false
                      AND p.plat_id IN (1, 2, 3, 4)
                ) platform_list
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

## V2 Function (Previous)

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
