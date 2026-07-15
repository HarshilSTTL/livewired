# `set_event_reminder`

```sql
-- Function: set_event_reminder
-- Group: Events
-- Endpoint: POST /rpc/set_event_reminder
-- Tables:   event_reminders (INSERT, UPDATE), event_mst (SELECT)
-- Doc: docs/api/events/set_event_reminder.md
--
-- Adds a new reminder time for a user on a specific event. A user may add
-- multiple reminders to the same event (e.g. 1 day before, 1 hour before,
-- 10 minutes before) as long as each reminder_minutes value is distinct.
-- No cap on the number of reminders per event.
--
-- Recurring propagation:
--   If p_event_id belongs to a recurring series (it is the parent template
--   OR a child occurrence), the reminder is applied to every occurrence of
--   that series with event_date >= CURRENT_DATE — not just the one passed in.
--   Past occurrences are left untouched.
--   If the event is not recurring, only that single event gets the reminder.
--
-- If the exact same reminder_minutes was soft-deleted previously for a given
-- occurrence, this revives that row instead of inserting a duplicate
-- (UNIQUE constraint is on (user_id, event_id, reminder_minutes) regardless
-- of is_deleted).

CREATE OR REPLACE FUNCTION set_event_reminder(
    p_user_id          uuid,
    p_event_id         uuid,
    p_reminder_minutes int
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_date       date;
    v_parent_event_id  uuid;
    v_is_recurring     boolean;
    v_series_root      uuid;
    v_target_id        uuid;
    v_reminder_id      uuid;
    v_reminder_ids     uuid[] := ARRAY[]::uuid[];
    v_occurrence_count int    := 0;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_user_id IS NULL OR p_event_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_event_id are required');
    END IF;

    IF p_reminder_minutes IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_reminder_minutes is required');
    END IF;

    IF p_reminder_minutes < 1 OR p_reminder_minutes > 1440 THEN
        RETURN json_build_object('status', false, 'message', 'p_reminder_minutes must be between 1 and 1440');
    END IF;

    -- ── Event must exist and not be soft-deleted ──────────────────────────────
    SELECT event_date, parent_event_id, is_recurring
    INTO v_event_date, v_parent_event_id, v_is_recurring
    FROM event_mst
    WHERE event_id = p_event_id AND is_deleted = false;

    IF NOT FOUND THEN
        RETURN json_build_object('status', false, 'message', 'Event not found');
    END IF;

    -- ── Resolve the series root (parent) if this is a recurring event ────────
    -- COALESCE(parent_event_id, event_id): if p_event_id IS a child, its parent
    -- is v_parent_event_id; if p_event_id IS the parent/template, it is its own root.
    v_series_root := COALESCE(v_parent_event_id, p_event_id);

    -- ── Determine target occurrences ──────────────────────────────────────────
    FOR v_target_id IN
        SELECT event_id FROM event_mst
        WHERE CASE
                  WHEN v_is_recurring OR v_parent_event_id IS NOT NULL THEN
                      -- Recurring series: every child occurrence from today forward.
                      parent_event_id = v_series_root AND event_date >= CURRENT_DATE
                  ELSE
                      -- Non-recurring: just the single event itself.
                      event_id = p_event_id
              END
          AND is_deleted = false
    LOOP
        -- Reject exact duplicate (already active for this occurrence)
        IF EXISTS (
            SELECT 1 FROM event_reminders
            WHERE user_id = p_user_id AND event_id = v_target_id
              AND reminder_minutes = p_reminder_minutes AND is_deleted = false
        ) THEN
            CONTINUE;
        END IF;

        INSERT INTO event_reminders (id, user_id, event_id, reminder_minutes, is_notified, is_deleted, deleted_at, created_at, updated_at)
        VALUES (gen_random_uuid(), p_user_id, v_target_id, p_reminder_minutes, false, false, NULL, now(), now())
        ON CONFLICT (user_id, event_id, reminder_minutes)
        DO UPDATE SET is_deleted = false, deleted_at = NULL, is_notified = false, updated_at = now()
        RETURNING id INTO v_reminder_id;

        v_reminder_ids     := array_append(v_reminder_ids, v_reminder_id);
        v_occurrence_count := v_occurrence_count + 1;
    END LOOP;

    IF v_occurrence_count = 0 THEN
        RETURN json_build_object('status', false, 'message', 'A reminder already exists for this time on all applicable occurrences');
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Reminder added',
        'data', json_build_object(
            'reminder_minutes',    p_reminder_minutes,
            'occurrences_updated', v_occurrence_count,
            'reminder_ids',        v_reminder_ids
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

---

## Function Details

| Field | Value |
|-------|-------|
| **Name** | `set_event_reminder` |
| **Group** | Events |
| **Endpoint** | `POST /rpc/set_event_reminder` |
| **Tables** | `event_reminders` (INSERT, UPDATE), `event_mst` (SELECT) |
| **Security** | `SECURITY DEFINER` |

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | `uuid` | ✅ | The user adding the reminder |
| `p_event_id` | `uuid` | ✅ | Any event UUID in the series — parent template or a single child occurrence |
| `p_reminder_minutes` | `int` | ✅ | Minutes before event start to notify (1–1440) |

---

## Response (Success)

```json
{
    "status": true,
    "message": "Reminder added",
    "data": {
        "reminder_minutes": 10,
        "occurrences_updated": 12,
        "reminder_ids": ["b1e7...", "9ac2...", "..."]
    }
}
```

---

## Response (Error - Duplicate on all occurrences)

```json
{
    "status": false,
    "message": "A reminder already exists for this time on all applicable occurrences"
}
```

---

## Business Rules

1. A user may have any number of reminders per event (one per distinct `reminder_minutes` value) — **no cap**.
2. Duplicate `reminder_minutes` for the same user+occurrence is skipped, not an error, unless it's a duplicate on every targeted occurrence.
3. **Recurring events:** passing the parent template's `event_id` or any child occurrence's `event_id` applies the reminder to every occurrence with `event_date >= CURRENT_DATE`. Past occurrences are untouched.
4. **Non-recurring events:** only the single event passed gets the reminder.
5. Re-adding a previously removed (soft-deleted) reminder time on a given occurrence revives that row instead of creating a new one.
6. Event must exist and not be soft-deleted.

---

## Interaction with `delete_event_reminder`

Deleting a reminder is scoped to **one occurrence's row** (`reminder_id`), not the whole series — `set_event_reminder`'s bulk-apply is add-only, one-directional. Removing a reminder from a recurring series today means calling `delete_event_reminder` once per occurrence's `reminder_id` (returned by `get_event_reminder` called per event_id). Bulk-delete-across-series is not implemented; flag if this asymmetry needs to be resolved.
