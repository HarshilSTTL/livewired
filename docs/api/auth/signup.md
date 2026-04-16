# SP: `signup`

**Endpoint:** `POST /rpc/signup`
**Group:** Auth
**Description:** Improved user registration with full input validation. Preferred over `register`. Uses `SECURITY DEFINER`.

## App Screen

![Sign Up Screen](../../assets/screenshots/signup.png)

> Save screenshot as: `docs/assets/screenshots/signup.png`

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `p_email` | text | ✅ | — | User's email address |
| `p_password` | text | ✅ | — | User's password |
| `p_username` | text | ✅ | — | Unique account username — min 3 characters |
| `p_ip` | text | ❌ | `'::1'` | Device IP address |

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
  "user_id": 1,
  "message": "Registration successful"
}
```

### Fail — Email required
```json
{
  "status": false,
  "message": "Email is required"
}
```

### Fail — Password required
```json
{
  "status": false,
  "message": "Password is required"
}
```

### Fail — Username required
```json
{ "status": false, "message": "Username is required" }
```

### Fail — Username too short
```json
{ "status": false, "message": "Username must be at least 3 characters" }
```

### Fail — Username taken
```json
{ "status": false, "message": "Username already taken" }
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
  "message": "Something went wrong in signup",
  "error": "<sqlerrm>"
}
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| Email is null or empty | `"Email is required"` |
| Password is null or empty | `"Password is required"` |
| Username is null or empty | `"Username is required"` |
| Username shorter than 3 chars | `"Username must be at least 3 characters"` |
| Active account with same email exists | `"Email already exists"` |
| Email exists but account was deleted | Reactivates the old row with new credentials |
| Any DB/runtime exception | `"Something went wrong in signup"` + sqlerrm |

---

## Logic Flow

1. Validate email not null/empty
2. Validate password not null/empty
3. Validate username not null/empty
4. Validate username length ≥ 3
5. Look up email in `users` (returns `id` + `is_deleted`)
6. If found and `is_deleted = false` → return `"Email already exists"`
7. If found and `is_deleted = true` → reactivate: UPDATE row with new password/username, reset `is_deleted = false`, `deleted_at = null`
8. If not found → INSERT new row
9. Return `user_id` on success

---

## Differences vs `register`

| Feature | `register` | `signup` |
|---------|-----------|---------|
| Input validation | None | Email + Password required check |
| Email uniqueness check | Exact match | Case-insensitive (`lower()`) |
| Security | Standard | `SECURITY DEFINER` |
| Response `data` wrapper | `"data": { "user_id": ... }` | Flat: `"user_id": ...` |
| Error detail | `sqlerrm` only | Message + `sqlerrm` |

---

## SQL Reference

See [`functions/auth/signup.md`](../../../functions/auth/signup.md)
