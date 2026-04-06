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
| Email already exists (case-insensitive) | `"Email already exists"` |
| Any DB/runtime exception | `"Something went wrong in signup"` + sqlerrm |

---

## Logic Flow

1. Validate email not null/empty
2. Validate password not null/empty
3. Validate username not null/empty
4. Validate username length ≥ 3
5. Case-insensitive username uniqueness check
6. Case-insensitive email uniqueness check
7. INSERT into `users` (email, password, username, device_ip)
8. Return `user_id` on success

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
