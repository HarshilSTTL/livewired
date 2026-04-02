# SP: `delete_account`

**Endpoint:** `POST /rpc/delete_account`
**Group:** Auth
**SQL:** [`functions/auth/delete_account.md`](../../../functions/auth/delete_account.md)
**Tables written:** `users` · `creator_profiles` · `event_mst`

---

## Overview

Soft deletes a user account. Sets `is_deleted = true` and `deleted_at = now()` on the `users` row. Also soft deletes all profiles (`status = 'deleted'`) and all events (`is_deleted = true`) belonging to that user.

The rows are **not removed** from the database. Required by Google Play and Apple App Store policies — both platforms mandate that apps offer an account deletion option.

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
| Soft delete | Sets `users.is_deleted = true` + `deleted_at = now()` |
| Profiles cascade | All `creator_profiles` rows with `user_id = p_user_id` get `status = 'deleted'` |
| Events cascade | All `event_mst` rows under those profiles get `is_deleted = true` |
| Already deleted | Returns "User not found" if account is already deleted |
| Re-login | After deletion the user can no longer log in (login SP checks `is_deleted = false`) |

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
5. Soft delete the user:
   UPDATE users SET is_deleted = true, deleted_at = now()
   WHERE id = p_user_id
6. Return success
```

---

## Related

- [`delete_profile`](../profiles/delete_profile.md) — delete a single profile without deleting the account
- [`login`](login.md) — will return error if user `is_deleted = true`
