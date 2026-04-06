# SP: `update_user`

**Endpoint:** `POST /rpc/update_user`
**Group:** Auth
**SQL:** [`functions/auth/update_user.md`](../../../functions/auth/update_user.md)
**Tables written:** `users` (UPDATE)

---

## Overview

Updates the `username` for an existing user.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The user's ID |
| `p_username` | text | ✅ | New username — min 3 characters |

---

## Request Example

```json
{
  "p_user_id":  "178fa2d8-97a4-49e0-aa2c-763f35f36634",
  "p_username": "new_username"
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "User updated successfully",
  "data": {
    "user_id":  "178fa2d8-97a4-49e0-aa2c-763f35f36634",
    "username": "new_username"
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

### Error — Username missing
```json
{
  "status":  false,
  "message": "Username is required"
}
```

### Error — Username too short
```json
{
  "status":  false,
  "message": "Username must be at least 3 characters"
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
| `Username is required` | `p_username` is null or empty |
| `Username must be at least 3 characters` | `p_username` length < 3 |
| `User not found` | No user with that ID, or user is soft-deleted |
| `Something went wrong` | Unhandled exception — `error` field contains detail |

---

## Logic Flow

```
1. Null check: p_user_id
2. Null/empty check: p_username
3. Length check: p_username >= 3 characters
4. Verify user exists (is_deleted = false)
5. UPDATE users SET username = trim(p_username), updated_at = now()
6. Return user_id + new username
```

---

## Related

- [`get_user`](get_user.md) — fetch current username and email
- [`users` table](../../database/tables/02_users.md)
