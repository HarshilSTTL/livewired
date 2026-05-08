# SP: `mark_notifications_read`

**Endpoint:** `POST /rpc/mark_notifications_read`
**Group:** Notifications
**SQL:** [`functions/notifications/mark_notifications_read.md`](../../../functions/notifications/mark_notifications_read.md)
**Tables written:** `notifications` (UPDATE)

---

## Overview

Marks notifications as read for the authenticated user. Supports two modes:

- **Mark all** — pass only `p_user_id` (omit `p_notification_ids`). Marks every unread notification for this user as read. Use this for a "Mark all as read" button.
- **Mark specific** — pass `p_notification_ids` with a list of UUIDs. Only those notifications are marked as read, and only if they belong to this user.

Already-read notifications are silently skipped in both modes.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The authenticated user's ID |
| `p_notification_ids` | uuid[] | ❌ | Specific notification IDs to mark as read. `null` (default) = mark all unread |

---

## Request Examples

### Mark all as read
```json
{
  "p_user_id": "uuid..."
}
```

### Mark specific notifications as read
```json
{
  "p_user_id":           "uuid...",
  "p_notification_ids":  ["notif-uuid-1", "notif-uuid-2"]
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "3 notification(s) marked as read"
}
```

> `message` includes the count of rows actually updated. `0 notification(s) marked as read` is a valid success response (e.g. all were already read).

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

- **Security:** `user_id` filter is always applied — users can only mark their own notifications. Passing another user's notification UUID is silently ignored (count = 0).
- **Idempotent:** Calling multiple times with the same IDs is safe — already-read rows are excluded from the UPDATE.

---

## Related

- [`get_notifications`](get_notifications.md) — fetch notification list (includes `is_read` field)
- [`get_unread_notification_count`](get_unread_notification_count.md) — badge count for unread notifications
