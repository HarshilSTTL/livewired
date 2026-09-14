# SP: `skip_onboarding`

**Endpoint:** `POST /rpc/skip_onboarding`
**Group:** Auth
**SQL:** [`functions/auth/skip_onboarding.md`](../../../functions/auth/skip_onboarding.md)
**Tables written:** `users`

---

## Overview

Called when the user taps the **Skip Onboarding** button on the platform-choose / tag-suggestion screens shown right after first signup. Sets `onboarding_completed = true` on the user's row without saving any platform or tag selections.

Without this, a user who skips onboarding would see the same onboarding screens again on every subsequent login — `onboarding_completed` is the only signal the app uses to decide whether to show them, and it is **not** inferred from the presence of `user_preferred_platforms` / `user_interests` rows.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The authenticated user's ID |

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
  "message": "Onboarding skipped"
}
```

### Error
```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id is required` | `p_user_id` is null |
| `User not found` | No user with that ID, or user is soft-deleted |
| `Something went wrong` | Unhandled DB exception |

---

## Notes

- Idempotent — calling it again on an already-onboarded user just re-sets the same flag, no error.
- This, [`submit_platform`](../platforms/submit_platform.md), and [`submit_tags`](../tags/submit_tags.md) are the only three places that set `onboarding_completed = true`.
- Current value is returned by [`get_user_v2`](get_user.md) as `onboarding_completed`.

---

## Related

- [`get_user_v2`](get_user.md) — read current `onboarding_completed`
- [`submit_platform`](../platforms/submit_platform.md) — sets `onboarding_completed = true` after saving platform selections
- [`submit_tags`](../tags/submit_tags.md) — sets `onboarding_completed = true` after saving tag selections
