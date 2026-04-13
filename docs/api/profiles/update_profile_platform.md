# SP: `update_profile_platform`

**Endpoint:** `POST /rpc/update_profile_platform`
**Group:** Profiles
**SQL:** [`functions/profiles/update_profile_platform.md`](../../../functions/profiles/update_profile_platform.md)
**Tables written:** `creator_platform_accounts` (UPDATE)

---

## Overview

Updates the `channel_url` for a specific platform link row. Used when the user edits a URL in the Toggle or Additional Links section and saves.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_id` | uuid | ✅ | `creator_platform_accounts.id` of the row to update |
| `p_user_id` | uuid | ✅ | Caller's user ID (ownership check) |
| `p_channel_url` | text | ✅ | New channel/stream URL |

---

## Request Example

```json
{
  "p_id":          "row-uuid",
  "p_user_id":     "user-uuid",
  "p_channel_url": "https://youtube.com/@newhandle"
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Platform link updated successfully" }
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Platform link ID is required` | `p_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Channel URL is required` | `p_channel_url` is null or empty |
| `Platform link not found or access denied` | Row doesn't exist, is soft-deleted, or belongs to a different user |
| `Something went wrong` | Unhandled exception |

---

## Notes

- Only updates `channel_url` — `platform_id` and `is_default` are not changed here
- Ownership verified by joining through `creator_profiles.user_id`
- Soft-deleted rows cannot be updated

---

## Related

- [`get_profile_platforms`](get_profile_platforms.md) — fetch all platform links (use `id` from here)
- [`add_profile_platform`](add_profile_platform.md) — add a new platform link
- [`delete_profile_platform`](delete_profile_platform.md) — soft-delete a platform link
