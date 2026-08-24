# SP: `get_user`

## Versions

| Version | Function | Endpoint | Status |
|---------|----------|----------|--------|
| v2.0 | `get_user_v2` | `POST /rpc/get_user_v2` | ✅ Current |
| v1.0 | `get_user` | `POST /rpc/get_user` | ❌ Deprecated |

> **Use `get_user_v2`** — v1 is deprecated. Only difference is `is_push_enabled` in the response (see below).

**Group:** Auth
**SQL:** [`functions/auth/get_user.md`](../../../functions/auth/get_user.md)
**Tables read:** `users`

---

## Overview

Fetches a user's `username`, `email`, and notification-related flags by their `user_id`.

---

## v2.0 vs v1.0 — Response Fields

| | v2.0 (`get_user_v2`) | v1.0 (`get_user`) |
|---|---|---|
| `is_push_enabled` | ✅ Included | ❌ Not returned |
| Everything else | Identical | Identical |

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The user's ID |

---

## Request Example

```json
{
  "p_user_id": "178fa2d8-97a4-49e0-aa2c-763f35f36634"
}
```

---

## Response

### Success — v2.0 (`get_user_v2`)
```json
{
  "status":  true,
  "message": "User fetched successfully",
  "data": {
    "user_id":              "178fa2d8-97a4-49e0-aa2c-763f35f36634",
    "username":             "harshil_dev",
    "email":                "harshil@gmail.com",
    "is_email_verified":    true,
    "onboarding_completed": true,
    "is_push_enabled":      true
  }
}
```

### Success — v1.0 (`get_user`, deprecated)
```json
{
  "status":  true,
  "message": "User fetched successfully",
  "data": {
    "user_id":              "178fa2d8-97a4-49e0-aa2c-763f35f36634",
    "username":             "harshil_dev",
    "email":                "harshil@gmail.com",
    "is_email_verified":    true,
    "onboarding_completed": true
  }
}
```

### Error — User ID missing
```json
{
  "status":  false,
  "message": "User ID is required"
}
```

### Error — Not found
```json
{
  "status":  false,
  "message": "User not found"
}
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `User ID is required` | `p_user_id` is null |
| `User not found` | No user with that ID, or user is soft-deleted |
| `Something went wrong` | Unhandled exception — `error` field contains detail |

---

## Logic Flow (v2.0)

```
1. Null check: p_user_id
2. SELECT id, email, username, is_email_verified, onboarding_completed, is_push_enabled
   FROM users WHERE id = p_user_id AND is_deleted = false
3. If not found → "User not found"
4. Return user_id, username, email, is_email_verified, onboarding_completed, is_push_enabled
```

---

## Related

- [`update_user`](update_user.md) — update username
- [`update_push_preference`](../notifications/update_push_preference.md) — toggle `is_push_enabled`
- [`register_device_token`](../notifications/register_device_token.md) — register an FCM token for this user
- [`login`](login.md) — also returns username on successful login
- [`users` table](../../../schema/tables/02_users.md)
