# SP: `get_profile_by_id`

**Endpoint:** `POST /rpc/get_profile_by_id`
**Group:** Profile
**SQL:** [`functions/profiles/get_profile_by_id.md`](../../../functions/profiles/get_profile_by_id.md)

## App Screen

![Profile View Screen](../../assets/screenshots/profile_view.png)

> This screen shows the profile header (avatar, name, followers, Unfollow/bell buttons) and the platform Links row.
> Save screenshot as: `docs/assets/screenshots/profile_view.png`
**Tables read:** `creator_profiles` · `creator_platform_accounts` · `profile_tags` · `follows`

---

## Overview

Returns the **full detail** of a single profile by `profile_id`. Used after the user selects
a profile from the post-login picker — pass the `profile_id` returned by `get_user_profiles`
to load everything about that profile.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | The profile ID to fetch |

---

## Request Example

```json
{
  "p_profile_id": "profile-uuid"
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
    "profile_id":          "uuid",
    "user_id":             "user-uuid",
    "profile_name":        "Gaming Channel",
    "avatar":              "<base64-encoded-image>",
    "bio":                 "My gaming channel",
    "is_default":          true,
    "status":              "active",
    "show_followers":      true,
    "twitch_by_default":   false,
    "kick_by_default":     false,
    "followers":           142,
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
    ],
    "created_at": "2026-03-01T10:00:00+00:00",
    "updated_at": "2026-03-15T14:30:00+00:00"
  }
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
| `data` | Single object (not array) |
| `user_id` | Owner of the profile |
| `followers` | `null` if `show_followers = false`; integer count otherwise |
| `status` | `active` / `suspended` / `deleted` |
| `platforms` | Always array, `[]` if none |
| `tags` | Always array, `[]` if none |
| `avatar` | Nullable |
| `bio` | Nullable |
| `created_at` / `updated_at` | Nullable timestamptz |

---

## Error Cases

| Message | Cause |
|---|---|
| `Profile ID is required` | `p_profile_id` is null |
| `Profile not found` | No profile with that ID |
| `Something went wrong` | Unhandled exception |

---

## Logic Flow

```
1. Null check: p_profile_id
2. SELECT id FROM creator_profiles WHERE id = p_profile_id
3. If not found → return error
4. SELECT full profile with:
   ├── followers: COUNT if show_followers = true, else null
   ├── platforms: subquery from creator_platform_accounts + platforms
   └── tags: subquery from profile_tags + tags
5. RETURN single profile object in data
```

---

## Typical Usage Flow

```
Login
  └── get_user_profiles(p_user_id)     → shows profile picker (name + avatar only)
        └── user selects a profile
              └── get_profile_by_id(p_profile_id)  → loads full profile detail
```

---

## Related

- [`get_user_profiles`](get_user_profiles.md) — lightweight post-login profile picker
- [`update_profile`](update_profile.md) — edit this profile
- [`creator_profiles` table](../../database/tables/05_creator_profiles.md)
