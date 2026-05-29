# SP: `get_profile_platforms` (v1, v2, v2.1)

**Latest Endpoint:** `POST /rpc/get_profile_platforms_v2_1`
**Previous Endpoint:** `POST /rpc/get_profile_platforms_v2`
**Deprecated Endpoint:** `POST /rpc/get_profile_platforms`
**Group:** Profile
**SQL:** [`functions/profiles/get_profile_platforms.md`](../../../functions/profiles/get_profile_platforms.md)
**Tables read:** `creator_profiles` · `creator_platform_accounts` · `platforms` · `profile_custom_links` · `profile_link_preferences`

---

## Overview

Returns **all profile links** organized by type (platforms, additional links, custom links) in separate response fields. Each link includes a `type` field to identify which group it belongs to.

### Version Comparison

| Version | Endpoint | Ordering | Features |
|---------|----------|----------|----------|
| **v2.1** (Current) | `/rpc/get_profile_platforms_v2_1` | User preferences | All 3 groups, preference ordering |
| **v2** | `/rpc/get_profile_platforms_v2` | ID-based | All 3 groups, fixed order |
| **v1** (Deprecated) | `/rpc/get_profile_platforms` | ID-based | Platforms only |

### What's New in v2.1?

- **Respects user preferences:** Links ordered by `profile_link_preferences` table
- **All 3 groups:** Platforms (1-4) → Additional Links (5+) → Custom Links
- **Type identifier:** Each link has `type` field: "platform", "additional_link", "custom_link"
- **Separate fields:** Easier for UI to handle each group differently

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_profile_id` | uuid | ✅ | The profile ID to fetch links for |

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
  "status": true,
  "message": "Platform links fetched successfully",
  "data": {
    "platforms": [
      {
        "id": "cpa-uuid-1",
        "platform_id": 1,
        "type": "platform",
        "platform_name": "YouTube",
        "logo_url": "https://cdn.example.com/yt.png",
        "channel_url": "https://youtube.com/@creator",
        "is_default": true
      },
      {
        "id": "cpa-uuid-2",
        "platform_id": 2,
        "type": "platform",
        "platform_name": "Twitch",
        "logo_url": "https://cdn.example.com/twitch.png",
        "channel_url": "https://twitch.tv/creator",
        "is_default": false
      }
    ],
    "additional_links": [
      {
        "id": "cpa-uuid-5",
        "platform_id": 5,
        "type": "additional_link",
        "platform_name": "Patreon",
        "logo_url": "https://cdn.example.com/patreon.png",
        "channel_url": "https://patreon.com/creator",
        "is_default": false
      }
    ],
    "custom_links": [
      {
        "id": "pcl-uuid-1",
        "platform_id": null,
        "type": "custom_link",
        "platform_name": "My Website",
        "logo_url": null,
        "channel_url": "https://mywebsite.com",
        "is_default": false
      }
    ]
  }
}
```

### Error

```json
{
  "status": false,
  "message": "<reason>"
}
```

---

## Response Fields

### platforms array
- **platform_id:** 1-4 (YouTube, Twitch, Kick, Rumble)
- **type:** "platform"
- **order:** By user's drag-drop preference (v2.1) or ID ascending (v2)

### additional_links array
- **platform_id:** 5+ from platforms table
- **type:** "additional_link"
- **order:** By user's drag-drop preference (v2.1) or ID ascending (v2)

### custom_links array
- **platform_id:** null (custom links don't have platform_id)
- **type:** "custom_link"
- **order:** By user's drag-drop preference (v2.1) or creation date ascending (v2)

---

## Error Cases

| Message | Cause |
|---------|-------|
| `Profile ID is required` | `p_profile_id` is null |
| `Profile not found` | No profile with that ID |
| `Something went wrong` | Unhandled exception |

---

## Logic Flow

```
1. Validate p_profile_id (not null)
2. Check if profile exists
3. Fetch 3 link groups in parallel:
   ├── Platforms (IDs 1-4)
   ├── Additional links (IDs 5+)
   └── Custom links (UUIDs)
4. Order each group by:
   ├── v2.1: profile_link_preferences table (drag-drop order)
   └── v2: ID ascending or created_at
5. Return with type field for each link
```

---

## Related APIs

- [[reorder_social_links_v2]] — Save drag-drop reordering
- [[get_profile_by_id_v2_1]] — Get full profile with links
- [[get_profile_custom_links_v2]] — Get custom links only
