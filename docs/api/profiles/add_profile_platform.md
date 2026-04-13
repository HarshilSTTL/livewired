# SP: `add_profile_platform`

**Endpoint:** `POST /rpc/add_profile_platform`
**Group:** Profiles
**SQL:** [`functions/profiles/add_profile_platform.md`](../../../functions/profiles/add_profile_platform.md)
**Tables written:** `creator_platform_accounts` (INSERT / UPDATE)

---

## Overview

Adds or updates multiple platform links for a creator profile in a single request. Each item in the array is upserted — if the platform already has an active row it updates the `channel_url`, otherwise it inserts a new row.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile to add the platform links to |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_platforms` | jsonb array | ✅ | Array of `{ platform_id, channel_url }` objects |

### `p_platforms` item shape

| Field | Type | Required | Description |
|---|---|---|---|
| `platform_id` | int | ✅ | ID from the `platforms` table |
| `channel_url` | text | ✅ | Full channel / stream URL |

---

## Request Example

```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms": [
    { "platform_id": 1, "channel_url": "https://youtube.com/@handle" },
    { "platform_id": 2, "channel_url": "https://twitch.tv/handle" },
    { "platform_id": 3, "channel_url": "https://kick.com/handle" }
  ]
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "3 platform link(s) saved successfully",
  "data": { "count": 3 }
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
| `Platforms list is required` | `p_platforms` is null or empty array |
| `Profile not found or access denied` | Profile doesn't exist or belongs to a different user |
| `Something went wrong` | Unhandled exception |

---

## Notes

- Items with a missing/invalid `platform_id` or empty `channel_url` are **silently skipped** — the rest still save
- Items with an invalid `platform_id` (not in `platforms` table) are also skipped
- **Upsert behaviour:** if an active row already exists for that platform, `channel_url` is updated rather than duplicated
- `data.count` reflects how many items were actually saved (excluding skipped ones)

---

## Related

- [`get_profile_platforms`](get_profile_platforms.md) — fetch all active platform links
- [`update_profile_platform`](update_profile_platform.md) — update a single platform link by row id
- [`delete_profile_platform`](delete_profile_platform.md) — soft-delete a platform link
