# SP: `clear_notifications`

**Endpoint:** `POST /rpc/clear_notifications`
**Group:** Notifications
**SQL:** [`functions/notifications/clear_notifications.md`](../../../functions/notifications/clear_notifications.md)
**Tables written:** `notifications` (UPDATE)

---

## Overview

Clears (hides) notifications for the authenticated user. Supports two modes:

- **Clear all** — pass only `p_user_id` (omit `p_notification_ids`). Clears every notification for this user that is not already cleared. Use this for a "Clear all notifications" button.
- **Clear specific** — pass `p_notification_ids` with a list of UUIDs. Only those notifications are cleared, and only if they belong to this user.

Already-cleared notifications are silently skipped in both modes.

**Effect:** Cleared notifications are hidden from `get_notifications` list and excluded from `get_unread_notification_count`, but are not deleted from the database.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The authenticated user's ID |
| `p_notification_ids` | uuid[] | ❌ | Specific notification IDs to clear. `null` (default) = clear all |

---

## Request Examples

### Clear all notifications

```json
{
  "p_user_id": "uuid..."
}
```

### Clear specific notifications

```json
{
  "p_user_id":           "uuid...",
  "p_notification_ids":  ["notif-uuid-1", "notif-uuid-2", "notif-uuid-3"]
}
```

---

## Response

### Success

```json
{
  "status":  true,
  "message": "3 notification(s) cleared"
}
```

> `message` includes the count of rows actually updated. `0 notification(s) cleared` is a valid success response (e.g. all were already cleared).

### Error

```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id is required` | `p_user_id` is null |
| `Something went wrong` | Unhandled DB exception |

---

## Notes

- **Security:** `user_id` filter is always applied — users can only clear their own notifications. Passing another user's notification UUID is silently ignored (count = 0).
- **Idempotent:** Calling multiple times with the same IDs is safe — already-cleared rows are excluded from the UPDATE.
- **Database behavior:** Cleared notifications remain in the database (not deleted), but are hidden from API responses and excluded from unread counts.
- **Related state:** A notification can be both `is_read = true` and `is_cleared = true`. Clearing a notification does NOT automatically mark it as read.

---

## Side Effects

When a notification is cleared:

1. **`get_notifications`** — The cleared notification no longer appears in the list (filtered by `is_cleared = false`)
2. **`get_unread_notification_count`** — If the notification had `is_read = false`, it is now excluded from the count (filtered by `is_cleared = false`)

---

## Related

- [`get_notifications`](get_notifications.md) — fetch notification list (includes `is_read` field, filtered to exclude cleared)
- [`get_unread_notification_count`](get_unread_notification_count.md) — badge count for unread notifications (excludes cleared)
- [`mark_notifications_read`](mark_notifications_read.md) — mark notifications as read (without clearing)
