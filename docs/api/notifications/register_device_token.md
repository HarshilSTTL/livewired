# SP: `register_device_token`

**Endpoint:** `POST /rpc/register_device_token`
**Group:** Notifications
**SQL:** [`functions/notifications/register_device_token.md`](../../../functions/notifications/register_device_token.md)
**Tables written:** `device_tokens`

---

## Overview

> **Already live in production, undocumented until now** — confirmed signature is
> `register_device_token(p_user_id uuid, p_token text, p_platform text DEFAULT 'android')`.

Registers (or refreshes) the FCM token for the calling user's current device. Call this:

- Right after the app receives OS push permission and obtains an FCM token for the first time
- Whenever Firebase fires `onTokenRefresh` with a new token
- On login, in case the device previously belonged to a different account

Upserts on `(user_id, fcm_token)` — safe to call every app start with the same token.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The authenticated user's ID |
| `p_token` | text | ✅ | The FCM registration token from Firebase |
| `p_platform` | text | ❌ | `'android'` (default) \| `'ios'` \| `'web'` |

---

## Request Example

```json
{
  "p_user_id": "178fa2d8-97a4-49e0-aa2c-763f35f36634",
  "p_token": "d3f4...long-fcm-token...",
  "p_platform": "android"
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Token registered" }
```

### Error
```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id and p_token are required` | `p_user_id` or `p_token` is null |
| `User not found` | No user with that ID, or user is soft-deleted |
| `Something went wrong` | Unhandled DB exception |

---

## Notes

- If the same `fcm_token` was previously registered to a **different** user (e.g. a shared/reused device where someone logged out and a different account logged in), the token is reassigned to the calling user and removed from the old owner's rows — the old account stops receiving push on that device, which is the correct behavior.
- This does not affect in-app notifications (`get_notifications`) — only which devices receive FCM pushes.
- Requires a `UNIQUE (user_id, fcm_token)` constraint on `device_tokens` — see [`schema/tables/20_device_tokens.md`](../../../schema/tables/20_device_tokens.md).

---

## Related

- [`update_push_preference`](update_push_preference.md) — master on/off switch for push, independent of registered tokens
- [`device_tokens` table](../../../schema/tables/20_device_tokens.md)
- [`push` Edge Function](../../../supabase/functions/push/index.ts) — reads this table when sending
