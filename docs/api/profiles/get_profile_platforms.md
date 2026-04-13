# SP: `get_profile_platforms`

**Endpoint:** `POST /rpc/get_profile_platforms`
**Group:** Profiles
**SQL:** [`functions/profiles/get_profile_platforms.md`](../../../functions/profiles/get_profile_platforms.md)
**Tables read:** `creator_platform_accounts` · `platforms` · `creator_profiles`

---

## Overview

Returns all active (non-deleted) platform links for a creator profile. Used to populate the Toggle and Additional Links sections when the profile edit screen opens.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile whose platform links to fetch |

---

## Request Example

```json
{ "p_profile_id": "profile-uuid" }
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Platform links fetched successfully",
  "data": [
    {
      "id":            "row-uuid",
      "platform_id":   1,
      "platform_name": "YouTube",
      "logo_url":      "https://...",
      "channel_url":   "https://youtube.com/@creator",
      "is_default":    true
    },
    {
      "id":            "row-uuid",
      "platform_id":   2,
      "platform_name": "Twitch",
      "logo_url":      "https://...",
      "channel_url":   "https://twitch.tv/creator",
      "is_default":    false
    }
  ]
}
```

### Success — No platform links
```json
{ "status": true, "message": "Platform links fetched successfully", "data": [] }
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
| `Profile not found` | No profile with that ID |
| `Something went wrong` | Unhandled exception |

---

## Notes

- `id` in each row is the `creator_platform_accounts.id` — use this for `update_profile_platform` and `delete_profile_platform` calls
- Only returns active rows — soft-deleted entries are excluded
- `data` is always an array, never null

---

## Related

- [`add_profile_platform`](add_profile_platform.md) — add a new platform link
- [`update_profile_platform`](update_profile_platform.md) — update a platform link
- [`delete_profile_platform`](delete_profile_platform.md) — soft-delete a platform link
