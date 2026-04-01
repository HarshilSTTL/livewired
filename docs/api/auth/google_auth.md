# SP: `google_auth`

**Endpoint:** `POST /rpc/google_auth`
**Group:** Auth
**SQL:** [`functions/auth/google_auth.md`](../../../functions/auth/google_auth.md)
**Tables written:** `users` (INSERT on first sign-in, SELECT on return visits)

---

## Overview

Handles both **Google signup** and **Google login** in a single call.

Call this SP from Flutter **after** `supabase.auth.signInWithOAuth(OAuthProvider.google)`
succeeds and you have the user's email from the Supabase session.

| Scenario | What happens |
|---|---|
| Email **not in users** table | New row inserted — `password = NULL`, `auth_provider = 'google'` |
| Email **already in users** table | Existing `user_id` returned — no insert, no error |
| Email exists with `auth_provider = 'email'` | Same account returned — no duplicate created |

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_email` | text | ✅ | Email returned from Supabase Google OAuth session |

---

## Request Example

```json
{
  "p_email": "user@gmail.com"
}
```

---

## Response

### First sign-in (signup)
```json
{
  "status":  true,
  "message": "Account created successfully",
  "data": {
    "user_id": "178fa2d8-97a4-49e0-aa2c-763f35f36634"
  }
}
```

### Returning user (login)
```json
{
  "status":  true,
  "message": "Login successful",
  "data": {
    "user_id": "178fa2d8-97a4-49e0-aa2c-763f35f36634"
  }
}
```

### Error
```json
{
  "status":  false,
  "message": "Email is required"
}
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Email is required` | `p_email` is null or empty |
| `Something went wrong` | Unhandled exception — `error` field contains detail |

---

## Logic Flow

```
1. Null check: p_email
2. SELECT id FROM users WHERE email = p_email
3. If found   → return user_id (login)
4. If not found → INSERT new user (password=NULL, auth_provider='google')
               → return new user_id (signup)
```

---

## Flutter Integration

```dart
// Step 1 — trigger Google OAuth via Supabase
await supabase.auth.signInWithOAuth(OAuthProvider.google);

// Step 2 — after redirect, get the email from the session
final email = supabase.auth.currentUser?.email;

// Step 3 — call your SP to get/create the user in your users table
final response = await supabase.rpc('google_auth', params: {
  'p_email': email,
});

// Step 4 — store the returned user_id and proceed normally
final userId = response['data']['user_id'];
```

---

## Database Change Required

Run this **once** in your Supabase SQL editor before deploying this SP:

```sql
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS auth_provider text DEFAULT 'email';
```

This adds the `auth_provider` column to your existing `users` table.
All existing users will automatically get `auth_provider = 'email'`.

---

## Related

- [`register`](register.md) — email/password signup (unchanged)
- [`login`](login.md) — email/password login (unchanged)
- [`users` table](../../database/tables/02_users.md)
