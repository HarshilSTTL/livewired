# `get_profiles`

```sql
-- Function: get_profiles
-- Group: Profile
-- Endpoint: POST /rpc/get_profiles
-- Requires: pg_trgm extension
-- Doc: docs/api/profiles/get_profiles.md

CREATE OR REPLACE FUNCTION get_profiles(
    p_keyword text DEFAULT null,
    p_limit   int  DEFAULT 20,
    p_offset  int  DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_keyword text;
    v_total   int;
BEGIN

    -- ── Normalise + clamp inputs ──────────────────────────────────────────────
    v_keyword := CASE
        WHEN p_keyword IS NULL OR trim(p_keyword) = '' THEN NULL
        ELSE trim(p_keyword)
    END;

    IF p_limit IS NULL OR p_limit < 1   THEN p_limit  := 20;  END IF;
    IF p_limit > 100                    THEN p_limit  := 100; END IF;
    IF p_offset IS NULL OR p_offset < 0 THEN p_offset := 0;   END IF;

    -- ── Total count (for pagination) ──────────────────────────────────────────
    SELECT COUNT(*)
    INTO   v_total
    FROM   creator_profiles cp
    WHERE  cp.status = 'active'
      AND  (
               v_keyword IS NULL
               OR cp.profile_name ILIKE '%' || v_keyword || '%'
               OR cp.username     ILIKE '%' || v_keyword || '%'
               OR word_similarity(v_keyword, cp.profile_name) > 0.3
               OR word_similarity(v_keyword, cp.username)     > 0.3
           );

    -- ── Result page ───────────────────────────────────────────────────────────
    RETURN json_build_object(
        'status', true,
        'data', json_build_object(
            'total',    v_total,
            'limit',    p_limit,
            'offset',   p_offset,
            'profiles', COALESCE((
                SELECT json_agg(row_to_json(t))
                FROM (
                    SELECT
                        cp.id            AS profile_id,
                        cp.profile_name,
                        cp.avatar,
                        CASE
                            WHEN cp.show_followers = true THEN (
                                SELECT COUNT(*)
                                FROM follows f
                                WHERE f.profile_id = cp.id
                                  AND f.is_active = true
                            )
                            ELSE NULL
                        END              AS followers,
                        (
                            SELECT COALESCE(
                                json_agg(json_build_object(
                                    'platform_id',   p.plat_id,
                                    'logo_url',      p.logo_url
                                )),
                                '[]'::json
                            )
                            FROM creator_platform_accounts cpa
                            JOIN platforms p ON p.plat_id = cpa.platform_id
                            WHERE cpa.profile_id = cp.id
                              AND cpa.is_deleted = false
                        )                AS platforms
                    FROM creator_profiles cp
                    WHERE cp.status = 'active'
                      AND (
                              v_keyword IS NULL
                              OR cp.profile_name ILIKE '%' || v_keyword || '%'
                              OR cp.username     ILIKE '%' || v_keyword || '%'
                              OR word_similarity(v_keyword, cp.profile_name) > 0.3
                              OR word_similarity(v_keyword, cp.username)     > 0.3
                          )
                    ORDER BY
                        CASE WHEN v_keyword IS NULL THEN 0
                             ELSE GREATEST(
                                 word_similarity(v_keyword, cp.profile_name),
                                 word_similarity(v_keyword, cp.username)
                             )
                        END DESC,
                        cp.created_at DESC
                    LIMIT  p_limit
                    OFFSET p_offset
                ) t
            ), '[]'::json)
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
