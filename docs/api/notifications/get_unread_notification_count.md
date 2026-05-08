# SP: `get_unread_notification_count`

**Endpoint:** `POST /rpc/get_unread_notification_count`
**Group:** Notifications
**SQL:** [`functions/notifications/get_unread_notification_count.md`](../../../functions/notifications/get_unread_notification_count.md)
**Tables read:** `notifications`

---

## Overview

Returns the number of unread notifications for the authenticated user. Use this to drive badge counters (e.g. the bell icon in the app header).

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
  "status":  true,
  "message": "Unread notification count fetched successfully",
  "data": {
    "unread_count": 3
  }
}
```

> `unread_count` is `0` when there are no unread notifications — never `null`.

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

- Counts **all** unread notifications for the user — not limited to a time window
- Call this on app launch and after `mark_notifications_read` to keep the badge in sync

---

## Related

- [`get_notifications`](get_notifications.md) — fetch notification list (includes `is_read` field)
- [`mark_notifications_read`](mark_notifications_read.md) — mark all or specific notifications as read
