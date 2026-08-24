# SP: `update_push_preference`

**Endpoint:** `POST /rpc/update_push_preference`
**Group:** Notifications
**SQL:** [`functions/notifications/update_push_preference.md`](../../../functions/notifications/update_push_preference.md)
**Tables written:** `users`

---

## Overview

Turns push notifications on/off for the calling user's account. This is the flag the `push` Edge Function checks before calling FCM — see [`push` Edge Function](../../../supabase/functions/push/index.ts).

Does **not** affect in-app notifications — rows are still inserted into `notifications` and remain visible via `get_notifications` regardless of this setting. Only the actual FCM push send is gated.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The authenticated user's ID |
| `p_push_enabled` | boolean | ✅ | `true` to enable push, `false` to disable |

---

## Request Example

```json
{
  "p_user_id": "178fa2d8-97a4-49e0-aa2c-763f35f36634",
  "p_push_enabled": false
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Push preference updated successfully",
  "data": {
    "user_id":         "178fa2d8-97a4-49e0-aa2c-763f35f36634",
    "is_push_enabled": false
  }
}
```

### Error
```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id is required` | `p_user_id` is null |
| `p_push_enabled is required` | `p_push_enabled` is null |
| `User not found` | No user with that ID, or user is soft-deleted |
| `Something went wrong` | Unhandled DB exception |

---

## Notes

- Current value is returned by [`get_user_v2`](../auth/get_user.md) as `is_push_enabled`.
- This only controls whether the `push` Edge Function attempts to send — it cannot detect or override OS-level notification permission (if the user denies the permission prompt or disables notifications for the app in device settings, FCM sends will fail/silently drop regardless of this flag). See the "OS permission vs. app preference" note on [`push` Edge Function`](../../../supabase/functions/push/index.ts).

---

## Related

- [`get_user_v2`](../auth/get_user.md) — read current `is_push_enabled`
- [`register_device_token`](register_device_token.md) — register the device that will receive pushes
- [`push` Edge Function](../../../supabase/functions/push/index.ts)
