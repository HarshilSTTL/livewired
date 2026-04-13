# SP: `update_custom_link`

**Endpoint:** `POST /rpc/update_custom_link`
**Group:** Profiles
**SQL:** [`functions/profiles/update_custom_link.md`](../../../functions/profiles/update_custom_link.md)
**Tables written:** `profile_custom_links` (UPDATE)

---

## Overview

Updates `platform_name` and `platform_url` for one or more custom link rows in a single request. Each item must include the row `id`. Used when the user edits custom links in the Custom Links section and saves.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile the links belong to (ownership check) |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_links` | jsonb array | ✅ | Array of `{ id, platform_name, platform_url }` objects |

### `p_links` item shape

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | uuid | ✅ | `profile_custom_links.id` of the row to update |
| `platform_name` | text | ✅ | New display name |
| `platform_url` | text | ✅ | New URL |

---

## Request Example

```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_links": [
    { "id": "row-uuid-1", "platform_name": "My Portfolio", "platform_url": "https://myportfolio.com" },
    { "id": "row-uuid-2", "platform_name": "My Blog",      "platform_url": "https://myblog.com" }
  ]
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "2 custom link(s) updated successfully",
  "data": { "count": 2 }
}
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Profile ID is required` | `p_profile_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Links list is required` | `p_links` is null or empty array |
| `Profile not found or access denied` | Profile doesn't exist or belongs to a different user |
| `Something went wrong` | Unhandled exception |

---

## Notes

- Items missing `id`, `platform_name`, or `platform_url` are **silently skipped**
- Only rows that belong to `p_profile_id` and are not soft-deleted can be updated
- `data.count` reflects how many rows were actually updated
- Also sets `updated_at = now()` on each updated row

---

## Related

- [`get_profile_custom_links`](../../platforms/get_profile_custom_links.md) — fetch all custom links (use `custom_id` from here as the `id` in each item)
- [`add_custom_link`](add_custom_link.md) — add new custom links
- [`delete_custom_link`](delete_custom_link.md) — soft-delete a custom link
