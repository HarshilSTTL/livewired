# SP: `delete_custom_link`

**Endpoint:** `POST /rpc/delete_custom_link`
**Group:** Profiles
**SQL:** [`functions/profiles/delete_custom_link.md`](../../../functions/profiles/delete_custom_link.md)
**Tables written:** `profile_custom_links` (UPDATE — soft delete)

---

## Overview

Soft-deletes a specific custom link row. Used when the user removes a custom link from the Custom Links section. Sets `is_deleted = true` and records `deleted_at`.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_id` | uuid | ✅ | `profile_custom_links.id` of the row to delete |
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
{ "status": true, "message": "Custom link deleted successfully" }
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Custom link ID is required` | `p_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Custom link not found or access denied` | Row doesn't exist, already soft-deleted, or belongs to a different user |
| `Something went wrong` | Unhandled exception |

---

## Notes

- Row is **not physically deleted** — `is_deleted` is set to `true` and `deleted_at` is timestamped
- `get_profile_custom_links` automatically excludes soft-deleted rows
- Ownership verified by joining through `creator_profiles.user_id`

---

## Related

- [`get_profile_custom_links`](../../platforms/get_profile_custom_links.md) — fetch all custom links (use `id` from here)
- [`add_custom_link`](add_custom_link.md) — add a new custom link
- [`update_custom_link`](update_custom_link.md) — update a custom link
