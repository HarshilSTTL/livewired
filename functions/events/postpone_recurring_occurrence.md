# `postpone_recurring_occurrence`

```sql
-- Function: postpone_recurring_occurrence
-- Group: Events
-- Endpoint: POST /rpc/postpone_recurring_occurrence
-- Tables:   event_mst (UPDATE)
-- Doc: docs/api/events/postpone_recurring_occurrence.md
--
-- Moves a single occurrence in a recurring series to a new date/time.
-- Parent event and all other occurrences remain unchanged.
-- Only the event owner can postpone occurrences.
-- Validates that new_date is not in the past (>= today).
-- Returns error if applied to a parent event or non-recurring event.

CREATE OR REPLACE FUNCTION postpone_recurring_occurrence(
    p_event_id   uuid,
    p_user_id    uuid,
    p_new_date   date,
    p_new_time   time DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_parent_id      uuid;
    v_owner_id       uuid;
    v_profile_id     uuid;
    v_existing_time  time;
    v_final_time     time;
    v_event_title    text;
    v_old_date       date;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL OR p_new_date IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id, p_user_id, and p_new_date are required');
    END IF;

    -- ── Locate the event ─────────────────────────────────────────────────────
    SELECT parent_event_id, profile_id, event_date, event_time, title
    INTO v_parent_id, v_profile_id, v_old_date, v_existing_time, v_event_title
    FROM event_mst
    WHERE event_id = p_event_id
    LIMIT 1;

    IF v_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event not found');
    END IF;

    -- ── Authorization: must be event owner ─────────────────────────────────
    v_owner_id := (SELECT user_id FROM creator_profiles WHERE id = v_profile_id);
    IF v_owner_id <> p_user_id THEN
        RETURN json_build_object('status', false, 'message', 'You do not have permission to modify this event');
    END IF;

    -- ── Ensure this is a child occurrence (parent_event_id IS NOT NULL) ───────
    IF v_parent_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Cannot postpone a parent event or non-recurring event');
    END IF;

    -- ── Validate new_date is not in the past (>= today) ──────────────────────
    IF p_new_date < CURRENT_DATE THEN
        RETURN json_build_object('status', false, 'message', 'New date cannot be in the past');
    END IF;

    -- ── Determine final time: use new_time if provided, else keep existing ────
    v_final_time := COALESCE(p_new_time, v_existing_time);

    -- ── Update this occurrence only ──────────────────────────────────────────
    UPDATE event_mst
    SET event_date = p_new_date,
        event_time = v_final_time
    WHERE event_id = p_event_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'Occurrence postponed',
        'data', json_build_object(
            'event_id',    p_event_id,
            'old_date',    v_old_date,
            'new_date',    p_new_date,
            'new_time',    v_final_time,
            'title',       v_event_title
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
