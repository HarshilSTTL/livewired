# `update_event`

```sql
-- Function: update_event
-- Group: Events
-- Endpoint: POST /rpc/update_event
-- Doc: docs/api/events/update_event.md
-- COALESCE pattern — only fields that are passed (non-null) are updated.
-- p_platforms: null = don't touch | [] = clear all | [...] = replace all
-- p_recurring_days: if passed, recurring rule is updated + all child rows are regenerated

CREATE OR REPLACE FUNCTION update_event(
    p_event_id             uuid,
    p_user_id              uuid,
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_platforms            jsonb    DEFAULT NULL,
    -- Recurring fields (pass any to trigger recurring update + child regeneration)
    p_recurring_days       text[]   DEFAULT NULL,
    p_recurring_type       text     DEFAULT NULL,
    p_recurring_interval   int      DEFAULT NULL,
    p_recurring_start_date date     DEFAULT NULL,
    p_recurring_end_date   date     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_platform      jsonb;

    -- For recurring child regeneration
    v_profile_id    uuid;
    v_title         text;
    v_description   text;
    v_event_time    time;
    v_event_tz      text;
    v_livestream    boolean;
    v_video         boolean;

    v_rec_days      text[];
    v_rec_type      text;
    v_rec_interval  int;
    v_rec_start     date;
    v_rec_end       date;
    v_safe_end      date;

    -- Occurrence generation variables
    v_day_name      text;
    v_dow_target    int;
    v_dow_start     int;
    v_days_ahead    int;
    v_first_occ     date;
    v_occ_date      date;
    v_month_start   date;
    v_month_end     date;
    v_dow_month_end int;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── Ownership check ───────────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── Platform validation ───────────────────────────────────────────────────
    IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
            WHERE NOT EXISTS (
                SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint
            )
        ) THEN
            RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
        END IF;

        IF EXISTS (
            SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
            WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
        ) THEN
            RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
        END IF;
    END IF;

    -- ── Recurring validation (only when recurring params are being updated) ───
    IF p_recurring_days IS NOT NULL THEN

        IF array_length(p_recurring_days, 1) = 0 THEN
            RETURN json_build_object('status', false, 'message', 'Recurring days cannot be empty');
        END IF;

        IF EXISTS (
            SELECT 1 FROM unnest(p_recurring_days) AS d(day)
            WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
        ) THEN
            RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
        END IF;

        -- Fetch current recurring rule to fill COALESCE gaps
        SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
        INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
        FROM event_recurring WHERE event_id = p_event_id;

        -- Apply incoming values over existing
        v_rec_days     := p_recurring_days;
        v_rec_type     := COALESCE(p_recurring_type,         v_rec_type);
        v_rec_interval := COALESCE(p_recurring_interval,     v_rec_interval);
        v_rec_start    := COALESCE(p_recurring_start_date,   v_rec_start);
        v_rec_end      := COALESCE(p_recurring_end_date,     v_rec_end);

        IF v_rec_type NOT IN ('weekly', 'first', 'last') THEN
            RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
        END IF;

        IF v_rec_type = 'weekly' THEN
            IF v_rec_interval IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
            END IF;
            IF v_rec_interval < 1 OR v_rec_interval > 12 THEN
                RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
            END IF;
        ELSE
            IF v_rec_interval IS NOT NULL THEN
                RETURN json_build_object('status', false, 'message', 'recurring_interval must be null for first/last type');
            END IF;
        END IF;

        IF v_rec_start IS NULL THEN
            RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
        END IF;

        IF v_rec_end IS NOT NULL AND v_rec_end <= v_rec_start THEN
            RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
        END IF;

    END IF;

    -- ── Update event_mst ──────────────────────────────────────────────────────
    UPDATE event_mst
    SET title          = COALESCE(p_title,       title),
        description    = COALESCE(p_description, description),
        event_date     = COALESCE(p_event_date,  event_date),
        event_time     = COALESCE(p_event_time,  event_time),
        event_timezone = COALESCE(p_timezone,    event_timezone),
        livestream     = COALESCE(p_livestream,  livestream),
        video          = COALESCE(p_video,       video),
        updated_at     = now()
    WHERE event_id     = p_event_id;

    -- ── Update platforms ──────────────────────────────────────────────────────
    IF p_platforms IS NOT NULL THEN
        DELETE FROM event_platforms WHERE event_id = p_event_id;

        IF jsonb_array_length(p_platforms) > 0 THEN
            FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
            LOOP
                INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                VALUES (
                    gen_random_uuid(),
                    p_event_id,
                    (v_platform->>'platform_id')::int4,
                    v_platform->>'stream_url',
                    now()
                );
            END LOOP;
        END IF;
    END IF;

    -- ── Update recurring rule + regenerate child rows ─────────────────────────
    IF p_recurring_days IS NOT NULL THEN

        -- Update event_recurring row
        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end
        WHERE event_id = p_event_id;

        -- Delete all existing child occurrence rows
        DELETE FROM event_mst WHERE parent_event_id = p_event_id;

        -- Fetch parent row values needed for child generation
        SELECT profile_id, title, description, event_time, event_timezone, livestream, video
        INTO v_profile_id, v_title, v_description, v_event_time, v_event_tz, v_livestream, v_video
        FROM event_mst WHERE event_id = p_event_id;

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '1 year');

        IF v_rec_type = 'weekly' THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP

                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM v_rec_start)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := v_rec_start + v_days_ahead;

                v_occ_date := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    INSERT INTO event_mst (
                        event_id, profile_id, parent_event_id,
                        title, description,
                        event_date, event_time, event_timezone,
                        livestream, video, is_recurring,
                        created_at, updated_at
                    )
                    VALUES (
                        gen_random_uuid(), v_profile_id, p_event_id,
                        v_title, v_description,
                        v_occ_date, v_event_time, v_event_tz,
                        v_livestream, v_video, true,
                        now(), now()
                    );
                    v_occ_date := v_occ_date + (7 * v_rec_interval);
                END LOOP;

            END LOOP;

        ELSIF v_rec_type IN ('first', 'last') THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP

                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;

                v_month_start := DATE_TRUNC('month', v_rec_start)::date;

                WHILE v_month_start <= v_safe_end LOOP

                    IF v_rec_type = 'first' THEN
                        v_days_ahead := (7 + v_dow_target - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date   := v_month_start + v_days_ahead;
                    ELSE
                        v_month_end     := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;

                    IF v_occ_date >= v_rec_start AND v_occ_date <= v_safe_end THEN
                        INSERT INTO event_mst (
                            event_id, profile_id, parent_event_id,
                            title, description,
                            event_date, event_time, event_timezone,
                            livestream, video, is_recurring,
                            created_at, updated_at
                        )
                        VALUES (
                            gen_random_uuid(), v_profile_id, p_event_id,
                            v_title, v_description,
                            v_occ_date, v_event_time, v_event_tz,
                            v_livestream, v_video, true,
                            now(), now()
                        );
                    END IF;

                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;

            END LOOP;

        END IF;

    END IF;

    RETURN json_build_object('status', true, 'message', 'Event updated successfully');

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
