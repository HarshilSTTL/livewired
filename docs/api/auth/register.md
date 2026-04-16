# SP: `register`

**Endpoint:** `POST /rpc/register`
**Group:** Auth
**Description:** Basic user registration. Inserts a new user into the `users` table. Earlier version — `signup` is the improved replacement.

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `p_email` | text | ✅ | — | User's email address |
| `p_password` | text | ✅ | — | User's password |
| `p_username` | text | ✅ | — | Unique account username — min 3 characters |
| `p_created_device_ip` | text | ❌ | null | Device IP at registration |

---

## Request Example

```json
{
  "p_email":    "harshil@gmail.com",
  "p_password": "mypassword123",
  "p_username": "harshil_dev"
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
| Email or password is null/empty | `"Email/Password is required"` |
| Username is null or empty | `"Username is required"` |
| Username shorter than 3 chars | `"Username must be at least 3 characters"` |
| Active account with same email exists | `"Email already exists"` |
| Email exists but account was deleted | Email was anonymized at deletion — fresh INSERT creates new UUID, zero old data |
| Any DB/runtime exception | `"Something went wrong"` + sqlerrm |

---

## Logic Flow

1. Validate email, password not null/empty
2. Validate username not null/empty, length ≥ 3
3. Check email in `users` WHERE `is_deleted = false`
4. If found → return `"Email already exists"`
5. If not found → INSERT new row (new UUID)
   Note: deleted accounts have their email anonymized in `delete_account`,
   so re-registration always lands here and creates a completely fresh account
6. Return `user_id` on success

---

## SQL Reference

See [`functions/auth/register.md`](../../../functions/auth/register.md)
