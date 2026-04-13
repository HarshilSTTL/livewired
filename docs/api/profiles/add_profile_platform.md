# SP: `add_profile_platform`

**Endpoint:** `POST /rpc/add_profile_platform`
**Group:** Profiles
**SQL:** [`functions/profiles/add_profile_platform.md`](../../../functions/profiles/add_profile_platform.md)
**Tables written:** `creator_platform_accounts` (INSERT)

---

## Overview

Inserts one new platform link for a creator profile. Used when the user adds a platform in the Toggle or Additional Links section and hits the "+" button.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile to add the platform link to |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_platform_id` | bigint | ✅ | Platform ID from `platforms` table |
| `p_channel_url` | text | ✅ | Full channel/stream URL |

---

## Request Example

```json
{
  "p_profile_id":  "profile-uuid",
  "p_user_id":     "user-uuid",
  "p_platform_id": 1,
  "p_channel_url": "https://youtube.com/@creator"
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Platform link added successfully",
  "data": {
    "id": "new-row-uuid"
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
| `Platform ID is required` | `p_platform_id` is null |
| `Channel URL is required` | `p_channel_url` is null or empty |
| `Profile not found or access denied` | Profile doesn't exist or belongs to a different user |
| `Platform ID is invalid` | `p_platform_id` not found in `platforms` table |
| `Something went wrong` | Unhandled exception |

---

## Related

- [`get_profile_platforms`](get_profile_platforms.md) — fetch all platform links for a profile
- [`update_profile_platform`](update_profile_platform.md) — update a platform link
- [`delete_profile_platform`](delete_profile_platform.md) — soft-delete a platform link
