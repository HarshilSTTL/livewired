# SP: `get_profile_by_id` (v1, v2, v2.1)

**Latest Endpoint:** `POST /rpc/get_profile_by_id_v2_1`
**Previous Endpoint:** `POST /rpc/get_profile_by_id_v2`
**Deprecated Endpoint:** `POST /rpc/get_profile_by_id`
**Group:** Profile
**SQL:** [`functions/profiles/get_profile_by_id.md`](../../../functions/profiles/get_profile_by_id.md)

## App Screen

![Profile View Screen](../../assets/screenshots/profile_view.png)

> This screen shows the profile header (avatar, name, followers, Unfollow/bell buttons) and the platform Links row.
> Save screenshot as: `docs/assets/screenshots/profile_view.png`
**Tables read:** `creator_profiles` · `creator_platform_accounts` · `profile_custom_links` · `profile_tags` · `follows` · `profile_link_preferences`

---

## Overview

Returns the **full detail** of a single profile by `profile_id`. Used after the user selects
a profile from the post-login picker — pass the `profile_id` returned by `get_user_profiles`
to load everything about that profile.

### Version Comparison

| Version | Endpoint | Ordering | Features |
|---------|----------|----------|----------|
| **v2.1** (Current) | `/rpc/get_profile_by_id_v2_1` | User preferences | All 3 groups, preference ordering, type field |
| **v2** | `/rpc/get_profile_by_id_v2` | ID-based (1→2→3→4) | Fixed platform order, platforms only |
| **v1** (Deprecated) | `/rpc/get_profile_by_id` | Database order | Unordered platforms |

### What's New in v2.1?

- **All 3 link groups:** Returns platforms (1-4) → additional links (5+) → custom links separately
- **Type identifier:** Each link has `type` field: "platform", "additional_link", or "custom_link"
- **Respects user preferences:** Links ordered by `profile_link_preferences` table
- **Separate fields:** Easier for UI to handle each group differently
- **Fallback ordering:** Uses ID-based ordering if no preferences exist

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

### Success (v2.1)
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
        "id":             "cpa-uuid-1",
        "platform_id":    1,
        "type":           "platform",
        "platform_name":  "YouTube",
        "logo_url":       "https://cdn.example.com/yt.png",
        "channel_url":    "https://youtube.com/@handle123",
        "is_default":     true
      },
      {
        "id":             "cpa-uuid-2",
        "platform_id":    2,
        "type":           "platform",
        "platform_name":  "Twitch",
        "logo_url":       "https://cdn.example.com/twitch.png",
        "channel_url":    "https://twitch.tv/handle123",
        "is_default":     false
      }
    ],
    "additional_links": [
      {
        "id":             "cpa-uuid-5",
        "platform_id":    5,
        "type":           "additional_link",
        "platform_name":  "Patreon",
        "logo_url":       "https://cdn.example.com/patreon.png",
        "channel_url":    "https://patreon.com/handle123",
        "is_default":     false
      }
    ],
    "custom_links": [
      {
        "id":             "pcl-uuid-1",
        "platform_id":    null,
        "type":           "custom_link",
        "platform_name":  "My Website",
        "logo_url":       null,
        "channel_url":    "https://mywebsite.com",
        "is_default":     false
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
| `platforms` | Array of main streaming platforms (IDs 1-4) with type="platform" |
| `additional_links` | Array of additional platform links (IDs 5+) with type="additional_link" |
| `custom_links` | Array of creator-defined custom links with type="custom_link" |
| `tags` | Always array, `[]` if none |
| `avatar` | Nullable |
| `bio` | Nullable |
| `created_at` / `updated_at` | Nullable timestamptz |

---

## Link Type Field Values

| Type Value | Description | Source |
|---|---|---|
| `"platform"` | Main streaming platforms (YouTube, Twitch, Kick, Rumble) | Platform IDs 1-4 |
| `"additional_link"` | Additional platform links (Patreon, Discord, etc.) | Platform IDs 5+ |
| `"custom_link"` | Creator-defined custom links | profile_custom_links table |

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
   ├── platforms: main platforms (1-4) ordered by preferences, type="platform"
   ├── additional_links: additional platforms (5+) ordered by preferences, type="additional_link"
   ├── custom_links: custom links ordered by preferences, type="custom_link"
   └── tags: subquery from profile_tags + tags
5. RETURN single profile object in data
```

---

## Typical Usage Flow

```
Login
  └── get_user_profiles(p_user_id)     → shows profile picker (name + avatar + default toggles)
        └── user selects a profile
              └── get_profile_by_id(p_profile_id)  → loads full profile detail with all 3 link groups
```

---

## Related

- [`get_user_profiles`](get_user_profiles.md) — lightweight post-login profile picker
- [`update_profile`](update_profile.md) — edit this profile
- [`reorder_social_links_v2`](reorder_social_links.md) — save link reordering
- [`creator_profiles` table](../../database/tables/05_creator_profiles.md)
