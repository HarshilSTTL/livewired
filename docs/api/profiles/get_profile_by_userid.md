# SP: `get_profile_by_userid` (v1, v2, v2.1)

**Latest Endpoint:** `POST /rpc/get_profile_by_userid_v2_1`
**Previous Endpoint:** `POST /rpc/get_profile_by_userid_v2`
**Deprecated Endpoint:** `POST /rpc/get_profile_by_userid`
**Group:** Profile
**SQL:** [`functions/profiles/get_profile_by_userid.md`](../../../functions/profiles/get_profile_by_userid.md)
**Tables read:** `creator_profiles` · `creator_platform_accounts` · `profile_custom_links` · `profile_tags` · `follows` · `profile_link_preferences`

---

## Overview

Returns **all profiles** belonging to a given `user_id`. Used for the **"Select Profile"
dropdown** and profile switcher in the app. Returns all statuses (`active`, `suspended`,
`deleted`) so the creator sees their complete list. Default profile is always first.

### Version Comparison

| Version | Endpoint | Ordering | Features |
|---------|----------|----------|----------|
| **v2.1** (Current) | `/rpc/get_profile_by_userid_v2_1` | User preferences | All 3 groups, preference ordering, type field |
| **v2** | `/rpc/get_profile_by_userid_v2` | ID-based (1→2→3→4) | Fixed platform order, platforms only |
| **v1** (Deprecated) | `/rpc/get_profile_by_userid` | Database order | Unordered platforms |

### What's New in v2.1?

- **All 3 link groups:** Returns platforms (1-4) → additional links (5+) → custom links separately
- **Type identifier:** Each link has `type` field: "platform", "additional_link", or "custom_link"
- **Respects user preferences:** Links ordered by `profile_link_preferences` table for each profile
- **Per-profile ordering:** Each profile can have different link orders set independently
- **Separate fields:** Easier for UI to handle each group differently

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

### Success (v2.1)
```json
{
  "status":  true,
  "message": "Profiles fetched successfully",
  "data": {
    "profiles": [
      {
        "profile_id":          "uuid",
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
| `followers` | `null` if `show_followers = false` · count if `true` |
| `platforms` | Array of main streaming platforms (IDs 1-4) with type="platform" |
| `additional_links` | Array of additional platform links (IDs 5+) with type="additional_link" |
| `custom_links` | Array of creator-defined custom links with type="custom_link" |
| `tags` | Always array, `[]` if none |
| `avatar` | Nullable |
| `bio` | Nullable |

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
| `User ID is required` | `p_user_id` is null |
| `User not found` | No user with that ID in `users` table |
| `Something went wrong` | Unhandled exception |

---

## Logic Flow

```
1. Null check: p_user_id
2. Check user exists in users table
3. SELECT all profiles WHERE user_id = p_user_id
   ├── For each: followers = CASE WHEN show_followers = true → COUNT(is_active=true) ELSE null END
   ├── For each: platforms (IDs 1-4) ordered by preferences, type="platform"
   ├── For each: additional_links (IDs 5+) ordered by preferences, type="additional_link"
   ├── For each: custom_links ordered by preferences, type="custom_link"
   └── For each: subquery tags from profile_tags + tags
4. ORDER BY is_default DESC, created_at ASC
5. RETURN profiles array (empty [] if none)
```

---

## Related

- [`create_profile`](create_profile.md) — creates a profile
- [`update_profile`](update_profile.md) — updates a profile
- [`reorder_social_links_v2`](reorder_social_links.md) — save link reordering
- [`creator_profiles` table](../../database/tables/05_creator_profiles.md)
