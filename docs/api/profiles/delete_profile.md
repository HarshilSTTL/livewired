# SP: `delete_profile`

**Endpoint:** `POST /rpc/delete_profile`
**Group:** Profiles
**SQL:** [`functions/profiles/delete_profile.md`](../../../functions/profiles/delete_profile.md)
**Tables written:** `creator_profiles` · `event_mst`

---

## Overview

Soft deletes a creator profile. Sets `status = 'deleted'` and `deleted_at = now()` on the profile row. Also soft deletes all events belonging to that profile.

The row is **not removed** from the database — it is simply hidden from all public queries. Only the owner (`p_user_id`) can delete their own profile.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_profile_id` | uuid | ✅ | The profile to delete |
| `p_user_id` | uuid | ✅ | Must be the owner of this profile |

---

## Request Example

```json
{
  "p_profile_id": "uuid...",
  "p_user_id":    "uuid..."
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Profile deleted successfully" }
```

### Not Found / Access Denied
```json
{ "status": false, "message": "Profile not found or access denied" }
```

### Error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Response Field Notes

| Field | Notes |
|-------|-------|
| Soft delete | Sets `creator_profiles.status = 'deleted'` + `deleted_at = now()` |
| Events cascade | All `event_mst` rows with `profile_id = p_profile_id` are also soft deleted (`is_deleted = true`) |
| Already deleted | Returns "Profile not found or access denied" if profile is already deleted |
| Public reads | `get_profile_by_id`, `get_profile_by_username`, `get_profiles`, `get_event_list` all filter out deleted profiles automatically |

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_profile_id and p_user_id are required` | Either required param is null |
| `Profile not found or access denied` | No matching profile, already deleted, or belongs to a different user |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null check: p_profile_id, p_user_id
2. Ownership check:
   WHERE id = p_profile_id AND user_id = p_user_id AND status != 'deleted'
3. Soft delete all events:
   UPDATE event_mst SET is_deleted = true, deleted_at = now()
   WHERE profile_id = p_profile_id AND is_deleted = false
4. Soft delete the profile:
   UPDATE creator_profiles SET status = 'deleted', deleted_at = now()
   WHERE id = p_profile_id
5. Return success
```

---

## Related

- [`delete_account`](../auth/delete_account.md) — deletes the user account + all profiles
- [`update_profile`](update_profile.md) — edit instead of delete
- [`get_profile_by_id`](get_profile_by_id.md) — returns "Profile not found" for deleted profiles
