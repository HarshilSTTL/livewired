# SP: `get_profile_by_userid`

**Endpoint:** `POST /rpc/get_profile_by_userid`
**Group:** Profile
**SQL:** [`functions/profiles/get_profile_by_userid.md`](../../../functions/profiles/get_profile_by_userid.md)
**Tables read:** `creator_profiles` · `creator_platform_accounts` · `profile_tags` · `follows`

---

## Overview

Returns **all profiles** belonging to a given `user_id`. Used for the **"Select Profile"
dropdown** and profile switcher in the app. Returns all statuses (`active`, `suspended`,
`deleted`) so the creator sees their complete list. Default profile is always first.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_user_id` | uuid | ✅ | The user whose profiles to fetch |

---

## Request Example

```json
{
  "p_user_id": "user-uuid"
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Profiles fetched successfully",
  "data": {
    "profiles": [
      {
        "profile_id":     "uuid",
        "profile_name":   "Gaming Channel",
        "username":       "handle123",
        "avatar_url":     "https://cdn.example.com/avatar.jpg",
        "bio":            "My gaming channel",
        "is_default":     true,
        "status":         "active",
        "show_followers": true,
        "followers":      142,
        "platforms": [
          {
            "platform_id":   1,
            "platform_name": "YouTube",
            "logo_url":      "https://cdn.example.com/yt.png",
            "channel_url":   "https://youtube.com/@handle123",
            "is_default":    true
          }
        ],
        "tags": [
          { "tag_id": 1, "tag_name": "Gaming" }
        ]
      }
    ]
  }
}
```

### No profiles yet
```json
{
  "status":  true,
  "message": "Profiles fetched successfully",
  "data": { "profiles": [] }
}
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Response Field Notes

| Field | Notes |
|---|---|
| `profiles` | Always array, `[]` if user has no profiles |
| `is_default` | Included — default profile sorted first |
| `followers` | Always shown — creator's own view, no show_followers restriction |
| `platforms` | Always array, `[]` if none |
| `tags` | Always array, `[]` if none |
| `avatar_url` | Nullable |
| `bio` | Nullable |

---

## Error Cases

| Message | Cause |
|---|---|
| `User ID is required` | `p_user_id` is null |
| `User not found` | No user with that ID in `users` table |
| `Something went wrong` | Unhandled exception |

---

## Logic Flow

```
1. Null check: p_user_id
2. Check user exists in users table
3. SELECT all profiles WHERE user_id = p_user_id
   ├── For each: COUNT follows WHERE is_active = true
   ├── For each: subquery platforms from creator_platform_accounts + platforms
   └── For each: subquery tags from profile_tags + tags
4. ORDER BY is_default DESC, created_at ASC
5. RETURN profiles array (empty [] if none)
```

---

## Key Differences vs `get_profile_by_username`

| Aspect | `get_profile_by_userid` | `get_profile_by_username` |
|---|---|---|
| Input | `p_user_id` (uuid) | `p_username` (text) |
| Returns | Array of all profiles | Single profile object |
| Use case | Creator's own profile switcher | Public profile view |
| `show_followers` respected? | No — always returns count | Yes — null if false |
| `is_default` in response | Yes | No |

---

## Related

- [`get_profile_by_username`](get_profile_by_username.md) — single public profile by username
- [`create_profile`](create_profile.md) — creates a profile
- [`update_profile`](update_profile.md) — updates a profile
- [`creator_profiles` table](../../database/tables/05_creator_profiles.md)
