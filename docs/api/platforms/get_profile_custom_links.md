# SP: `get_profile_custom_links`

**Endpoint:** `POST /rpc/get_profile_custom_links`
**Group:** Platforms
**SQL:** [`functions/platforms/get_profile_custom_links.md`](../../../functions/platforms/get_profile_custom_links.md)
**Tables read:** `profile_custom_links` · `creator_profiles`

---

## Overview

Returns all active (non-deleted) custom platform links for a given creator profile.

Used in two places:
1. **Profile edit screen** — to populate the existing Custom Links section when the user opens it
2. **Additional Links dropdown** — frontend can merge this result with `get_all_platforms` to show global + custom platforms together

`get_all_platforms` is **not changed** — this is a separate, dedicated endpoint.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile whose custom links to fetch |

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
  "message": "Custom links fetched successfully",
  "data": [
    {
      "custom_id":    "uuid",
      "profile_name": "Amazon",
      "profile_url":  "https://amazon.com/storefront/creator",
      "is_custom":    true,
      "created_at":   "2026-04-10T00:00:00",
      "updated_at":   "2026-04-10T00:00:00"
    },
    {
      "custom_id":    "uuid",
      "profile_name": "Cashapp",
      "profile_url":  "https://cash.app/$creator",
      "is_custom":    true,
      "created_at":   "2026-04-10T00:00:00",
      "updated_at":   "2026-04-10T00:00:00"
    }
  ]
}
```

### Success — No custom links yet
```json
{
  "status":  true,
  "message": "Custom links fetched successfully",
  "data":    []
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

## Response Field Notes

| Field | Notes |
|---|---|
| `data` | Always an array — `[]` if no custom links exist |
| `custom_id` | UUID of the row in `profile_custom_links` — use this for update/delete calls |
| `profile_name` | User-defined platform name e.g. `"Amazon"`, `"Cashapp"` |
| `profile_url` | Full URL entered by the creator |
| `is_custom` | Always `true` — helps frontend distinguish from global platforms when merging |

---

## Error Cases

| Message | Cause |
|---|---|
| `Profile ID is required` | `p_profile_id` is null |
| `Profile not found` | No profile with that ID in `creator_profiles` |
| `Something went wrong` | Unhandled exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Null check: p_profile_id
2. Profile existence check in creator_profiles
3. SELECT from profile_custom_links
   WHERE profile_id = p_profile_id AND is_deleted = false
   ORDER BY created_at ASC
4. Return data array ([] if none found)
```

---

## Notes

- Only returns **active** links — soft-deleted rows (`is_deleted = true`) are excluded
- Results ordered by `created_at ASC` — oldest first, preserving the order the user added them
- `get_all_platforms` is unchanged — call both separately and merge on the frontend if needed

---

## Related

- [`get_all_platforms`](get_all_platforms.md) — global platforms list (unchanged)
- `manage_custom_links` SP *(planned)* — add / edit / soft-delete custom links
- [`profile_custom_links` table](../../database/tables/14_profile_custom_links.md)
