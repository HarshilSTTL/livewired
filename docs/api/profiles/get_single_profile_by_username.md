# SP: `get_single_profile_by_username`

**Endpoint:** `POST /rpc/get_single_profile_by_username`
**Group:** Profile
**SQL:** [`functions/profiles/get_single_profile_by_username.md`](../../../functions/profiles/get_single_profile_by_username.md)
**Tables read:** `creator_profiles` · `creator_platform_accounts` · `profile_tags` · `follows`

---

## Overview

Returns a single profile by its unique `username`. Used for the **public profile view page**
when a user taps on a creator's profile. Respects `show_followers` — if the creator has
disabled follower count visibility, `followers` returns `null`.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_username` | text | ✅ | The unique profile username to look up |

---

## Request Example

```json
{
  "p_username": "handle123"
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Profile fetched successfully",
  "data": {
    "profile_id":     "uuid",
    "profile_name":   "Gaming Channel",
    "username":       "handle123",
    "avatar_url":     "https://cdn.example.com/avatar.jpg",
    "bio":            "My gaming channel",
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
      { "tag_id": 1, "tag_name": "Gaming" },
      { "tag_id": 2, "tag_name": "Tech" }
    ]
  }
}
```

### show_followers = false
```json
{
  "followers": null
}
```
> All other fields are returned normally. Only `followers` becomes `null`.

### Error
```json
{
  "status":  false,
  "message": "<reason>"
}
```

---

## Response Field Notes

| Field | Notes |
|---|---|
| `data` | Single object (not array) |
| `followers` | `null` when `show_followers = false`; integer count otherwise |
| `status` | Returned as-is (`active` / `suspended` / `deleted`) — UI decides how to display |
| `platforms` | Always an array (`[]` if none linked) |
| `tags` | Always an array (`[]` if none selected) |
| `avatar_url` | Nullable |
| `bio` | Nullable |
| `is_default` | Not returned — irrelevant for public view |

---

## Error Cases

| Message | Cause |
|---|---|
| `Username is required` | `p_username` is null or empty string |
| `Profile not found` | No profile with that username |
| `Something went wrong` | Unhandled exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Null/empty check: p_username
2. SELECT id, show_followers FROM creator_profiles WHERE username = p_username
3. If not found → return Profile not found
4. SELECT full profile data:
   ├── followers: COUNT follows WHERE is_active = true — only if show_followers = true, else null
   ├── platforms: subquery from creator_platform_accounts + platforms JOIN
   └── tags: subquery from profile_tags + tags JOIN
5. RETURN single profile object in data
```

---

## Key Differences vs `get_profiles_by_username`

| Aspect | `get_single_profile_by_username` | `get_profiles_by_username` |
|---|---|---|
| Input | `p_username` (text) | `p_user_id` (uuid) |
| Returns | Single profile object | Array of all user's profiles |
| Use case | Public profile view page | Creator's own profile switcher |
| `show_followers` respected? | Yes — null if false | No — always returns count |
| `is_default` in response | No | Yes |

---

## Related

- [`get_profiles_by_username`](get_profiles_by_username.md) — all profiles for a user
- [`search_profiles`](../search/search_profiles.md) — search profiles by keyword
- [`follow_creator`](../follow/follow_creator.md) — follow this profile
- [`creator_profiles` table](../../database/tables/05_creator_profiles.md)
