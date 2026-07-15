# `delete_event_reminder`

```sql
-- Function: delete_event_reminder
-- Group: Events
-- Endpoint: POST /rpc/delete_event_reminder
-- Tables:   event_reminders (UPDATE)
-- Doc: docs/api/events/delete_event_reminder.md
--
-- Soft-deletes ONE specific reminder belonging to the caller.
-- Since a user can have multiple reminders per event, p_reminder_id
-- identifies exactly which one to remove.

CREATE OR REPLACE FUNCTION delete_event_reminder(
    p_user_id     uuid,
    p_reminder_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_updated_id uuid;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_user_id IS NULL OR p_reminder_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_reminder_id are required');
    END IF;

    -- ── Soft delete, scoped to the caller so users can't remove others' reminders ─
    UPDATE event_reminders
    SET is_deleted = true, deleted_at = now(), updated_at = now()
    WHERE id      = p_reminder_id
      AND user_id = p_user_id
      AND is_deleted = false
    RETURNING id INTO v_updated_id;

    IF v_updated_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Reminder not found');
    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', 'Reminder removed',
        'data', json_build_object('reminder_id', v_updated_id)
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
| **Name** | `delete_event_reminder` |
| **Group** | Events |
| **Endpoint** | `POST /rpc/delete_event_reminder` |
| **Tables** | `event_reminders` (UPDATE) |
| **Security** | `SECURITY DEFINER` |

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | `uuid` | ✅ | The caller — must own the reminder |
| `p_reminder_id` | `uuid` | ✅ | The specific reminder row to remove (from `get_event_reminder`'s `reminders[].reminder_id`) |

---

## Response (Success)

```json
{
    "status": true,
    "message": "Reminder removed",
    "data": { "reminder_id": "b1e7..." }
}
```

---

## Response (Error - Not found / not owned)

```json
{
    "status": false,
    "message": "Reminder not found"
}
```

---

## Business Rules

1. Ownership-scoped: a user can only delete their own reminders (`user_id` must match)
2. Idempotent-safe: deleting an already-deleted or nonexistent reminder returns a clean error, not an exception
3. Soft delete only — row stays for audit/history, filtered out by `is_deleted = false` everywhere else
