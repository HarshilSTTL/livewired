# SP: `reorder_social_links_v2`

**Endpoint:** `POST /rpc/reorder_social_links_v2`
**Group:** Profiles
**SQL:** [[functions/profiles/reorder_social_links.md]]
**Version:** 2.0 (2026-05-28)

---

## Overview

Saves the drag-drop reordering of social links (platforms, additional links, custom links) for a profile. Called when user clicks SAVE button after reordering links.

Creates or updates a single record in `profile_link_preferences` with the new display order for all three link groups.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_profile_id` | uuid | ✅ | Profile ID |
| `p_platform_ids` | int[] | ❌ | Platform IDs in desired order (1-4: YouTube, Twitch, Kick, Rumble) |
| `p_additional_ids` | int[] | ❌ | Additional link IDs in desired order (5-42+) |
| `p_custom_ids` | uuid[] | ❌ | Custom link IDs in desired order |

---

## Request Example

```json
{
  "p_profile_id": "abc-123-def-456",
  "p_platform_ids": [3, 4, 2, 1],
  "p_additional_ids": [7, 5, 6, 8],
  "p_custom_ids": ["uuid-10", "uuid-8", "uuid-9"]
}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Links reordered successfully",
  "data": {
    "profile_id": "abc-123-def-456",
    "platform_ids_order": [3, 4, 2, 1],
    "additional_ids_order": [7, 5, 6, 8],
    "custom_ids_order": ["uuid-10", "uuid-8", "uuid-9"]
  }
}
```

### Error — Profile not found
```json
{
  "status": false,
  "message": "Profile not found"
}
```

### Error — Missing profile ID
```json
{
  "status": false,
  "message": "Profile ID is required"
}
```

### Error — Server error
```json
{
  "status": false,
  "message": "Something went wrong",
  "error": "<sqlerrm>"
}
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| `p_profile_id` is null | `"Profile ID is required"` |
| Profile doesn't exist | `"Profile not found"` |
| DB/runtime exception | `"Something went wrong"` + error detail |

---

## Logic Flow

1. Validate `p_profile_id` is not null
2. Check if profile exists
3. UPSERT into `profile_link_preferences`:
   - If profile has no preferences: INSERT new row
   - If profile has preferences: UPDATE existing row
4. Return saved order in response

---

## Notes

- **Idempotent:** Calling twice with same data = same result
- **Partial Updates:** Can save only platforms, skip additional/custom by passing empty arrays
- **No Validation:** Function doesn't validate if IDs actually exist or belong to profile
  - Frontend should validate before calling
- **Order Matters:** Arrays preserve order — first element = displayed first
- **Cascading Delete:** If profile is deleted, preferences are auto-deleted

---

## Related

- [[get_profile_by_id_v2_1]] — Fetch profile with ordered links
- [[get_profile_by_userid_v2_1]] — Fetch user's profiles with ordered links
- [[search_profiles_v2_1]] — Search profiles with ordered links
