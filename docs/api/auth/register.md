# SP: `register`

**Endpoint:** `POST /rpc/register`
**Group:** Auth
**Description:** Basic user registration. Inserts a new user into the `users` table. Earlier version — `signup` is the improved replacement.

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| email | text | Yes | — | User's email address |
| password | text | Yes | — | User's password |
| created_device_i | text | No | null | Device IP at registration |

> ⚠️ Note: Parameter is `created_device_i` (not `created_device_ip`) — both `created_device_ip` and `updated_device_ip` columns are set to this same value on insert.

---

## Request Example

```json
{
  "email": "harshil@gmail.com",
  "password": "mypassword123",
  "created_device_i": "192.168.1.1"
}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "User registered successfully",
  "data": {
    "user_id": 1
  }
}
```

### Fail — Email already exists
```json
{
  "status": false,
  "message": "Email already exists"
}
```

### Fail — Server error
```json
{
  "status": false,
  "message": "<sqlerrm error message>"
}
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| Email already in `users` table | `status: false, message: "Email already exists"` |
| Any DB/runtime exception | `status: false, message: sqlerrm` |

---

## Logic Flow

1. Check if email exists in `users` → return error if yes
2. INSERT into `users` (email, password, created_device_ip, updated_device_ip)
3. Return `user_id` on success
4. EXCEPTION block catches any other errors

---

## SQL Reference

See [`functions/auth/register.sql`](../../../functions/auth/register.sql)
