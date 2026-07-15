# `get_event_reminder`

```sql
-- Function: get_event_reminder
-- Group: Events
-- Endpoint: POST /rpc/get_event_reminder
-- Tables:   event_reminders (SELECT)
-- Doc: docs/api/events/get_event_reminder.md
--
-- Retrieves ALL active reminders a user has set for a specific event.
-- A user may have multiple reminders on the same event (e.g. 1 day before,
-- 1 hour before, 10 minutes before) — this returns every one of them.
--
-- If no active reminders exist for this user+event combination,
-- returns status: true with has_reminder: false and an empty reminders array.

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
    v_reminders json;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_user_id IS NULL OR p_event_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_event_id are required');
    END IF;

    -- ── Collect all active reminders for this user+event ─────────────────────
    SELECT json_agg(
               json_build_object(
                   'reminder_id',      er.id,
                   'reminder_minutes', er.reminder_minutes
               )
               ORDER BY er.reminder_minutes
           )
    INTO v_reminders
    FROM event_reminders er
    WHERE er.user_id  = p_user_id
      AND er.event_id = p_event_id
      AND er.is_deleted = false;

    RETURN json_build_object(
        'status', true,
        'data', json_build_object(
            'has_reminder', v_reminders IS NOT NULL,
            'reminders',    COALESCE(v_reminders, '[]'::json)
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
| `p_user_id` | `uuid` | ✅ | The user checking their reminders |
| `p_event_id` | `uuid` | ✅ | The event UUID to check |

---

## Response (Success - Reminders exist)

```json
{
    "status": true,
    "data": {
        "has_reminder": true,
        "reminders": [
            { "reminder_id": "b1e7...", "reminder_minutes": 10 },
            { "reminder_id": "9ac2...", "reminder_minutes": 60 },
            { "reminder_id": "44d0...", "reminder_minutes": 1440 }
        ]
    }
}
```

---

## Response (Success - No reminders)

```json
{
    "status": true,
    "data": {
        "has_reminder": false,
        "reminders": []
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

1. Only returns **active** reminders (`is_deleted = false`)
2. Returns `has_reminder: false` and `reminders: []` if none exist
3. `reminders` is sorted ascending by `reminder_minutes`
4. Does NOT validate if the event exists — returns an empty list if no reminders found

---

## Breaking Change (v2 shape)

Prior versions of this function returned a single `reminder_minutes` field
(`{ "has_reminder": true, "reminder_minutes": 15 }`). Callers must migrate to
reading the `reminders` array instead — a single event may now have more than
one reminder for the same user.
