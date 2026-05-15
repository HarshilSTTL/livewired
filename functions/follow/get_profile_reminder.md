# `get_profile_reminder`

```sql
-- Function: get_profile_reminder
-- Group: Follow
-- Endpoint: POST /rpc/get_profile_reminder
-- Tables:   follows (SELECT)
-- Doc: docs/api/follow/get_profile_reminder.md
--
-- Checks if a user has profile-level event notifications enabled for a profile they follow.
-- Returns notification status (event_notification_enabled) and notification_minutes if enabled.
-- This is for automatic profile-level event subscriptions (all events on the profile).
--
-- If user doesn't follow this profile (or follow is not active),
-- returns status: false with "User not followed" message.

CREATE OR REPLACE FUNCTION get_profile_reminder(
    p_user_id    uuid,
    p_profile_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reminder_enabled boolean;
    v_reminder_minutes int;
    v_follow_exists    boolean;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_user_id IS NULL OR p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_profile_id are required');
    END IF;

    -- ── Check if user follows this profile (active only) ──────────────────────
    SELECT event_notification_enabled, event_notification_minutes
    INTO v_reminder_enabled, v_reminder_minutes
    FROM follows
    WHERE user_id    = p_user_id
      AND profile_id = p_profile_id
      AND is_active  = true
    LIMIT 1;

    -- ── User doesn't follow this profile ─────────────────────────────────────
    IF v_reminder_enabled IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User not followed');
    END IF;

    -- ── Return reminder status ───────────────────────────────────────────────
    RETURN json_build_object(
        'status', true,
        'data', json_build_object(
            'has_reminder',    v_reminder_enabled,
            'reminder_minutes', CASE 
                                   WHEN v_reminder_enabled THEN v_reminder_minutes
                                   ELSE NULL
                               END
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
| **Name** | `get_profile_reminder` |
| **Group** | Follow |
| **Endpoint** | `POST /rpc/get_profile_reminder` |
| **Tables** | `follows` (SELECT) |
| **Security** | `SECURITY DEFINER` |

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | `uuid` | ✅ | The user checking their reminder status |
| `p_profile_id` | `uuid` | ✅ | The creator profile to check |

---

## Response (Success)

```json
{
    "status": true,
    "data": {
        "has_reminder": true,
        "reminder_minutes": 5
    }
}
```

Or when reminders are disabled:

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

## Response (Error)

**When user doesn't follow the profile:**
```json
{
    "status": false,
    "message": "User not followed"
}
```

**When required parameters are missing:**
```json
{
    "status": false,
    "message": "p_user_id and p_profile_id are required"
}
```

**When an exception occurs:**
```json
{
    "status": false,
    "message": "Something went wrong",
    "error": "<PostgreSQL error details>"
}
```

---

## Business Rules

1. Only checks **active** follows (`is_active = true`)
2. If user doesn't follow the profile → `status: false` with error message
3. If user follows but reminders are disabled → `has_reminder: false` and `reminder_minutes: null`
4. If user follows and reminders are enabled → `has_reminder: true` and `reminder_minutes: <value>`
