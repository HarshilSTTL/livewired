# SP: `add_custom_link`

**Endpoint:** `POST /rpc/add_custom_link`
**Group:** Profiles
**SQL:** [`functions/profiles/add_custom_link.md`](../../../functions/profiles/add_custom_link.md)
**Tables written:** `profile_custom_links` (INSERT)

---

## Overview

Inserts one new custom link for a creator profile. Used when the user adds a free-text name + URL entry in the Custom Links section and hits the "+" button.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | Profile to add the custom link to |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_profile_name` | text | ✅ | Display name for the link (free text) |
| `p_profile_url` | text | ✅ | Full URL |

---

## Request Example

```json
{
  "p_profile_id":   "profile-uuid",
  "p_user_id":      "user-uuid",
  "p_profile_name": "My Portfolio",
  "p_profile_url":  "https://myportfolio.com"
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Custom link added successfully",
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
| `Link name is required` | `p_profile_name` is null or empty |
| `Link URL is required` | `p_profile_url` is null or empty |
| `Profile not found or access denied` | Profile doesn't exist or belongs to a different user |
| `Something went wrong` | Unhandled exception |

---

## Notes

- `id` in the response is the `profile_custom_links.id` — use this for `update_custom_link` and `delete_custom_link` calls
- Both name and URL are trimmed before insert

---

## Related

- [`get_profile_custom_links`](../../platforms/get_profile_custom_links.md) — fetch all custom links for a profile
- [`update_custom_link`](update_custom_link.md) — update a custom link
- [`delete_custom_link`](delete_custom_link.md) — soft-delete a custom link
