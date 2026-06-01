# `check_event_conflict` (v1.0)

## Version History

### v1.0 (Current — 2026-06-01)
- **Purpose:** Detects event time conflicts for a profile
- **Usage:** Real-time validation in date/time picker
- **Message:** "You already have an event scheduled at this time."
- **Parameters:** p_profile_id (uuid), p_start_time, p_end_time, p_event_id (uuid, optional)
- **Endpoint:** `POST /rpc/check_event_conflict`

---

## V1.0 Function (Current)

```sql
-- Function: check_event_conflict
-- Group:    events
-- Endpoint: POST /rpc/check_event_conflict
-- Tables:   events
-- Doc:      docs/api/events/check_event_conflict.md
-- Version:  1.0 (2026-06-01)
-- Purpose:  Checks if a proposed event time conflicts with existing scheduled events
--           for a profile. Returns conflict details if overlap detected.
--
-- Parameters:
--   p_profile_id (uuid) - Profile ID to check conflicts for
--   p_start_time (timestamp with time zone) - Event start time (ISO 8601)
--   p_end_time (timestamp with time zone) - Event end time (ISO 8601)
--   p_event_id (uuid, optional) - Event ID to exclude when editing
--
-- Returns JSON with:
--   - status (boolean) - Success/failure
--   - has_conflict (boolean) - Whether conflict detected
--   - message (string) - Conflict message if found
--   - conflicting_event details if conflict exists

CREATE OR REPLACE FUNCTION check_event_conflict(
    p_profile_id uuid,
    p_start_time timestamp with time zone,
    p_end_time timestamp with time zone,
    p_event_id uuid DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_conflict_count int;
    v_conflicting_event record;
BEGIN
    -- Validate inputs
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_start_time IS NULL OR p_end_time IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Start time and end time are required');
    END IF;

    IF p_start_time >= p_end_time THEN
        RETURN json_build_object('status', false, 'message', 'Start time must be before end time');
    END IF;

    -- Check for overlapping events
    -- Logic: existing_start < new_end AND existing_end > new_start
    SELECT COUNT(*) INTO v_conflict_count
    FROM events
    WHERE profile_id = p_profile_id
      AND status NOT IN ('deleted', 'cancelled')
      AND (p_event_id IS NULL OR id != p_event_id)
      AND event_start < p_end_time
      AND event_end > p_start_time;

    -- If conflict found, return conflict details
    IF v_conflict_count > 0 THEN
        SELECT * INTO v_conflicting_event
        FROM events
        WHERE profile_id = p_profile_id
          AND status NOT IN ('deleted', 'cancelled')
          AND (p_event_id IS NULL OR id != p_event_id)
          AND event_start < p_end_time
          AND event_end > p_start_time
        LIMIT 1;

        RETURN json_build_object(
            'status', true,
            'has_conflict', true,
            'message', 'You already have an event scheduled at this time.',
            'conflicting_event_id', v_conflicting_event.id,
            'conflicting_event_name', v_conflicting_event.event_name,
            'conflicting_event_start', v_conflicting_event.event_start,
            'conflicting_event_end', v_conflicting_event.event_end
        );
    ELSE
        RETURN json_build_object(
            'status', true,
            'has_conflict', false,
            'message', 'No conflicts found.'
        );
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status', false,
            'has_conflict', false,
            'message', 'Error checking conflicts',
            'error', SQLERRM
        );
END;
$$;
```

---
