# SP: `add_custom_link`

**Endpoint:** `POST /rpc/add_custom_link`
**Group:** Profiles
**SQL:** [`functions/profiles/add_custom_link.md`](../../../functions/profiles/add_custom_link.md)
**Tables written:** `profile_custom_links` (INSERT)

---

## Overview

Inserts multiple custom links for a creator profile in a single request. Each item in the array is inserted as a new row. Used when the user adds one or more free-text name + URL entries in the Custom Links section.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile to add the custom links to |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_links` | jsonb array | ✅ | Array of `{ profile_name, profile_url }` objects |

### `p_links` item shape

| Field | Type | Required | Description |
|---|---|---|---|
| `profile_name` | text | ✅ | Display name for the link (free text) |
| `profile_url` | text | ✅ | Full URL |

---

## Request Example

```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_links": [
    { "profile_name": "My Portfolio", "profile_url": "https://myportfolio.com" },
    { "profile_name": "My Blog",      "profile_url": "https://myblog.com" }
  ]
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "2 custom link(s) added successfully",
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

- Items with a missing `profile_name` or `profile_url` are **silently skipped** — the rest still save
- `data.count` reflects how many items were actually inserted (excluding skipped ones)
- Each item always creates a **new row** — use `update_custom_link` to edit existing ones
- Use `get_profile_custom_links` after this call to get the `id` of each newly created row

---

## Related

- [`get_profile_custom_links`](../../platforms/get_profile_custom_links.md) — fetch all custom links (use `id` from here for update/delete)
- [`update_custom_link`](update_custom_link.md) — update a custom link
- [`delete_custom_link`](delete_custom_link.md) — soft-delete a custom link
