# SP: `unregister_device_token`

**Endpoint:** `POST /rpc/unregister_device_token`
**Group:** Notifications
**SQL:** [`functions/notifications/unregister_device_token.md`](../../../functions/notifications/unregister_device_token.md)
**Tables written:** `device_tokens`

---

## Overview

Call this at logout, **before** clearing the local session/token, using the same FCM
token that was registered via `register_device_token`. Soft-deletes it
(`is_active = false`) so the device stops receiving push for this account.

Closes the gap where a logged-out device kept receiving push tied to the account
it just logged out of, until the token naturally went stale.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The user who is logging out |
| `p_token` | text | ✅ | The FCM token registered on this device |

---

## Request Example

```json
{
  "p_user_id": "178fa2d8-97a4-49e0-aa2c-763f35f36634",
  "p_token": "d3f4...long-fcm-token..."
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Token unregistered" }
```

> Returns success even if no matching row existed (nothing to unregister) — logout
> should never be blocked by this call failing to find a token.

### Error
```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id and p_token are required` | either param is null |
| `Something went wrong` | Unhandled DB exception |

---

## Notes

- If the same device later logs into a **different** account, `register_device_token`
  already reassigns the token automatically — this call isn't required for that case,
  only for "log out and don't log into anything else on this device."
- Fire-and-forget on the client: don't block the logout flow waiting on this call.

---

## Related

- [`register_device_token`](register_device_token.md) — registers/reactivates a token
- [`device_tokens` table](../../../schema/tables/20_device_tokens.md)
