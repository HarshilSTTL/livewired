# SP: `get_notifications`

**Endpoint:** `POST /rpc/get_notifications`
**Group:** Notifications
**SQL:** [`functions/notifications/get_notifications.md`](../../../functions/notifications/get_notifications.md)
**Tables read:** `notifications`

---

## Overview

Returns the authenticated user's notification history from the past 2 days, sorted latest first.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The authenticated user's ID |

---

## Request Example

```json
{
  "p_user_id": "uuid..."
}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Notifications fetched successfully",
  "data": [
    {
      "id":         "uuid",
      "title":      "Harshil Gaming goes live in 10 min!",
      "body":       "Valorant Ranked Grind",
      "data": {
        "type":             "reminder",
        "event_id":         "uuid",
        "profile_id":       "uuid",
        "reminder_minutes": 10
      },
      "is_read":    false,
      "created_at": "2026-04-09T14:30:00+00:00"
    }
  ]
}
```

> `data` always returns as an array — `[]` if no notifications in the past 2 days.

### Error
```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Response Fields

| Field | Source | Notes |
|-------|--------|-------|
| id | notifications.id | UUID |
| title | notifications.title | Push notification title |
| body | notifications.body | Push notification body (event title) |
| data | notifications.data | jsonb payload — type, event_id, profile_id, reminder_minutes |
| is_read | notifications.is_read | `false` = unread · `true` = read |
| created_at | notifications.created_at | UTC timestamp |

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id is required` | `p_user_id` is null |
| `Something went wrong` | Unhandled DB exception |

---

## Notes

- Only notifications created within the **past 2 days** (`NOW() - INTERVAL '2 days'`) are returned
- Results are ordered by `created_at DESC` (latest first)
- Returns `[]` (empty array) if the user has no notifications in that window — never `null`

---

## Related

- [`get_unread_notification_count`](get_unread_notification_count.md) — badge count for unread notifications
- [`mark_notifications_read`](mark_notifications_read.md) — mark all or specific notifications as read
- [`process_event_reminders`](../../../functions/notifications/process_event_reminders.md) — cron job that inserts notifications
