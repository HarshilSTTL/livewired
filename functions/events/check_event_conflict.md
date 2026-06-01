# `check_event_conflict` (v1.0)

## Version History

### v1.0 (Current — 2026-06-01)
- **Purpose:** Detects event time conflicts for a profile
- **Usage:** Real-time validation in date/time picker
- **Message:** "You already have an event scheduled at this time."
- **Parameters:** p_profile_id (uuid), p_event_date (date), p_event_time (time), p_event_end_time (time), p_event_id (uuid, optional)
- **Table:** `event_mst` (stores separate date + time columns)
- **Endpoint:** `POST /rpc/check_event_conflict`

---

## V1.0 Function (Current)

```sql
-- Function: check_event_conflict
-- Group:    events
-- Endpoint: POST /rpc/check_event_conflict
-- Tables:   event_mst, creator_profiles
-- Doc:      docs/api/events/check_event_conflict.md
-- Version:  1.0 (2026-06-01)
-- Purpose:  Checks if a proposed event time conflicts with existing scheduled events
--           for a profile. Returns conflict details if overlap detected.
--           Handles date + time comparison (event_mst stores separate date and time)
--
-- Parameters:
--   p_profile_id (uuid) - Profile ID to check conflicts for
--   p_event_date (date) - Event date (YYYY-MM-DD)
--   p_event_time (time) - Event start time (HH:MM:SS)
--   p_event_end_time (time) - Event end time (HH:MM:SS)
--   p_event_id (uuid, optional) - Event ID to exclude when editing
--
-- Returns JSON with:
--   - status (boolean) - Success/failure
--   - has_conflict (boolean) - Whether conflict detected
--   - message (string) - Conflict message if found
--   - conflicting_event details if conflict exists

CREATE OR REPLACE FUNCTION check_event_conflict(
    p_profile_id uuid,
    p_event_date date,
    p_event_time time,
    p_event_end_time time,
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
    v_new_start timestamptz;
    v_new_end timestamptz;
BEGIN
    -- Validate inputs
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_event_date IS NULL OR p_event_time IS NULL OR p_event_end_time IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event date and times are required');
    END IF;

    IF p_event_time >= p_event_end_time THEN
        RETURN json_build_object('status', false, 'message', 'Event start time must be before end time');
    END IF;

    -- Build timestamps for comparison
    -- Assuming events are stored in creator's timezone, convert to UTC for comparison
    v_new_start := (p_event_date || ' ' || p_event_time)::timestamp AT TIME ZONE 'UTC';
    v_new_end := (p_event_date || ' ' || p_event_end_time)::timestamp AT TIME ZONE 'UTC';

    -- Check for overlapping events in event_mst
    -- Exclude: deleted events (is_deleted = true)
    -- Logic: existing_start < new_end AND existing_end > new_start
    SELECT COUNT(*) INTO v_conflict_count
    FROM event_mst
    WHERE profile_id = p_profile_id
      AND is_deleted = false
      AND (p_event_id IS NULL OR event_id != p_event_id)
      AND (event_date || ' ' || event_time)::timestamp < v_new_end
      AND (event_date || ' ' || COALESCE(event_end_time, event_time))::timestamp > v_new_start;

    -- If conflict found, return conflict details
    IF v_conflict_count > 0 THEN
        SELECT 
            event_id,
            title,
            event_date,
            event_time,
            event_end_time
        INTO v_conflicting_event
        FROM event_mst
        WHERE profile_id = p_profile_id
          AND is_deleted = false
          AND (p_event_id IS NULL OR event_id != p_event_id)
          AND (event_date || ' ' || event_time)::timestamp < v_new_end
          AND (event_date || ' ' || COALESCE(event_end_time, event_time))::timestamp > v_new_start
        ORDER BY event_date, event_time
        LIMIT 1;

        RETURN json_build_object(
            'status', true,
            'has_conflict', true,
            'message', 'You already have an event scheduled at this time.',
            'conflicting_event_id', v_conflicting_event.event_id,
            'conflicting_event_title', v_conflicting_event.title,
            'conflicting_event_date', v_conflicting_event.event_date,
            'conflicting_event_time', v_conflicting_event.event_time,
            'conflicting_event_end_time', v_conflicting_event.event_end_time
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
