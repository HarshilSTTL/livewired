# SP: `delete_profile_platform`

**Endpoint:** `POST /rpc/delete_profile_platform`
**Group:** Profiles
**SQL:** [`functions/profiles/delete_profile_platform.md`](../../../functions/profiles/delete_profile_platform.md)
**Tables written:** `creator_platform_accounts` (UPDATE — soft delete)

---

## Overview

Soft-deletes a specific platform link row. Used when the user removes a platform from the Toggle or Additional Links section. Sets `is_deleted = true` and records `deleted_at`.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_id` | uuid | ✅ | `creator_platform_accounts.id` of the row to delete |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |

---

## Request Example

```json
{
  "p_id":      "row-uuid",
  "p_user_id": "user-uuid"
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Platform link deleted successfully" }
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Platform link ID is required` | `p_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Platform link not found or access denied` | Row doesn't exist, already soft-deleted, or belongs to a different user |
| `Something went wrong` | Unhandled exception |

---

## Notes

- Row is **not physically deleted** — `is_deleted` is set to `true` and `deleted_at` is timestamped
- `get_profile_platforms` and all profile read SPs automatically exclude soft-deleted rows
- Ownership verified by joining through `creator_profiles.user_id`

---

## Related

- [`get_profile_platforms`](get_profile_platforms.md) — fetch all platform links (use `id` from here)
- [`add_profile_platform`](add_profile_platform.md) — add a new platform link
- [`update_profile_platform`](update_profile_platform.md) — update a platform link
