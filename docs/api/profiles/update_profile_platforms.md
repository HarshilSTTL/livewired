# SP: `update_profile_platforms`

**Endpoint:** `POST /rpc/update_profile_platforms`
**Group:** Profiles
**SQL:** [`functions/profiles/update_profile_platforms.md`](../../../functions/profiles/update_profile_platforms.md)
**Tables written:** `creator_platform_accounts` (DELETE + INSERT)

---

## Overview

Dedicated SP for managing a creator's additional platform links (channel URLs per streaming platform).

Use this instead of `update_profile` when you only need to add, replace, or clear the creator's platform accounts — without touching any other profile fields.

**Semantics:**
- `p_platforms = [{...}]` → replace-all: clears existing, inserts new list
- `p_platforms = []` → clears all platform accounts
- `p_platforms = null` → error (required for this SP)

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile whose platforms to update |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_platforms` | jsonb | ✅ | Array of platform link objects (see format below) |

### `p_platforms` format

```json
[
  { "platform_id": 1, "channel_url": "https://youtube.com/@creator", "is_default": true },
  { "platform_id": 2, "channel_url": "https://twitch.tv/creator" }
]
```

| Field | Type | Required | Description |
|---|---|---|---|
| `platform_id` | int | ✅ | ID from `platforms` table (1=YouTube, 2=Twitch, 3=Kick, 4=Rumble) |
| `channel_url` | text | ✅ | Creator's channel URL on that platform |
| `is_default` | boolean | ❌ | Marks this as the creator's primary platform. Defaults to `false` |

---

## Request Examples

### Add / replace platform links
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms": [
    { "platform_id": 1, "channel_url": "https://youtube.com/@creator", "is_default": true },
    { "platform_id": 2, "channel_url": "https://twitch.tv/creator" }
  ]
}
```

### Add a single platform link
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms": [
    { "platform_id": 3, "channel_url": "https://kick.com/creator" }
  ]
}
```

### Clear all platform links
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_platforms":  []
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Profile platforms updated successfully",
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
| `Platforms list is required` | `p_platforms` is null |
| `Profile not found or access denied` | Profile doesn't exist or belongs to a different user |
| `One or more platform IDs are invalid` | A `platform_id` in the array doesn't exist in `platforms` table |
| `Channel URL is required for each platform` | A platform object is missing `channel_url` or it is empty |
| `Something went wrong` | Unhandled exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Null check: p_profile_id, p_user_id, p_platforms
2. Ownership check: creator_profiles WHERE id = p_profile_id AND user_id = p_user_id
3. Platform validation (if p_platforms non-empty):
   ├── All platform_ids must exist in platforms table
   └── channel_url must be non-null and non-empty for each entry
4. Fetch current username from creator_profiles (used in creator_platform_accounts.username)
5. DELETE all existing rows from creator_platform_accounts WHERE profile_id = p_profile_id
6. If p_platforms non-empty: INSERT each platform object as a new row
7. Return success with profile_id
```

---

## Notes

- **Replace-all semantics** — every call fully replaces the platform list. The frontend should always send the complete desired state (not a diff).
- `username` in `creator_platform_accounts` is auto-populated from the current profile username.
- Use `get_all_platforms` to fetch the list of valid platforms with their IDs and names for the dropdown.

---

## Related

- [`update_profile`](update_profile.md) — full profile update (includes platform management plus all other fields)
- [`get_all_platforms`](../platforms/get_all_platforms.md) — fetch available platforms for the dropdown
- [`get_profile_by_id`](get_profile_by_id.md) — read current profile state including platform accounts
- [`creator_platform_accounts` table](../../database/tables/06_creator_platform_accounts.md)
