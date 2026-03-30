# SP: `signup`

**Endpoint:** `POST /rpc/signup`
**Group:** Auth
**Description:** Improved user registration with full input validation. Preferred over `register`. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| email | text | Yes | — | User's email address |
| password | text | Yes | — | User's password |
| ip | text | No | `'::1'` | Device IP (currently hardcoded to `::1` in INSERT) |

> ⚠️ Note: The `ip` parameter is accepted but the INSERT currently hardcodes `'::1'` for both `created_device_ip` and `updated_device_ip`.

---

## Request Example

```json
{
  "email": "harshil@gmail.com",
  "password": "mypassword123"
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
| Email is null or empty string | `"Email is required"` |
| Password is null or empty string | `"Password is required"` |
| Email already exists (case-insensitive check) | `"Email already exists"` |
| Any DB/runtime exception | `"Something went wrong in signup"` + sqlerrm |

---

## Logic Flow

1. Validate email not null/empty
2. Validate password not null/empty
3. Case-insensitive check: `lower(u.email) = lower(signup.email)` — return error if exists
4. INSERT into `users`
5. Return `user_id` on success
6. EXCEPTION block catches all other errors

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

See [`functions/auth/signup.sql`](../../../functions/auth/signup.sql)
