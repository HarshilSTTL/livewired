# SP: `update_custom_link`

**Endpoint:** `POST /rpc/update_custom_link`
**Group:** Profiles
**SQL:** [`functions/profiles/update_custom_link.md`](../../../functions/profiles/update_custom_link.md)
**Tables written:** `profile_custom_links` (UPDATE)

---

## Overview

Updates the `profile_name` and `profile_url` for a specific custom link row. Used when the user edits a custom link in the Custom Links section and saves.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_id` | uuid | ✅ | `profile_custom_links.id` of the row to update |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_profile_name` | text | ✅ | New display name |
| `p_profile_url` | text | ✅ | New URL |

---

## Request Example

```json
{
  "p_id":           "row-uuid",
  "p_user_id":      "user-uuid",
  "p_profile_name": "Updated Portfolio",
  "p_profile_url":  "https://newportfolio.com"
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Custom link updated successfully" }
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Custom link ID is required` | `p_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Link name is required` | `p_profile_name` is null or empty |
| `Link URL is required` | `p_profile_url` is null or empty |
| `Custom link not found or access denied` | Row doesn't exist, is soft-deleted, or belongs to a different user |
| `Something went wrong` | Unhandled exception |

---

## Notes

- Updates both `profile_name` and `profile_url` together — both must always be provided
- Also sets `updated_at = now()` on the row
- Ownership verified by joining through `creator_profiles.user_id`
- Soft-deleted rows cannot be updated

---

## Related

- [`get_profile_custom_links`](../../platforms/get_profile_custom_links.md) — fetch all custom links (use `id` from here)
- [`add_custom_link`](add_custom_link.md) — add a new custom link
- [`delete_custom_link`](delete_custom_link.md) — soft-delete a custom link
