# SP: `get_user`

**Endpoint:** `POST /rpc/get_user`
**Group:** Auth
**SQL:** [`functions/auth/get_user.md`](../../../functions/auth/get_user.md)
**Tables read:** `users`

---

## Overview

Fetches a user's `username` and `email` by their `user_id`.

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

### Success
```json
{
  "status":  true,
  "message": "User fetched successfully",
  "data": {
    "user_id":  "178fa2d8-97a4-49e0-aa2c-763f35f36634",
    "username": "harshil_dev",
    "email":    "harshil@gmail.com"
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

## Logic Flow

```
1. Null check: p_user_id
2. SELECT id, email, username FROM users WHERE id = p_user_id AND is_deleted = false
3. If not found → "User not found"
4. Return user_id, username, email
```

---

## Related

- [`update_user`](update_user.md) — update username
- [`login`](login.md) — also returns username on successful login
- [`users` table](../../database/tables/02_users.md)
