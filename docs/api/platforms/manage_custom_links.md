# SP: `manage_custom_links`

**Endpoint:** `POST /rpc/manage_custom_links`
**Group:** Platforms
**SQL:** [`functions/platforms/manage_custom_links.md`](../../../functions/platforms/manage_custom_links.md)
**Tables written:** `profile_custom_links` (INSERT · UPDATE · soft-DELETE)
**Tables read:** `creator_profiles`

---

## Overview

Manages the Custom Links section on the profile edit screen. Called when the user hits **"Apply"**.

Handles add, edit, and soft-delete in a single call using a **replace-aware** pattern:

| Item in `p_links` | Action |
|---|---|
| `id = null` | INSERT new row |
| `id = <uuid>` | UPDATE existing row |
| Row in DB but **not in list** | Soft-delete (`is_deleted = true`) |
| `p_links = []` | Soft-delete ALL existing custom links |

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile whose custom links to manage |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_links` | jsonb | ✅ | Array of link objects (see format below) |

### `p_links` format

```json
[
  { "id": "existing-uuid", "platform_name": "Amazon",  "platform_url": "https://amazon.com/..." },
  { "id": null,            "platform_name": "Cashapp", "platform_url": "https://cash.app/..." }
]
```

| Field | Required | Description |
|---|---|---|
| `id` | ❌ | UUID of existing row — pass `null` for new links |
| `platform_name` | ✅ | Platform name — must not be empty |
| `platform_url` | ✅ | Full URL — must not be empty |

---

## Request Examples

### Add a new link
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_links": [
    { "id": null, "platform_name": "Amazon", "platform_url": "https://amazon.com/storefront/creator" }
  ]
}
```

### Edit an existing link
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_links": [
    { "id": "existing-uuid", "platform_name": "Amazon Store", "platform_url": "https://amazon.com/new-url" }
  ]
}
```

### Add one, keep one, delete one
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_links": [
    { "id": "uuid-1",  "platform_name": "Amazon",  "platform_url": "https://..." },
    { "id": null,      "platform_name": "Patreon",  "platform_url": "https://..." }
  ]
}
```
> Any row in the DB not included in this list is soft-deleted automatically.

### Clear all custom links
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_links": []
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Custom links updated successfully",
  "data": {
    "profile_id": "profile-uuid"
  }
}
```

### Error
```json
{
  "status":  false,
  "message": "<reason>"
}
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Profile ID is required` | `p_profile_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Links list is required` | `p_links` is null |
| `Profile not found or access denied` | Profile doesn't exist or belongs to a different user |
| `Platform name is required for each link` | Any item has empty `platform_name` |
| `URL is required for each link` | Any item has empty `platform_url` |
| `Something went wrong` | Unhandled exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Null check: p_profile_id, p_user_id, p_links
2. Ownership check: creator_profiles WHERE id = p_profile_id AND user_id = p_user_id
3. Validate each item: platform_name and platform_url must be non-empty
4. Build v_sent_ids = array of all IDs present in p_links (excludes nulls)
5. Soft-delete: UPDATE profile_custom_links SET is_deleted=true, deleted_at=now()
   WHERE profile_id = p_profile_id AND is_deleted=false AND id NOT IN v_sent_ids
6. For each item in p_links:
   ├── id present → UPDATE platform_name, platform_url, updated_at
   └── id null    → INSERT new row
7. Return success with profile_id
```

---

## Notes

- **Soft-delete only** — rows are never hard-deleted. `is_deleted = true` + `deleted_at = now()`.
- **Always send the full list** — missing items get soft-deleted. Frontend must include all links the user wants to keep.
- Use `get_profile_custom_links` first to load existing links before calling this SP.

---

## Related

- [`get_profile_custom_links`](get_profile_custom_links.md) — fetch existing custom links before editing
- [`profile_custom_links` table](../../database/tables/14_profile_custom_links.md)
