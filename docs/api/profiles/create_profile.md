# SP: `create_profile`

**Endpoint:** `POST /rpc/create_profile`
**Group:** Profile
**Description:** Creates a new creator profile. Any registered user can create a profile — no pre-approval or role required. The user is automatically promoted to `role_id = 2` (creator) upon success. Optionally links platforms and tags in the same call. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| p_user_id | uuid | Yes | — | Must be a registered user — any user can create a profile |
| p_profile_name | text | Yes | — | Display name |
| p_avatar | text | No | null | Profile picture Base64 (nullable) |
| p_bio | text | No | null | Short bio (nullable) |
| p_is_default | boolean | No | false | Set as primary profile |
| p_status | text | No | 'active' | `active` / `suspended` / `deleted` |
| p_show_followers | boolean | No | true | Show follower count publicly |
| p_twitch_by_default | boolean | No | false | Show Twitch stream by default on profile |
| p_kick_by_default | boolean | No | false | Show Kick stream by default on profile |
| p_platforms | jsonb | No | null | Array of platform objects (see below) |
| p_tag_ids | bigint[] | No | null | Array of tag IDs (max 10) |

### `p_platforms` Format
```json
[
  {
    "platform_id": 1,
    "channel_url": "https://youtube.com/@harshil",
    "is_default": true
  },
  {
    "platform_id": 2,
    "channel_url": "https://twitch.tv/harshil",
    "is_default": false
  }
]
```
> `channel_url` is required for each platform object when p_platforms is provided (validated by SP).

---

## Request Example

```json
{
  "p_user_id": "uuid...",
  "p_profile_name": "Harshil Gaming",
  "p_bio": "I stream games daily",
  "p_show_followers": true,
  "p_twitch_by_default": false,
  "p_kick_by_default": false,
  "p_platforms": [
    { "platform_id": 1, "channel_url": "https://youtube.com/@harshil", "is_default": true }
  ],
  "p_tag_ids": [1, 2, 4]
}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Profile created successfully",
  "data": {
    "profile_id": "uuid...",
    "show_followers": true,
    "twitch_by_default": false,
    "kick_by_default": false
  }
}
```

### Fail — Profile name required
```json
{ "status": false, "message": "Profile name is required" }
```

### Fail — Invalid status
```json
{ "status": false, "message": "Invalid status" }
```

### Fail — Invalid platform ID
```json
{ "status": false, "message": "One or more platform IDs are invalid" }
```

### Fail — Channel URL missing
```json
{ "status": false, "message": "Channel URL is required for each platform" }
```

### Fail — Too many tags
```json
{ "status": false, "message": "Maximum 10 tags allowed" }
```

### Fail — Invalid tag ID
```json
{ "status": false, "message": "One or more tag IDs are invalid" }
```

### Fail — Server error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| p_profile_name null or empty | `"Profile name is required"` |
| p_status not in allowed values | `"Invalid status"` |
| any platform_id not in platforms table | `"One or more platform IDs are invalid"` |
| channel_url missing for a platform | `"Channel URL is required for each platform"` |
| more than 10 tag IDs | `"Maximum 10 tags allowed"` |
| any tag_id not in tags table | `"One or more tag IDs are invalid"` |
| DB/runtime exception | `"Something went wrong"` + sqlerrm |

---

## Logic Flow

1. Validate p_profile_name not empty
2. Validate p_status in (`active`, `suspended`, `deleted`)
3. Check profile_name uniqueness in `creator_profiles`
4. If p_platforms provided: validate all platform_id exist + channel_url not empty
5. If p_tag_ids provided: validate count ≤ 10 + all tag_ids exist
6. If user has no profiles yet → force `p_is_default = true`
7. If `p_is_default = true` → UPDATE all user's other profiles to `is_default = false`
8. INSERT into `creator_profiles` → get `v_profile_id`
9. If p_platforms provided → INSERT each into `creator_platform_accounts`
10. If p_tag_ids provided → bulk INSERT into `profile_tags` via `unnest()`
11. Return `profile_id` + `show_followers` + `twitch_by_default` + `kick_by_default`

---

## Tables Written

| Table | Action |
|-------|--------|
| `creator_profiles` | INSERT 1 row |
| `creator_platform_accounts` | INSERT N rows (one per platform) |
| `profile_tags` | INSERT N rows (one per tag) |

---

## SQL Reference

See [`functions/profiles/create_profile.md`](../../../functions/profiles/create_profile.md)
