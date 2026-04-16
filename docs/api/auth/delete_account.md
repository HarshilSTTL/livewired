# SP: `delete_account`

**Endpoint:** `POST /rpc/delete_account`
**Group:** Auth
**SQL:** [`functions/auth/delete_account.md`](../../../functions/auth/delete_account.md)
**Tables written:** `users` · `creator_profiles` · `event_mst`
**Tables hard deleted:** `auth.users`

---

## Overview

Deletes a user account using a hybrid strategy:

- **Soft delete** on `public.users`, `creator_profiles`, and `event_mst` — rows are retained for audit purposes (`is_deleted = true`, `deleted_at = now()`)
- **Hard delete** on `auth.users` — the Supabase Auth identity is fully erased

The hard delete on `auth.users` is required to:
1. Prevent Google OAuth from silently re-authenticating a deleted account
2. Allow the user to re-register with the same email/Google account as a brand new user
3. Comply with Google Play and Apple App Store account deletion policies

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The user account to delete |

---

## Request Example

```json
{
  "p_user_id": "uuid..."
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Account deleted successfully" }
```

### Not Found
```json
{ "status": false, "message": "User not found" }
```

### Error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Response Field Notes

| Field | Notes |
|-------|-------|
| Soft delete | Sets `users.is_deleted = true` + `deleted_at = now()` (audit trail retained) |
| Email anonymized | `users.email` is set to `deleted_<user_id>@deleted.invalid` — frees the UNIQUE slot |
| Profiles cascade | All `creator_profiles` rows with `user_id = p_user_id` get `status = 'deleted'` |
| Events cascade | All `event_mst` rows under those profiles get `is_deleted = true` |
| Hard delete | `auth.users` row is permanently removed — frees the email/OAuth identity |
| Already deleted | Returns "User not found" if account is already deleted |
| Re-registration | Because the email is freed, re-registration creates a new UUID — completely fresh account, no old data |
| Google OAuth | After deletion Google OAuth re-login creates a brand new account with no old data |

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id is required` | `p_user_id` is null |
| `User not found` | No user with that ID, or account already deleted |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null check: p_user_id
2. Existence check: users WHERE id = p_user_id AND is_deleted = false
3. Soft delete all events:
   UPDATE event_mst SET is_deleted = true, deleted_at = now()
   WHERE profile_id IN (SELECT id FROM creator_profiles WHERE user_id = p_user_id)
     AND is_deleted = false
4. Soft delete all profiles:
   UPDATE creator_profiles SET status = 'deleted', deleted_at = now()
   WHERE user_id = p_user_id AND status != 'deleted'
5. Soft delete the user row + anonymize email:
   UPDATE users SET is_deleted = true, deleted_at = now(),
                    email = 'deleted_' || user_id || '@deleted.invalid'
   WHERE id = p_user_id
   (anonymizing frees the UNIQUE email slot so re-registration creates a fresh UUID)
6. Hard delete from auth.users:
   DELETE FROM auth.users WHERE id = p_user_id
   (frees the Supabase Auth identity — blocks silent Google OAuth re-login)
7. Return success
```

---

## Related

- [`delete_profile`](../profiles/delete_profile.md) — delete a single profile without deleting the account
- [`login`](login.md) — will return error if user `is_deleted = true`
