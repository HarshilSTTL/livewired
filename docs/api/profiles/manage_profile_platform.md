# SP: `manage_profile_platform`

**Endpoint:** `POST /rpc/manage_profile_platform`
**Group:** Profiles
**SQL:** [`functions/profiles/manage_profile_platform.md`](../../../functions/profiles/manage_profile_platform.md)
**Tables written:** `creator_platform_accounts` (INSERT · UPDATE · soft-DELETE)

---

## Overview

Manages all platform links for a creator profile in a single request. Replace-aware — compares the sent list against existing DB rows to decide what to insert, update, or soft-delete.

| Item in `p_platforms` | Action |
|---|---|
| `id` present | UPDATE `channel_url` on that row |
| `id` null | INSERT new row |
| Row in DB but **not in list** | Soft-delete (`is_deleted = true`) |
| `p_platforms = []` | Soft-delete ALL platform links for the profile |

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile whose platform links to manage |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_platforms` | jsonb | ✅ | Array of platform link objects (see format below) |

### `p_platforms` item shape

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | uuid | ❌ | Row ID from `creator_platform_accounts` — omit or `null` for new links |
| `platform_id` | int | ✅ for new rows | Required when `id` is null (INSERT). Optional when `id` is present — send to change the platform, omit to keep it unchanged |
| `channel_url` | text | ✅ | Full channel / stream URL |

---

## Request Examples

### Add a new platform link
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms": [
    { "id": null, "platform_id": 1, "channel_url": "https://youtube.com/@handle" }
  ]
}
```

### Edit URL only (keep same platform)
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms": [
    { "id": "existing-uuid", "channel_url": "https://youtube.com/@newhandle" }
  ]
}
```

### Edit URL and change platform
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms": [
    { "id": "existing-uuid", "platform_id": 3, "channel_url": "https://kick.com/@handle" }
  ]
}
```

### Add one, keep one, delete one
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms": [
    { "id": "uuid-1", "channel_url": "https://youtube.com/@handle" },
    { "id": null,     "platform_id": 3, "channel_url": "https://kick.com/handle" }
  ]
}
```
> Any row in DB not included in this list is soft-deleted automatically.

### Clear all platform links
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms": []
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Platform links updated successfully",
  "data": {
    "profile_id": "profile-uuid"
  }
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
| `Platforms list is required` | `p_platforms` is null |
| `Profile not found or access denied` | Profile doesn't exist or belongs to a different user |
| `platform_id is required for new platform links` | A new item (id=null) is missing `platform_id` |
| `channel_url is required for each platform link` | Any item has empty `channel_url` |
| `Something went wrong` | Unhandled exception |

---

## Notes

- **Always send the full list** — any row in DB not in the list gets soft-deleted
- New items with an invalid `platform_id` (not in `platforms` table) are silently skipped
- Use `get_profile_platforms` first to load existing links and their `id` values before calling this SP

---

## Related

- [`get_profile_platforms`](get_profile_platforms.md) — fetch existing platform links before editing
- [`add_profile_platform`](add_profile_platform.md) — add-only SP (no delete)
- [`update_profile_platform`](update_profile_platform.md) — update single row
- [`delete_profile_platform`](delete_profile_platform.md) — delete single row
