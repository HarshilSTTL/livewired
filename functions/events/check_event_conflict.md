# `check_event_conflict` (v1.0)

## Version History

### v1.0 (Current — 2026-06-01)
- **Purpose:** Detects event time conflicts for a profile
- **Usage:** Real-time validation in date/time picker (works with or without end time)
- **Message:** "You already have an event scheduled at this time."
- **Parameters:** p_profile_id (uuid), p_event_date (date), p_event_time (time), p_event_end_time (time, optional), p_event_id (uuid, optional)
- **Behavior:** 
  - With end_time: Full overlap check (exclusive, allows adjacent events: existing_start < new_end AND existing_end > new_start)
  - Without end_time: Point-in-time check (inclusive: existing_start <= point AND existing_end >= point)
- **Check Scope:** Only checks conflicts with events that have event_end_time IS NOT NULL
- **Adjacency:** Events that touch but don't overlap (6:00 PM vs 1:00-6:00 PM) are NOT considered conflicts
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
--   p_event_end_time (time, optional) - Event end time (HH:MM:SS). If NULL, skip conflict check
--   p_event_id (uuid, optional) - Event ID to exclude when editing
--
-- Returns JSON with:
--   - status (boolean) - Success/failure
--   - has_conflict (boolean) - Whether conflict detected
--   - message (string) - Conflict message or status message
--   - conflicting_event details if conflict exists (event_id, title, date, time, end_time)
--
-- Conflict Logic:
--   - If p_event_end_time IS NULL (point-in-time):
--     Check if start_time is DURING existing event (inclusive of boundaries)
--     existing_start <= point AND existing_end >= point
--     Examples: 1:00 PM vs 1:00-6:00 PM = CONFLICT, 6:00 PM vs 1:00-6:00 PM = CONFLICT
--   
--   - If p_event_end_time IS NOT NULL (range):
--     Check if ranges overlap (exclusive of boundaries = allows adjacency)
--     existing_start < new_end AND existing_end > new_start
--     Examples: 2:00-3:00 PM vs 1:00-6:00 PM = CONFLICT, 6:00-7:00 PM vs 1:00-6:00 PM = NO CONFLICT

CREATE OR REPLACE FUNCTION check_event_conflict(
    p_profile_id uuid,
    p_event_date date,
    p_event_time time,
    p_event_end_time time DEFAULT NULL,
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

    IF p_event_date IS NULL OR p_event_time IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event date and start time are required');
    END IF;

    -- Validate times
    IF p_event_end_time IS NOT NULL AND p_event_time >= p_event_end_time THEN
        RETURN json_build_object('status', false, 'message', 'Event start time must be before end time');
    END IF;

    -- Build timestamps for comparison
    -- If no end_time provided, use start_time as end_time (point-in-time check)
    v_new_start := (p_event_date || ' ' || p_event_time)::timestamp AT TIME ZONE 'UTC';
    v_new_end := CASE 
                    WHEN p_event_end_time IS NULL THEN v_new_start
                    ELSE (p_event_date || ' ' || p_event_end_time)::timestamp AT TIME ZONE 'UTC'
                 END;

    -- Check for overlapping events in event_mst
    -- Exclude: deleted events (is_deleted = true)
    -- Only check: events that have an end time (event_end_time IS NOT NULL)
    -- Logic:
    --   Point-in-time (no end_time): existing_start <= point AND existing_end >= point
    --   Range (has end_time): existing_start < new_end AND existing_end > new_start
    --   (Excludes adjacent events - 6:00 PM vs 1:00-6:00 PM = no conflict)
    SELECT COUNT(*) INTO v_conflict_count
    FROM event_mst
    WHERE profile_id = p_profile_id
      AND is_deleted = false
      AND event_end_time IS NOT NULL
      AND (p_event_id IS NULL OR event_id != p_event_id)
      AND CASE 
            WHEN p_event_end_time IS NULL THEN
                -- Point-in-time: check if start_time is during existing event (inclusive)
                (event_date || ' ' || event_time)::timestamp <= v_new_start
                AND (event_date || ' ' || event_end_time)::timestamp >= v_new_start
            ELSE
                -- Range: check if ranges overlap (exclusive - allows adjacency)
                (event_date || ' ' || event_time)::timestamp < v_new_end
                AND (event_date || ' ' || event_end_time)::timestamp > v_new_start
          END;

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
          AND event_end_time IS NOT NULL
          AND (p_event_id IS NULL OR event_id != p_event_id)
          AND CASE 
                WHEN p_event_end_time IS NULL THEN
                    -- Point-in-time: check if start_time is during existing event (inclusive)
                    (event_date || ' ' || event_time)::timestamp <= v_new_start
                    AND (event_date || ' ' || event_end_time)::timestamp >= v_new_start
                ELSE
                    -- Range: check if ranges overlap (exclusive - allows adjacency)
                    (event_date || ' ' || event_time)::timestamp < v_new_end
                    AND (event_date || ' ' || event_end_time)::timestamp > v_new_start
              END
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
