-- Function: search_events
-- Group: Search
-- Endpoint: POST /rpc/search_events
-- Requires: pg_trgm extension
-- Doc: docs/api/search/search_events.md

CREATE OR REPLACE FUNCTION search_events(
    p_keyword text,
    p_limit   int DEFAULT 20
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_events  json;
    v_keyword text;
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

    SELECT json_agg(result) INTO v_events
    FROM (
        SELECT json_build_object(
            'event_id',      e.event_id,
            'event_title',   e.title,
            'description',   e.description,
            'event_date',    e.event_date,
            'event_time',    e.event_time,
            'livestream',    e.livestream,
            'is_recurring',  e.is_recurring,
            'profile_name',  cp.profile_name,
            'username',      cp.username,
            'avatar_url',    cp.avatar_url,
            'followers',     (
                SELECT count(*) FROM follows f
                WHERE f.profile_id = cp.id AND f.is_active = true
            ),
            'streaming', (
                SELECT coalesce(
                    json_agg(
                        json_build_object(
                            'platform_id',   p.plat_id,
                            'platform_name', p.plat_name,
                            'logo_url',      p.logo_url,
                            'streaming_url', ep.stream_url
                        )
                    ),
                    '[]'::json
                )
                FROM event_platforms ep
                LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
                WHERE ep.event_id = e.event_id
            ),
            'match_score', GREATEST(
                word_similarity(v_keyword, e.title),
                word_similarity(v_keyword, coalesce(e.description, ''))
            )
        ) AS result,
        GREATEST(
            word_similarity(v_keyword, e.title),
            word_similarity(v_keyword, coalesce(e.description, ''))
        ) AS score
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE cp.status = 'active'
        AND (
            e.title          ILIKE '%' || v_keyword || '%'
            OR e.description ILIKE '%' || v_keyword || '%'
            OR word_similarity(v_keyword, e.title) > 0.3
            OR word_similarity(v_keyword, coalesce(e.description, '')) > 0.3
        )
        ORDER BY score DESC, e.event_date ASC
        LIMIT p_limit
    ) sub;

    IF v_events IS NULL THEN
        RETURN json_build_object(
            'status',  true,
            'message', 'No events found',
            'data',    '[]'::json
        );
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Events fetched successfully',
        'data',    v_events
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
