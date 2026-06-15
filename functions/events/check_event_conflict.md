# `check_event_conflict`

## Version History

### v2.0 (Current — 2026-06-02) ✅
- **Function name:** `check_event_conflict_v2`
- **Changes from v1.0:**
  - Added `p_event_id` (uuid, optional) — exclude event being edited from conflict check
  - Added `p_parent_event_id` (uuid, optional) — exclude entire recurring series from conflict check
  - Added CASE logic for point-in-time vs range boundary handling
  - Made `p_event_end_time` optional (DEFAULT NULL) — supports events without end time
- **Behavior:**
  - With end_time (range): `existing_start < new_end AND existing_end > new_start` (exclusive, adjacent = no conflict)
  - Without end_time (point-in-time): `existing_start <= point AND existing_end >= point` (inclusive)
- **Endpoint:** `POST /rpc/check_event_conflict_v2`

### v1.0 (2026-06-01) — Deprecated
- **Function name:** `check_event_conflict`
- Basic conflict check — required both start and end times
- No self-exclusion (editing event would conflict with itself)
- No recurring series support
- Strict operators only — boundary cases failed
- **Endpoint:** `POST /rpc/check_event_conflict`

---

## V2.0 Function (Current) ✅

```sql
-- Function: check_event_conflict_v2
-- Group:    events
-- Endpoint: POST /rpc/check_event_conflict_v2
-- Tables:   event_mst
-- Doc:      docs/api/events/check_event_conflict.md
-- Version:  2.0 (2026-06-02)
-- Changes:  Added p_event_id, p_parent_event_id, CASE boundary logic, optional end_time
--
-- Parameters:
--   p_profile_id      (uuid)       - required  - Profile ID to check conflicts for
--   p_event_date      (date)       - required  - Event date (YYYY-MM-DD)
--   p_event_time      (time)       - required  - Event start time (HH:MM:SS)
--   p_event_end_time  (time)       - optional  - Event end time. NULL = point-in-time check
--   p_event_id        (uuid)       - optional  - Exclude this specific event (editing)
--   p_parent_event_id (uuid)       - optional  - Exclude entire recurring series (editing recurring)
--
-- Conflict Logic:
--   Without end_time (point-in-time): existing_start <= point AND existing_end >= point
--   With end_time (range):            existing_start < new_end AND existing_end > new_start

CREATE OR REPLACE FUNCTION check_event_conflict_v2(
    p_profile_id uuid,
    p_event_date date,
    p_event_time time,
    p_event_end_time time DEFAULT NULL,
    p_event_id uuid DEFAULT NULL,
    p_parent_event_id uuid DEFAULT NULL
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

    IF p_event_end_time IS NOT NULL AND p_event_time >= p_event_end_time THEN
        RETURN json_build_object('status', false, 'message', 'Event start time must be before end time');
    END IF;

    v_new_start := (p_event_date || ' ' || p_event_time)::timestamp AT TIME ZONE 'UTC';
    v_new_end := CASE 
                    WHEN p_event_end_time IS NULL THEN v_new_start
                    ELSE (p_event_date || ' ' || p_event_end_time)::timestamp AT TIME ZONE 'UTC'
                 END;

    SELECT COUNT(*) INTO v_conflict_count
    FROM event_mst
    WHERE profile_id = p_profile_id
      AND is_deleted = false
      AND event_end_time IS NOT NULL
      AND (p_event_id IS NULL OR event_id != p_event_id)
      AND (p_parent_event_id IS NULL OR parent_event_id != p_parent_event_id)
      AND CASE 
            WHEN p_event_end_time IS NULL THEN
                (event_date || ' ' || event_time)::timestamp <= v_new_start
                AND (event_date || ' ' || event_end_time)::timestamp >= v_new_start
            ELSE
                (event_date || ' ' || event_time)::timestamp < v_new_end
                AND (event_date || ' ' || event_end_time)::timestamp > v_new_start
          END;

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
          AND (p_parent_event_id IS NULL OR parent_event_id != p_parent_event_id)
          AND CASE 
                WHEN p_event_end_time IS NULL THEN
                    (event_date || ' ' || event_time)::timestamp <= v_new_start
                    AND (event_date || ' ' || event_end_time)::timestamp >= v_new_start
                ELSE
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

## V1.0 Function (Deprecated)

```sql
-- Function: check_event_conflict
-- Version:  1.0 (2026-06-01) — DEPRECATED, use check_event_conflict_v2
-- Endpoint: POST /rpc/check_event_conflict

CREATE OR REPLACE FUNCTION check_event_conflict(
    p_profile_id uuid,
    p_event_date date,
    p_event_time time,
    p_event_end_time time
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
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_event_date IS NULL OR p_event_time IS NULL OR p_event_end_time IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event date, start time and end time are required');
    END IF;

    IF p_event_time >= p_event_end_time THEN
        RETURN json_build_object('status', false, 'message', 'Event start time must be before end time');
    END IF;

    v_new_start := (p_event_date || ' ' || p_event_time)::timestamp AT TIME ZONE 'UTC';
    v_new_end   := (p_event_date || ' ' || p_event_end_time)::timestamp AT TIME ZONE 'UTC';

    SELECT COUNT(*) INTO v_conflict_count
    FROM event_mst
    WHERE profile_id = p_profile_id
      AND is_deleted = false
      AND event_end_time IS NOT NULL
      AND (event_date || ' ' || event_time)::timestamp < v_new_end
      AND (event_date || ' ' || event_end_time)::timestamp > v_new_start;

    IF v_conflict_count > 0 THEN
        SELECT event_id, title, event_date, event_time, event_end_time
        INTO v_conflicting_event
        FROM event_mst
        WHERE profile_id = p_profile_id
          AND is_deleted = false
          AND event_end_time IS NOT NULL
          AND (event_date || ' ' || event_time)::timestamp < v_new_end
          AND (event_date || ' ' || event_end_time)::timestamp > v_new_start
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
