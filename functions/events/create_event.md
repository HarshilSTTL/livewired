# `create_event`

```sql
-- Function: create_event
-- Group:    events
-- Endpoint: POST /rpc/create_event
-- Tables:   event_mst (INSERT), event_platforms (INSERT), event_recurring (INSERT if recurring)
-- Doc:      docs/api/events/create_event.md
--
-- Notes:
--   • event_platforms.platform_id is int4 — cast (pl->>'platform_id')::int4 on INSERT.
--   • Validate platform IDs against platforms.plat_id (int8) using ::bigint cast.
--   • Ownership check: profile must exist, belong to p_user_id, and be 'active'.
--   • p_platforms null/[] → no event_platforms rows created.
--
-- Recurring event pre-generation:
--   When p_is_recurring = true, create_event inserts:
--     1. ONE parent row in event_mst (parent_event_id = NULL) — stores the definition
--     2. event_platforms rows on the parent only — children inherit
--     3. ONE row in event_recurring — stores the recurrence rule
--     4. N child rows in event_mst (parent_event_id = parent event_id) —
--        one per computed occurrence date between recurring_start_date and recurring_end_date
--
--   Child rows have individual event_date values but share all other fields with the parent.
--   If recurring_end_date is null, occurrences are generated up to 3 months from start_date.
--   The computed end date is always written to event_recurring so notify_expiring_recurring_events
--   can query it without needing to handle NULLs.
--
-- Occurrence date generation:
--   weekly → for each day in recurring_days, find first occurrence on/after start_date,
--            then add (7 × interval) days per step until end_date
--   first  → for each day in recurring_days, find the first occurrence of that weekday
--            in each calendar month between start_date and end_date
--   last   → same but last occurrence of the weekday in each calendar month

CREATE OR REPLACE FUNCTION create_event(
    p_profile_id             uuid,
    p_user_id                uuid,
    p_title                  text,
    p_event_date             date,
    p_event_time             time,
    p_event_end_time         time     DEFAULT null,
    p_timezone               text     DEFAULT 'UTC',
    p_description            text     DEFAULT null,
    p_livestream             boolean  DEFAULT false,
    p_video                  boolean  DEFAULT false,
    p_is_collaborative       boolean  DEFAULT false,
    p_collaborator_ids       uuid[]   DEFAULT null,
    p_is_recurring           boolean  DEFAULT false,
    p_platforms              jsonb    DEFAULT null,
    -- Recurring fields (only used when p_is_recurring = true)
    p_recurring_days         text[]   DEFAULT null,
    p_recurring_type         text     DEFAULT null,
    p_recurring_interval     int      DEFAULT null,
    p_recurring_start_date   date     DEFAULT null,
    p_recurring_end_date     date     DEFAULT null
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_id           uuid;
    v_platform           jsonb;
    v_platform_id        bigint;
    v_stream_url         text;

    -- Collaborator invite variables
    v_owner_name         text;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;

    -- Recurring generation variables
    v_safe_end           date;
    v_day_name           text;
    v_dow_target         int;
    v_dow_start          int;
    v_days_ahead         int;
    v_first_occ          date;
    v_occ_date           date;
    v_month_start        date;
    v_month_end          date;
    v_dow_month_end      int;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    -- ── Ownership + active check ──────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id AND status = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found, access denied, or profile is not active');
    END IF;

    -- ── Collaborator IDs require is_collaborative = true ─────────────────────
    IF p_collaborator_ids IS NOT NULL AND array_length(p_collaborator_ids, 1) > 0
       AND COALESCE(p_is_collaborative, false) = false THEN
        RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
    END IF;

    -- ── Required field validation ─────────────────────────────────────────────
    IF p_title IS NULL OR trim(p_title) = '' THEN
        RETURN json_build_object('status', false, 'message', 'Event title is required');
    END IF;

    IF p_event_date IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event date is required');
    END IF;

    IF p_event_time IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event time is required');
    END IF;

    -- ── End time validation ───────────────────────────────────────────────────
    -- end_time < start_time is valid (cross-midnight, treated as next day).
    -- Only reject if end_time = start_time (zero-duration event).
    IF p_event_end_time IS NOT NULL AND p_event_end_time = p_event_time THEN
        RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
    END IF;

    -- Default end time to 2 hours after start time if not provided.
    -- TIME + INTERVAL wraps correctly past midnight (e.g. 23:00 → 01:00),
    -- which is already handled as cross-midnight by get_profile_events / get_event_list.
    IF p_event_end_time IS NULL THEN
        p_event_end_time := p_event_time + INTERVAL '2 hours';
    END IF;

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

    -- ── Recurring validation (only when p_is_recurring = true) ───────────────
    IF COALESCE(p_is_recurring, false) = true THEN

        -- recurring_days: required, non-empty, valid values only
        IF p_recurring_days IS NULL OR array_length(p_recurring_days, 1) = 0 THEN
            RETURN json_build_object('status', false, 'message', 'Recurring days are required');
        END IF;

        IF EXISTS (
            SELECT 1 FROM unnest(p_recurring_days) AS d(day)
            WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
        ) THEN
            RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
        END IF;

        -- recurring_type: required, valid value
        IF p_recurring_type IS NULL OR p_recurring_type NOT IN ('weekly', 'first', 'last') THEN
            RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
        END IF;

        -- recurring_interval: required + 1–12 for weekly; must be null for first/last
        IF p_recurring_type = 'weekly' THEN
            IF p_recurring_interval IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
            END IF;
            IF p_recurring_interval < 1 OR p_recurring_interval > 12 THEN
                RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
            END IF;
        ELSE
            IF p_recurring_interval IS NOT NULL THEN
                RETURN json_build_object('status', false, 'message', 'recurring_interval must be null for first/last type');
            END IF;
        END IF;

        -- recurring_start_date: required
        IF p_recurring_start_date IS NULL THEN
            RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
        END IF;

        -- recurring_end_date: if provided, must be after start date
        IF p_recurring_end_date IS NOT NULL AND p_recurring_end_date <= p_recurring_start_date THEN
            RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
        END IF;

    END IF;

    -- ── Insert parent row into event_mst ──────────────────────────────────────
    -- For recurring events this is the "template" row (parent_event_id = NULL).
    -- It stores the definition (title, time, platforms) but is excluded from
    -- date-based queries by get_profile_events.
    INSERT INTO event_mst (
        event_id, profile_id, parent_event_id,
        title, description,
        event_date, event_time, event_end_time, event_timezone,
        livestream, video, is_collaborative, is_recurring,
        created_at, updated_at
    )
    VALUES (
        gen_random_uuid(), p_profile_id, NULL,
        p_title, p_description,
        p_event_date, p_event_time, p_event_end_time, p_timezone,
        COALESCE(p_livestream, false), COALESCE(p_video, false),
        COALESCE(p_is_collaborative, false), COALESCE(p_is_recurring, false),
        now(), now()
    )
    RETURNING event_id INTO v_event_id;

    -- ── Insert into event_platforms (parent only) ─────────────────────────────
    -- ⚠️ platform_id column is int4 — cast ::int4 on INSERT
    -- Child occurrence rows do NOT get event_platforms rows — they inherit from
    -- the parent via COALESCE(parent_event_id, event_id) in get_profile_events.
    IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
        FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
        LOOP
            v_platform_id := (v_platform->>'platform_id')::bigint;
            v_stream_url  := v_platform->>'stream_url';

            INSERT INTO event_platforms (
                id, event_id, platform_id, stream_url, created_at
            )
            VALUES (
                gen_random_uuid(), v_event_id, v_platform_id::int4, v_stream_url, now()
            );
        END LOOP;
    END IF;

    -- ── Insert recurrence rule into event_recurring ───────────────────────────
    IF COALESCE(p_is_recurring, false) = true THEN
        -- Compute final end date: default to 3 months if not provided.
        -- Always store a concrete date so notify_expiring_recurring_events can query it.
        v_safe_end := COALESCE(p_recurring_end_date, p_recurring_start_date + INTERVAL '3 months');

        INSERT INTO event_recurring (
            id, event_id, recurring_days, recurring_type,
            recurring_interval, recurring_start_date, recurring_end_date,
            created_at
        )
        VALUES (
            gen_random_uuid(), v_event_id, p_recurring_days, p_recurring_type,
            p_recurring_interval, p_recurring_start_date, v_safe_end,
            now()
        );

        IF p_recurring_type = 'weekly' THEN

            -- For each selected day, compute its first occurrence on/after start_date,
            -- then step forward by (7 × interval) days until v_safe_end.
            FOREACH v_day_name IN ARRAY p_recurring_days LOOP

                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM p_recurring_start_date)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := p_recurring_start_date + v_days_ahead;

                v_occ_date := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    INSERT INTO event_mst (
                        event_id, profile_id, parent_event_id,
                        title, description,
                        event_date, event_time, event_end_time, event_timezone,
                        livestream, video, is_collaborative, is_recurring,
                        created_at, updated_at
                    )
                    VALUES (
                        gen_random_uuid(), p_profile_id, v_event_id,
                        p_title, p_description,
                        v_occ_date, p_event_time, p_event_end_time, p_timezone,
                        COALESCE(p_livestream, false), COALESCE(p_video, false),
                        COALESCE(p_is_collaborative, false), true,
                        now(), now()
                    );
                    v_occ_date := v_occ_date + (7 * p_recurring_interval);
                END LOOP;

            END LOOP;

        ELSIF p_recurring_type IN ('first', 'last') THEN

            -- For each selected day, walk month-by-month and find the first or last
            -- occurrence of that weekday in each calendar month.
            FOREACH v_day_name IN ARRAY p_recurring_days LOOP

                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;

                v_month_start := DATE_TRUNC('month', p_recurring_start_date)::date;

                WHILE v_month_start <= v_safe_end LOOP

                    IF p_recurring_type = 'first' THEN
                        -- First occurrence of v_dow_target in v_month_start's month
                        v_days_ahead := (7 + v_dow_target
                                           - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date := v_month_start + v_days_ahead;
                    ELSE
                        -- Last occurrence of v_dow_target in v_month_start's month
                        v_month_end     := (DATE_TRUNC('month', v_month_start)
                                            + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end
                                         - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;

                    -- Only insert if the occurrence falls within [start_date, safe_end]
                    IF v_occ_date >= p_recurring_start_date AND v_occ_date <= v_safe_end THEN
                        INSERT INTO event_mst (
                            event_id, profile_id, parent_event_id,
                            title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring,
                            created_at, updated_at
                        )
                        VALUES (
                            gen_random_uuid(), p_profile_id, v_event_id,
                            p_title, p_description,
                            v_occ_date, p_event_time, p_event_end_time, p_timezone,
                            COALESCE(p_livestream, false), COALESCE(p_video, false),
                            COALESCE(p_is_collaborative, false), true,
                            now(), now()
                        );
                    END IF;

                    -- Advance to next month
                    v_month_start := (DATE_TRUNC('month', v_month_start)
                                      + INTERVAL '1 month')::date;
                END LOOP;

            END LOOP;

        END IF; -- recurring type

    END IF; -- is_recurring

    -- ── Send collaborator invites ─────────────────────────────────────────────
    v_skipped_ids  := ARRAY[]::uuid[];
    v_collab_count := 0;

    IF COALESCE(p_is_collaborative, false) = true
       AND p_collaborator_ids IS NOT NULL
       AND array_length(p_collaborator_ids, 1) > 0 THEN

        SELECT profile_name INTO v_owner_name
        FROM creator_profiles WHERE id = p_profile_id;

        FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

            -- Cannot invite the creating profile
            IF v_collab_id = p_profile_id THEN
                v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                CONTINUE;
            END IF;

            -- Hard cap: max 5 collaborators
            IF v_collab_count >= 5 THEN
                v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                CONTINUE;
            END IF;

            -- Verify profile exists and is active
            SELECT user_id INTO v_invitee_user_id
            FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

            IF v_invitee_user_id IS NULL THEN
                v_skipped_ids     := array_append(v_skipped_ids, v_collab_id);
                v_invitee_user_id := NULL;
                CONTINUE;
            END IF;

            -- Insert pending invite
            INSERT INTO event_collaborators (
                id, event_id, profile_id, invited_by, status, invited_at, updated_at
            )
            VALUES (
                gen_random_uuid(), v_event_id, v_collab_id, p_profile_id, 'pending', now(), now()
            );

            -- Notify the invitee
            INSERT INTO notifications (user_id, title, body, data)
            VALUES (
                v_invitee_user_id,
                'Collaboration Invite',
                v_owner_name || ' invited you to collaborate on "' || p_title || '"',
                json_build_object(
                    'type',                  'collaborator_invite',
                    'event_id',              v_event_id,
                    'invited_profile_id',    v_collab_id,
                    'invited_by_profile_id', p_profile_id
                )
            );

            v_collab_count    := v_collab_count + 1;
            v_invitee_user_id := NULL;

        END LOOP;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Event created successfully',
        'data', json_build_object(
            'event_id',                 v_event_id,
            'skipped_collaborator_ids', v_skipped_ids
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
