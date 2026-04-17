# `get_suggested_profiles`

```sql
-- Function: get_suggested_profiles
-- Group: Profile
-- Endpoint: POST /rpc/get_suggested_profiles
-- Doc: docs/api/profiles/get_suggested_profiles.md

CREATE OR REPLACE FUNCTION get_suggested_profiles(
    p_user_id uuid,
    p_limit   int DEFAULT 20,
    p_offset  int DEFAULT 0
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_total int;
BEGIN

    -- ── Validate ──────────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'p_user_id is required'
        );
    END IF;

    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'User not found'
        );
    END IF;

    -- ── Clamp inputs ──────────────────────────────────────────────────────────
    IF p_limit IS NULL OR p_limit < 1   THEN p_limit  := 20;  END IF;
    IF p_limit > 100                    THEN p_limit  := 100; END IF;
    IF p_offset IS NULL OR p_offset < 0 THEN p_offset := 0;   END IF;

    -- ── Total eligible profiles (for pagination) ──────────────────────────────
    SELECT COUNT(DISTINCT cp.id)
    INTO   v_total
    FROM   creator_profiles cp
    WHERE  cp.status = 'active'
      AND  cp.user_id != p_user_id
      AND  cp.id NOT IN (
               SELECT profile_id FROM follows
               WHERE  user_id = p_user_id AND is_active = true
           );

    -- ── Scored suggestions ────────────────────────────────────────────────────
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
                                FROM   follows f
                                WHERE  f.profile_id = cp.id
                                  AND  f.is_active = true
                            )
                            ELSE NULL
                        END              AS followers,
                        (
                            SELECT COALESCE(
                                json_agg(json_build_object(
                                    'platform_id', p.plat_id,
                                    'logo_url',    p.logo_url
                                )),
                                '[]'::json
                            )
                            FROM creator_platform_accounts cpa
                            JOIN platforms p ON p.plat_id = cpa.platform_id
                            WHERE cpa.profile_id = cp.id
                              AND cpa.is_deleted = false
                        )                AS platforms,
                        (
                            SELECT COALESCE(
                                json_agg(json_build_object(
                                    'tag_id',   tg.tag_id,
                                    'tag_name', tg.tag_name
                                )),
                                '[]'::json
                            )
                            FROM profile_tags pt
                            JOIN tags tg ON tg.tag_id = pt.tag_id
                            WHERE pt.profile_id = cp.id
                              AND pt.tag_id IS NOT NULL
                        )                AS tags,
                        -- ── Match score: platform overlaps + tag overlaps ────
                        (
                            (
                                SELECT COUNT(*)
                                FROM   creator_platform_accounts cpa
                                WHERE  cpa.profile_id = cp.id
                                  AND  cpa.is_deleted = false
                                  AND  cpa.platform_id::bigint IN (
                                           SELECT platform_id
                                           FROM   user_preferred_platforms
                                           WHERE  user_id = p_user_id
                                       )
                            )
                            +
                            (
                                SELECT COUNT(*)
                                FROM   profile_tags pt
                                WHERE  pt.profile_id = cp.id
                                  AND  pt.tag_id IS NOT NULL
                                  AND  pt.tag_id IN (
                                           SELECT tag_id
                                           FROM   user_interests
                                           WHERE  user_id = p_user_id
                                       )
                            )
                        )                AS match_score
                    FROM creator_profiles cp
                    WHERE cp.status = 'active'
                      AND cp.user_id != p_user_id
                      AND cp.id NOT IN (
                              SELECT profile_id FROM follows
                              WHERE  user_id = p_user_id AND is_active = true
                          )
                    ORDER BY
                        match_score DESC,
                        (
                            SELECT COUNT(*) FROM follows f
                            WHERE f.profile_id = cp.id AND f.is_active = true
                        ) DESC
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
