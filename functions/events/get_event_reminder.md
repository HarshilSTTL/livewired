# `get_event_reminder`

```sql
-- Function: get_event_reminder
-- Group: Events
-- Endpoint: POST /rpc/get_event_reminder
-- Tables:   event_reminders (SELECT)
-- Doc: docs/api/events/get_event_reminder.md
--
-- Retrieves the reminder configuration for a specific event that a user has set.
-- Returns whether a reminder exists and at what interval (in minutes before event).
--
-- If no active reminder exists for this user+event combination,
-- returns status: true with has_reminder: false.

CREATE OR REPLACE FUNCTION get_event_reminder(
    p_user_id  uuid,
    p_event_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reminder_minutes int;
    v_reminder_exists  boolean;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_user_id IS NULL OR p_event_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_event_id are required');
    END IF;

    -- ── Check if user has an active reminder for this event ───────────────────
    SELECT reminder_minutes
    INTO v_reminder_minutes
    FROM event_reminders
    WHERE user_id  = p_user_id
      AND event_id = p_event_id
      AND is_deleted = false
    LIMIT 1;

    -- ── Reminder doesn't exist or is deleted ─────────────────────────────────
    IF v_reminder_minutes IS NULL THEN
        RETURN json_build_object(
            'status', true,
            'data', json_build_object(
                'has_reminder',    false,
                'reminder_minutes', NULL
            )
        );
    END IF;

    -- ── Return reminder details ──────────────────────────────────────────────
    RETURN json_build_object(
        'status', true,
        'data', json_build_object(
            'has_reminder',    true,
            'reminder_minutes', v_reminder_minutes
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
| **Name** | `get_event_reminder` |
| **Group** | Events |
| **Endpoint** | `POST /rpc/get_event_reminder` |
| **Tables** | `event_reminders` (SELECT) |
| **Security** | `SECURITY DEFINER` |

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | `uuid` | ✅ | The user checking their reminder |
| `p_event_id` | `uuid` | ✅ | The event UUID to check |

---

## Response (Success - Reminder exists)

```json
{
    "status": true,
    "data": {
        "has_reminder": true,
        "reminder_minutes": 15
    }
}
```

---

## Response (Success - No reminder)

```json
{
    "status": true,
    "data": {
        "has_reminder": false,
        "reminder_minutes": null
    }
}
```

---

## Response (Error - Missing parameters)

```json
{
    "status": false,
    "message": "p_user_id and p_event_id are required"
}
```

---

## Business Rules

1. Only checks **active** reminders (`is_deleted = false`)
2. Returns `has_reminder: false` if no reminder exists or reminder is deleted
3. When a reminder exists, `reminder_minutes` contains the notification lead time (1–1440 minutes)
4. Does NOT validate if the event exists — returns `has_reminder: false` if no reminder found
