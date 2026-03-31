# SP: `update_profile`

**Endpoint:** `POST /rpc/update_profile`
**Group:** Profile
**SQL:** [`functions/profiles/update_profile.md`](../../../functions/profiles/update_profile.md)
**Tables written:** `creator_profiles` · `creator_platform_accounts` · `profile_tags`

---

## Overview

Partially updates an existing creator profile. Uses the **COALESCE pattern** — only fields
that are explicitly passed (non-null) get updated in `creator_profiles`. Platform accounts
and tags use a **replace-all pattern** — when passed (even as empty array), the existing
rows are deleted and replaced. When passed as `null`, those tables are untouched.

---

## Parameters

| Parameter          | Type     | Required | Default | Description                                 |
| ------------------ | -------- | -------- | ------- | ------------------------------------------- |
| `p_profile_id`     | uuid     | ✅        | —       | Profile to update                           |
| `p_user_id`        | uuid     | ✅        | —       | Must be the profile owner (ownership check) |
| `p_profile_name`   | text     | ❌        | null    | New display name (omit to keep current)     |
| `p_username`       | text     | ❌        | null    | New username — must be globally unique      |
| `p_avatar_url`     | text     | ❌        | null    | New avatar URL                              |
| `p_bio`            | text     | ❌        | null    | New bio                                     |
| `p_is_default`     | boolean  | ❌        | null    | Set as default profile (unsets all others)  |
| `p_status`         | text     | ❌        | null    | `'active'` · `'suspended'` · `'deleted'`    |
| `p_show_followers` | boolean  | ❌        | null    | Toggle follower count visibility            |
| `p_platforms`      | jsonb    | ❌        | null    | Replace all platforms (see format below)    |
| `p_tag_ids`        | bigint[] | ❌        | null    | Replace all tags (max 10)                   |

### p_platforms format

```json
[
  { "platform_id": 1, "channel_url": "https://youtube.com/@handle", "is_default": true },
  { "platform_id": 2, "channel_url": "https://twitch.tv/handle",    "is_default": false }
]
```

> `username` in `creator_platform_accounts` is automatically taken from the resolved
> profile username (after any username update applied in the same call).

---

## Null vs Empty — Platform & Tag Behaviour

| Value passed | Behaviour |
|---|---|
| `null` (omitted) | Table **not touched** — existing rows preserved |
| `[]` empty array | **Clears all** rows for this profile (DELETE, no INSERT) |
| `[...]` non-empty | **Replace all**: DELETE existing + INSERT new |

---

## Request Example

### Partial update (bio + show_followers only)
```json
{
  "p_profile_id": "abc123",
  "p_user_id":    "user456",
  "p_bio":        "Updated bio text",
  "p_show_followers": false
}
```

### Full update (all three tables)
```json
{
  "p_profile_id":     "abc123",
  "p_user_id":        "user456",
  "p_profile_name":   "New Display Name",
  "p_username":       "new_handle",
  "p_avatar_url":     "https://cdn.example.com/avatar.jpg",
  "p_bio":            "Creator bio here",
  "p_is_default":     true,
  "p_show_followers": true,
  "p_platforms": [
    { "platform_id": 1, "channel_url": "https://youtube.com/@new_handle", "is_default": true }
  ],
  "p_tag_ids": [1, 3, 5]
}
```

### Clear all platforms (keep tags unchanged)
```json
{
  "p_profile_id": "abc123",
  "p_user_id":    "user456",
  "p_platforms":  []
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Profile updated successfully",
  "data": {
    "profile_id": "abc123"
  }
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

## Error Cases

| Message | Cause |
|---|---|
| `Profile ID is required` | `p_profile_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Profile not found or access denied` | Profile doesn't exist OR doesn't belong to `p_user_id` |
| `Username cannot be empty` | `p_username` passed as empty string |
| `Username already taken` | `p_username` exists on a different profile |
| `Invalid status` | `p_status` not in `active / suspended / deleted` |
| `One or more platform IDs are invalid` | Platform ID not in `platforms` table |
| `Channel URL is required for each platform` | A platform object missing `channel_url` |
| `Maximum 10 tags allowed` | `p_tag_ids` array length > 10 |
| `One or more tag IDs are invalid` | Tag ID not in `tags` table |
| `Something went wrong` | Unhandled exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Null check: p_profile_id, p_user_id
2. Ownership check: creator_profiles WHERE id = p_profile_id AND user_id = p_user_id
3. Username uniqueness check (if p_username provided, exclude current profile)
4. Status validation (if p_status provided)
5. Platform validation (if p_platforms non-null and non-empty)
   ├── All platform_ids must exist in platforms table
   └── All platform objects must have a non-empty channel_url
6. Tag validation (if p_tag_ids non-null and non-empty)
   ├── Max 10 tags
   └── All tag_ids must exist in tags table
7. If p_is_default = true → UPDATE other profiles: is_default = false
8. UPDATE creator_profiles using COALESCE for each field + updated_at = now()
9. Fetch resolved username (post-update) into v_final_username
10. If p_platforms IS NOT NULL:
    ├── DELETE FROM creator_platform_accounts WHERE profile_id = p_profile_id
    └── If array non-empty → INSERT each platform with v_final_username
11. If p_tag_ids IS NOT NULL:
    ├── DELETE FROM profile_tags WHERE profile_id = p_profile_id
    └── If array non-empty → INSERT unnest(p_tag_ids)
12. RETURN success with profile_id
```

---

## Key Differences vs `create_profile`

| Aspect | `create_profile` | `update_profile` |
|---|---|---|
| Profile ID | Generated (`gen_random_uuid()`) | Provided by caller |
| Ownership check | role_id = 2 check | `profile.user_id = p_user_id` check |
| is_default auto-set | Yes — first profile auto-becomes default | No auto-logic; only acts if explicitly passed |
| Username check | Must not exist at all | Must not exist on *any other* profile |
| Platforms/tags | null = skip insert | null = don't touch; `[]` = clear all |
| `creator_platform_accounts` username | `p_username` directly | `v_final_username` (resolved post-update) |

---

## Related

- [`create_profile`](create_profile.md) — creates the profile and all three tables atomically
- [`creator_profiles` table](../../database/tables/05_creator_profiles.md)
- [`creator_platform_accounts` table](../../database/tables/06_creator_platform_accounts.md)
- [`profile_tags` table](../../database/tables/07_profile_tags.md)
