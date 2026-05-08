# `update_event`

```sql
-- Function: update_event
-- Group: Events
-- Endpoint: POST /rpc/update_event
-- Tables:   event_mst (UPDATE), event_platforms (DELETE+INSERT), event_recurring (UPDATE if recurring)
--           event_collaborators (INSERT/UPDATE if collaborative), notifications (INSERT if collaborative)
-- Doc: docs/api/events/update_event.md
--
-- COALESCE pattern — only fields that are passed (non-null) are updated.
-- p_scope: 'all' (default) = update parent + all occurrences
--          'this'          = update only this specific child occurrence (pass child event_id)
-- p_platforms: null = don't touch | [] = clear | [...] = replace
-- p_recurring_days: triggers recurring rule update + child regeneration ('all' scope only)
-- p_collaborator_ids: append new invites only — PATCH, never removes ('all' scope only)
--
-- 'this' scope behaviour:
--   • Updates scalar fields on the child row only (COALESCE — only passed fields change)
--   • If p_platforms passed: stores platforms on child's own event_id
--     → read SPs detect per-child platforms and use them instead of parent's
--   • Recurring schedule and collaborator changes are not allowed per-occurrence

CREATE OR REPLACE FUNCTION update_event(
    p_event_id             uuid,
    p_user_id              uuid,
    p_scope                text     DEFAULT 'all',
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_event_end_time       time     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_is_collaborative     boolean  DEFAULT NULL,
    p_collaborator_ids     uuid[]   DEFAULT NULL,
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

    -- Parent resolution
    v_parent_event_id    uuid;
    v_target_parent_id   uuid;

    -- For recurring child regeneration
    v_profile_id         uuid;
    v_title              text;
    v_description        text;
    v_event_time         time;
    v_event_end_time     time;
    v_event_tz           text;
    v_livestream         boolean;
    v_video              boolean;
    v_is_collaborative   boolean;

    v_existing_event_time     time;
    v_existing_event_end_time time;
    v_final_event_time        time;
    v_final_event_end_time    time;

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

    -- Collaborator invite variables
    v_owner_profile_id   uuid;
    v_owner_name         text;
    v_event_title        text;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;
    v_existing_collab_id uuid;
    v_existing_deleted   boolean;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── Scope validation ──────────────────────────────────────────────────────
    IF COALESCE(p_scope, 'all') NOT IN ('all', 'this') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be ''all'' or ''this''');
    END IF;

    -- ── Ownership check (owner only) ─────────────────────────────────────────
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

    -- ── Resolve parent event ──────────────────────────────────────────────────
    -- v_parent_event_id = NULL  → p_event_id is a parent or non-recurring event
    -- v_parent_event_id = uuid  → p_event_id is a child occurrence
    SELECT parent_event_id INTO v_parent_event_id
    FROM event_mst WHERE event_id = p_event_id;

    -- v_target_parent_id is always the series parent (or the event itself if non-recurring)
    v_target_parent_id := COALESCE(v_parent_event_id, p_event_id);

    -- ══════════════════════════════════════════════════════════════════════════
    -- SCOPE: 'this' — update only this specific occurrence
    -- ══════════════════════════════════════════════════════════════════════════
    IF COALESCE(p_scope, 'all') = 'this' THEN

        -- Must be a child occurrence row
        IF v_parent_event_id IS NULL THEN
            RETURN json_build_object('status', false, 'message',
                'Scope ''this'' can only be used on a specific recurring occurrence — pass the child event_id, not the parent');
        END IF;

        -- Recurring schedule changes are not per-occurrence
        IF p_recurring_days IS NOT NULL THEN
            RETURN json_build_object('status', false, 'message',
                'Recurring schedule cannot be changed for a single occurrence — use scope ''all''');
        END IF;

        -- Collaborator invites are not per-occurrence
        IF p_collaborator_ids IS NOT NULL AND array_length(p_collaborator_ids, 1) > 0 THEN
            RETURN json_build_object('status', false, 'message',
                'Collaborator invites cannot be scoped to a single occurrence — use scope ''all''');
        END IF;

        -- End time validation
        SELECT event_time, event_end_time
        INTO v_existing_event_time, v_existing_event_end_time
        FROM event_mst WHERE event_id = p_event_id;

        v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
        v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

        IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
            RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
        END IF;

        -- Platform validation
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

        -- Update this occurrence only (COALESCE — only passed fields change)
        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_date     = COALESCE(p_event_date,     event_date),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            updated_at     = now()
        WHERE event_id = p_event_id;

        -- Handle platforms for this occurrence specifically.
        -- Storing event_platforms rows on the child's own event_id signals an override
        -- to read SPs — they detect per-child rows and skip the parent fallback.
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

        RETURN json_build_object(
            'status',  true,
            'message', 'Event occurrence updated successfully',
            'data',    json_build_object('skipped_collaborator_ids', ARRAY[]::uuid[])
        );

    END IF;
    -- ══════════════════════════════════════════════════════════════════════════
    -- SCOPE: 'all' — update parent + propagate to all occurrences
    -- All operations below use v_target_parent_id (the series parent event_id)
    -- ══════════════════════════════════════════════════════════════════════════

    -- ── Collaborator IDs require is_collaborative = true (effective value) ────
    IF p_collaborator_ids IS NOT NULL AND array_length(p_collaborator_ids, 1) > 0 THEN
        IF COALESCE(
            p_is_collaborative,
            (SELECT is_collaborative FROM event_mst WHERE event_id = v_target_parent_id)
        ) = false THEN
            RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
        END IF;
    END IF;

    -- ── End time validation (using parent's current values for reference) ─────
    SELECT event_time, event_end_time
    INTO v_existing_event_time, v_existing_event_end_time
    FROM event_mst
    WHERE event_id = v_target_parent_id;

    v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
    v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

    IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
        RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
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

        -- Fetch current recurring rule from parent
        SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
        INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
        FROM event_recurring WHERE event_id = v_target_parent_id;

        v_rec_days     := p_recurring_days;
        v_rec_type     := COALESCE(p_recurring_type,       v_rec_type);
        v_rec_interval := COALESCE(p_recurring_interval,   v_rec_interval);
        v_rec_start    := COALESCE(p_recurring_start_date, v_rec_start);
        v_rec_end      := COALESCE(p_recurring_end_date,   v_rec_end);

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

    -- ── Update parent event_mst ───────────────────────────────────────────────
    UPDATE event_mst
    SET title             = COALESCE(p_title,            title),
        description       = COALESCE(p_description,      description),
        event_date        = COALESCE(p_event_date,        event_date),
        event_time        = COALESCE(p_event_time,        event_time),
        event_end_time    = COALESCE(p_event_end_time,    event_end_time),
        event_timezone    = COALESCE(p_timezone,          event_timezone),
        livestream        = COALESCE(p_livestream,        livestream),
        video             = COALESCE(p_video,             video),
        is_collaborative  = COALESCE(p_is_collaborative,  is_collaborative),
        updated_at        = now()
    WHERE event_id = v_target_parent_id;

    -- ── Propagate scalar changes to all child occurrences ─────────────────────
    -- event_date intentionally excluded — each child keeps its own occurrence date.
    -- Fields not passed are left as-is on each child (COALESCE pattern per row).
    UPDATE event_mst
    SET title            = COALESCE(p_title,            title),
        description      = COALESCE(p_description,      description),
        event_time       = COALESCE(p_event_time,       event_time),
        event_end_time   = COALESCE(p_event_end_time,   event_end_time),
        event_timezone   = COALESCE(p_timezone,         event_timezone),
        livestream       = COALESCE(p_livestream,       livestream),
        video            = COALESCE(p_video,            video),
        is_collaborative = COALESCE(p_is_collaborative, is_collaborative),
        updated_at       = now()
    WHERE parent_event_id = v_target_parent_id;

    -- ── Update platforms ──────────────────────────────────────────────────────
    IF p_platforms IS NOT NULL THEN
        -- Clear parent's own platform rows
        DELETE FROM event_platforms WHERE event_id = v_target_parent_id;
        -- Clear any per-occurrence platform overrides on child rows
        DELETE FROM event_platforms
        WHERE event_id IN (
            SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id
        );
        IF jsonb_array_length(p_platforms) > 0 THEN
            FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
            LOOP
                INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                VALUES (
                    gen_random_uuid(),
                    v_target_parent_id,
                    (v_platform->>'platform_id')::int4,
                    v_platform->>'stream_url',
                    now()
                );
            END LOOP;
        END IF;
    END IF;

    -- ── Update recurring rule + regenerate child rows ─────────────────────────
    IF p_recurring_days IS NOT NULL THEN

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '3 months');
        v_rec_end  := v_safe_end;

        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end,
            renewal_notified_at  = NULL
        WHERE event_id = v_target_parent_id;

        -- Delete all existing child occurrence rows
        -- (ON DELETE CASCADE removes any per-child event_platforms rows automatically)
        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id;

        -- Fetch parent row values for child generation
        SELECT profile_id, title, description, event_time, event_end_time,
               event_timezone, livestream, video, is_collaborative
        INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
             v_event_tz, v_livestream, v_video, v_is_collaborative
        FROM event_mst WHERE event_id = v_target_parent_id;

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
                        event_date, event_time, event_end_time, event_timezone,
                        livestream, video, is_collaborative, is_recurring,
                        created_at, updated_at
                    )
                    VALUES (
                        gen_random_uuid(), v_profile_id, v_target_parent_id,
                        v_title, v_description,
                        v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                        v_livestream, v_video, v_is_collaborative, true,
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
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring,
                            created_at, updated_at
                        )
                        VALUES (
                            gen_random_uuid(), v_profile_id, v_target_parent_id,
                            v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true,
                            now(), now()
                        );
                    END IF;

                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;

            END LOOP;

        END IF;

    END IF; -- recurring

    -- ── Append collaborator invites (PATCH — only add new, never remove) ──────
    v_skipped_ids := ARRAY[]::uuid[];

    IF p_collaborator_ids IS NOT NULL AND array_length(p_collaborator_ids, 1) > 0 THEN

        SELECT cp.id, cp.profile_name, e.title
        INTO v_owner_profile_id, v_owner_name, v_event_title
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = v_target_parent_id;

        SELECT COUNT(*) INTO v_collab_count
        FROM event_collaborators
        WHERE event_id   = v_target_parent_id
          AND status     = 'accepted'
          AND is_deleted = false;

        FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

            IF v_collab_id = v_owner_profile_id THEN
                v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                CONTINUE;
            END IF;

            IF v_collab_count >= 5 THEN
                v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                CONTINUE;
            END IF;

            SELECT id, is_deleted
            INTO v_existing_collab_id, v_existing_deleted
            FROM event_collaborators
            WHERE event_id   = v_target_parent_id
              AND profile_id = v_collab_id
            LIMIT 1;

            IF v_existing_collab_id IS NOT NULL AND v_existing_deleted = false THEN
                v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                v_existing_collab_id := NULL;
                CONTINUE;
            END IF;

            SELECT user_id INTO v_invitee_user_id
            FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

            IF v_invitee_user_id IS NULL THEN
                v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                v_existing_collab_id := NULL;
                CONTINUE;
            END IF;

            IF v_existing_collab_id IS NOT NULL THEN
                UPDATE event_collaborators
                SET status       = 'pending',
                    invited_by   = v_owner_profile_id,
                    invited_at   = now(),
                    responded_at = NULL,
                    updated_at   = now(),
                    is_deleted   = false,
                    deleted_at   = NULL
                WHERE id = v_existing_collab_id;
            ELSE
                INSERT INTO event_collaborators (
                    id, event_id, profile_id, invited_by, status, invited_at, updated_at
                )
                VALUES (
                    gen_random_uuid(), v_target_parent_id, v_collab_id,
                    v_owner_profile_id, 'pending', now(), now()
                );
            END IF;

            INSERT INTO notifications (user_id, title, body, data)
            VALUES (
                v_invitee_user_id,
                'Collaboration Invite',
                v_owner_name || ' invited you to collaborate on "' || v_event_title || '"',
                json_build_object(
                    'type',                  'collaborator_invite',
                    'event_id',              v_target_parent_id,
                    'invited_by_profile_id', v_owner_profile_id
                )
            );

            v_invitee_user_id    := NULL;
            v_existing_collab_id := NULL;

        END LOOP;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Event updated successfully',
        'data', json_build_object(
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
