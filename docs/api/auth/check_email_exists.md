# SP: `check_email_exists`

**Endpoint:** `POST /rpc/check_email_exists`
**Group:** Auth
**Description:** Checks whether an active account exists for an email. Used on the Forgot Password screen **before** calling `resetPasswordForEmail`, so unknown emails get a clear "Please enter a valid email" message. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| p_email | text | Yes | Trimmed, matched case-insensitively |

## Request Example

```json
{ "p_email": "harshil@gmail.com" }
```

---

## Response

### Success — user exists
```json
{ "status": true, "message": "Email found" }
```

### Fail — no such user
```json
{ "status": false, "message": "Please enter a valid email" }
```

### Fail — Email required
```json
{ "status": false, "message": "Email is required" }
```

---

## App Flow (Forgot Password)

```dart
final res = await supabase.rpc('check_email_exists', params: {'p_email': email});
if (res['status'] != true) {
  showError(res['message']);   // "Please enter a valid email"
  return;
}
await supabase.auth.resetPasswordForEmail(email);   // then go to OTP screen
```

See [`forgot_password.md`](forgot_password.md) for the OTP and new-password steps.

---

## Notes

- Excludes soft-deleted users (`is_deleted = true`) → treated as not found.
- ⚠️ **Account enumeration trade-off:** this deliberately reveals whether an email is registered, reversing the earlier "always show generic success" decision in `forgot_password.md`. Mitigate by rate-limiting the endpoint (API gateway / Supabase rate limits) if abuse is a concern.
- Google-sign-in users also match; Supabase recovery will let them set a password.

## SQL Reference

See [`functions/auth/check_email_exists.md`](../../../functions/auth/check_email_exists.md)
