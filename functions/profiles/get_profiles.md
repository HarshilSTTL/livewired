# `get_profiles`

```sql
-- Function: get_profiles
-- Group: Profile
-- Endpoint: POST /rpc/get_profiles
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
        ELSE lower(trim(p_keyword))
    END;

    IF p_limit IS NULL OR p_limit < 1  THEN p_limit  := 20;  END IF;
    IF p_limit > 100                   THEN p_limit  := 100; END IF;
    IF p_offset IS NULL OR p_offset < 0 THEN p_offset := 0;  END IF;

    -- ── Total count (for pagination) ──────────────────────────────────────────
    SELECT COUNT(*)
    INTO   v_total
    FROM   creator_profiles cp
    WHERE  cp.status = 'active'
      AND  (
               v_keyword IS NULL
               OR lower(cp.profile_name) ILIKE '%' || v_keyword || '%'
               OR lower(cp.username)     ILIKE '%' || v_keyword || '%'
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
                        cp.user_id,
                        cp.profile_name,
                        cp.username,
                        cp.avatar,
                        cp.bio,
                        cp.status,
                        cp.show_followers,
                        CASE
                            WHEN cp.show_followers THEN
                                (SELECT COUNT(*)
                                 FROM follows f
                                 WHERE f.profile_id = cp.id
                                   AND f.is_active = true)
                            ELSE NULL
                        END              AS followers,
                        (
                            SELECT COALESCE(
                                json_agg(json_build_object(
                                    'platform_id',   p.plat_id,
                                    'platform_name', p.plat_name,
                                    'logo_url',      p.logo_url,
                                    'channel_url',   cpa.channel_url
                                )),
                                '[]'::json
                            )
                            FROM creator_platform_accounts cpa
                            JOIN platforms p ON p.plat_id = cpa.platform_id
                            WHERE cpa.profile_id = cp.id
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
                        )                AS tags,
                        cp.created_at
                    FROM creator_profiles cp
                    WHERE cp.status = 'active'
                      AND (
                              v_keyword IS NULL
                              OR lower(cp.profile_name) ILIKE '%' || v_keyword || '%'
                              OR lower(cp.username)     ILIKE '%' || v_keyword || '%'
                          )
                    ORDER BY cp.created_at DESC
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
