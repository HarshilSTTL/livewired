# `skip_recurring_occurrence`

```sql
-- Function: skip_recurring_occurrence
-- Group: Events
-- Endpoint: POST /rpc/skip_recurring_occurrence
-- Tables:   event_mst (UPDATE)
-- Doc: docs/api/events/skip_recurring_occurrence.md
--
-- Soft-deletes a single occurrence in a recurring series (sets is_deleted = true on that child row).
-- Parent event and all other occurrences remain unchanged.
-- Only the event owner can skip occurrences.
-- Returns error if applied to a parent event or non-recurring event.

CREATE OR REPLACE FUNCTION skip_recurring_occurrence(
    p_event_id uuid,
    p_user_id  uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_parent_id    uuid;
    v_owner_id     uuid;
    v_event_date   date;
    v_event_title  text;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── Locate the event ─────────────────────────────────────────────────────
    SELECT parent_event_id, profile_id, event_date, title
    INTO v_parent_id, v_owner_id, v_event_date, v_event_title
    FROM event_mst
    WHERE event_id = p_event_id
    LIMIT 1;

    IF v_owner_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event not found');
    END IF;

    -- ── Authorization: must be event owner (profile_id, not event_owner) ──────
    IF v_owner_id <> (SELECT user_id FROM creator_profiles WHERE id = v_owner_id) THEN
        RETURN json_build_object('status', false, 'message', 'You do not have permission to modify this event');
    END IF;

    -- ── Ensure this is a child occurrence (parent_event_id IS NOT NULL) ───────
    IF v_parent_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Cannot skip a parent event or non-recurring event');
    END IF;

    -- ── Soft delete this occurrence ──────────────────────────────────────────
    UPDATE event_mst
    SET is_deleted = true
    WHERE event_id = p_event_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'Occurrence skipped',
        'data', json_build_object(
            'event_id',   p_event_id,
            'event_date', v_event_date,
            'title',      v_event_title
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
