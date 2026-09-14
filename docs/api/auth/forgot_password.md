# Forgot Password (OTP via Email)

> ✅ **No stored procedure required.** Handled entirely by Supabase Auth's
> built-in recovery-OTP flow, called directly from the Flutter app via the
> Supabase client SDK. No custom table, no custom SQL function, no Edge
> Function. This supersedes the plain `resetPasswordForEmail` magic-link note
> in `docs/remaining_apis.md` — same call, but the email template is switched
> to send a 6-digit code instead of a link.

**Group:** Auth
**Screens:** Forgot Password (enter email) → Enter OTP + New Password

---

## One-time setup (Supabase Dashboard — not app code)

Authentication → Email Templates → **Reset Password**. Replace the default
link-based body with one that renders `{{ .Token }}` (the 6-digit OTP)
instead of `{{ .ConfirmationURL }}`. Example body:

```html
<h2>Reset your LiveWired password</h2>
<p>Your one-time code is:</p>
<h1>{{ .Token }}</h1>
<p>This code expires in 1 hour. If you didn't request this, ignore this email.</p>
```

Sent through the existing custom SMTP relay (Gmail, configured
2026-07-15 — see `updates/2026-07-15.md`), so no separate email-service
integration is needed.

---

## Step 1 — Request OTP

```dart
await supabase.auth.resetPasswordForEmail(email);
```

- Always returns success to the caller regardless of whether the email
  exists — **do not** report "email not found" in the UI; this prevents
  account enumeration (same intent as `login`'s shared error message, see
  `docs/api/auth/login.md`).
- Supabase generates the OTP, stores it hashed, sets its own expiry
  (default 1 hour), and enforces its own resend cooldown/rate limiting
  server-side — none of this needs to be built or configured in this repo's
  `system_config` table.

## Step 2 — Verify OTP

```dart
final res = await supabase.auth.verifyOTP(
  email: email,
  token: otp,          // the 6-digit code the user typed
  type: OtpType.recovery,
);
```

- On success this returns an authenticated **recovery session** for that
  user (short-lived, recovery-scoped).
- On failure (wrong code, expired code, too many attempts) Supabase throws
  an `AuthException` whose raw message is something like `"Token has
  expired or is invalid"` — **do not show that string to the user.** Catch
  it and map to app copy:

  ```dart
  try {
    final res = await supabase.auth.verifyOTP(
      email: email,
      token: otp,
      type: OtpType.recovery,
    );
  } on AuthException catch (e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('expired') || msg.contains('invalid')) {
      showError('OTP is invalid or expired');
    } else {
      showError('Something went wrong. Please try again.');
    }
  }
  ```

  Match on `contains('expired')`/`contains('invalid')` rather than the
  exact string — Supabase's wording isn't a stable contract across SDK
  versions.

## Step 3 — Set new password

```dart
await supabase.auth.updateUser(
  UserAttributes(password: newPassword),
);
```

- Must be called while the recovery session from Step 2 is still active.
- Client-side validate `newPassword` length against
  `password_min_length` / `password_max_length` from `system_config`
  (same values `signup`/`register` would have used) before calling, so the
  user gets instant feedback instead of waiting on a Supabase error.

---

## Error Cases

| Scenario | Handling |
|----------|----------|
| Email doesn't exist | `resetPasswordForEmail` still returns success — show the generic "check your email" message |
| Wrong/expired OTP | `verifyOTP` throws — show "Invalid or expired code", let user retry or resend |
| New password too short/long | Validate client-side against `password_min_length`/`password_max_length` before calling `updateUser` |
| `updateUser` called without a valid recovery session | Throws — user must restart the flow from Step 1 |

---

## Notes

- Nothing in `public.users` changes — `is_email_verified`, `role_id`, etc.
  are untouched by a password reset.
- No new schema, no new SQL function. If a future requirement needs
  server-side control over OTP format/expiry/attempt-limits beyond what
  Supabase Auth offers, that would require a custom `password_reset_otps`
  table + SQL functions + a service-role Edge Function (rejected for now —
  see the 2026-08-20 update log for why).

## SQL Reference

None — this flow has no corresponding file under `functions/`.
