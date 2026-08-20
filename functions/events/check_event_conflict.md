# `check_event_conflict`

## Version History

### v3.0 (Current — 2026-08-20) ✅
- **Function name:** `check_event_conflict_v3`
- **Changes from v2.0:** Adds `p_event_end_date` (optional, defaults to `p_event_date`),
  matching `create_event_v4`/`update_event_v2_5`, and fixes a pre-existing inconsistency:
  v2.0 rejected `p_event_time >= p_event_end_time` outright and computed both the new
  and every existing event's end timestamp using the *same calendar day* as its start
  time — so a legitimately created cross-midnight event (`event_end_time < event_time`)
  could never be checked correctly here, and the endpoint would reject a same-shape
  request that `create_event_v4`/`update_event_v2_5` accept. Both the new event and every
  existing row now use their real `event_end_date` (or `p_event_date`/`event_date` when
  none is set) to build the end timestamp, so multi-day spans compare correctly.
- **Endpoint:** `POST /rpc/check_event_conflict_v3`

### v2.0 (Previous — 2026-06-02)
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

## V3.0 Function (Current) ✅

```sql
-- Function: check_event_conflict_v3
-- Group:    events
-- Endpoint: POST /rpc/check_event_conflict_v3
-- Tables:   event_mst
-- Doc:      docs/api/events/check_event_conflict.md
-- Version:  3.0 (2026-08-20)
-- Changes:  Added p_event_end_date (defaults to p_event_date). New event and every
--           existing row now use their real end date to build the end timestamp
--           instead of assuming the end time falls on the same calendar day as the
--           start time — fixes cross-midnight events being uncheckable/rejected.
--
-- Parameters:
--   p_profile_id      (uuid)       - required  - Profile ID to check conflicts for
--   p_event_date      (date)       - required  - Event date (YYYY-MM-DD)
--   p_event_time      (time)       - required  - Event start time (HH:MM:SS)
--   p_event_end_time  (time)       - optional  - Event end time. NULL = point-in-time check
--   p_event_end_date  (date)       - optional  - Event end date. Defaults to p_event_date.
--   p_event_id        (uuid)       - optional  - Exclude this specific event (editing)
--   p_parent_event_id (uuid)       - optional  - Exclude entire recurring series (editing recurring)
--
-- Conflict Logic:
--   Without end_time (point-in-time): existing_start <= point AND existing_end >= point
--   With end_time (range):            existing_start < new_end AND existing_end > new_start

CREATE OR REPLACE FUNCTION check_event_conflict_v3(
    p_profile_id uuid,
    p_event_date date,
    p_event_time time,
    p_event_end_time time DEFAULT NULL,
    p_event_end_date date DEFAULT NULL,
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
    v_new_end_date date;
BEGIN
    -- Validate inputs
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    IF p_event_date IS NULL OR p_event_time IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event date and start time are required');
    END IF;

    v_new_end_date := COALESCE(p_event_end_date, p_event_date);

    IF v_new_end_date < p_event_date THEN
        RETURN json_build_object('status', false, 'message', 'Event end date cannot be before event start date');
    END IF;

    IF p_event_end_time IS NOT NULL
       AND (v_new_end_date || ' ' || p_event_end_time)::timestamp <= (p_event_date || ' ' || p_event_time)::timestamp THEN
        RETURN json_build_object('status', false, 'message', 'Event start date/time must be before end date/time');
    END IF;

    v_new_start := (p_event_date || ' ' || p_event_time)::timestamp AT TIME ZONE 'UTC';
    v_new_end := CASE 
                    WHEN p_event_end_time IS NULL THEN v_new_start
                    ELSE (v_new_end_date || ' ' || p_event_end_time)::timestamp AT TIME ZONE 'UTC'
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
                AND (COALESCE(event_end_date, event_date) || ' ' || event_end_time)::timestamp >= v_new_start
            ELSE
                (event_date || ' ' || event_time)::timestamp < v_new_end
                AND (COALESCE(event_end_date, event_date) || ' ' || event_end_time)::timestamp > v_new_start
          END;

    IF v_conflict_count > 0 THEN
        SELECT 
            event_id,
            title,
            event_date,
            event_time,
            event_end_date,
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
                    AND (COALESCE(event_end_date, event_date) || ' ' || event_end_time)::timestamp >= v_new_start
                ELSE
                    (event_date || ' ' || event_time)::timestamp < v_new_end
                    AND (COALESCE(event_end_date, event_date) || ' ' || event_end_time)::timestamp > v_new_start
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
            'conflicting_event_end_date', v_conflicting_event.event_end_date,
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

## V2.0 Function (Previous)

```sql
-- Function: check_event_conflict_v2
-- Group:    events
-- Endpoint: POST /rpc/check_event_conflict_v2
-- Tables:   event_mst
-- Doc:      docs/api/events/check_event_conflict.md
-- Version:  2.0 (2026-06-02)
-- Changes:  Added p_event_id, p_parent_event_id, CASE boundary logic, optional end_time
--
-- Superseded by check_event_conflict_v3 (2026-08-20) — this version assumes the end
-- time always falls on the same calendar day as the start time and rejects
-- end_time <= start_time outright, so it cannot correctly check (or even accept) a
-- cross-midnight event. Kept for existing callers.
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
