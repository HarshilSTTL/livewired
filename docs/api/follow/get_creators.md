# SP: `get_creators`

**Endpoint:** `GET /rpc/get_creators`
**Group:** Follow
**Description:** Returns all active creator profiles with follower count and platform names. Used for the follow recommendations screen during onboarding. Uses `SECURITY DEFINER`.

> ⚠️ **Two differences from other follow SPs:**
> 1. `followers` count has **no `is_active` filter** — counts all rows in `follows` including unfollowed users
> 2. `platforms` returns **platform name strings only** (not objects with platform_id/logo_url)

---

## Parameters

None — no input required.

---

## Request Example

```http
GET /rest/v1/rpc/get_creators
apikey: <your-api-key>
Authorization: Bearer <token>
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Data fetched successfully",
  "data": {
    "creators": [
      {
        "id": "uuid",
        "name": "Harshil Gaming",
        "username": "harshil_gaming",
        "profilepic": "url or null",
        "followers": 150,
        "platforms": ["YouTube", "Twitch"]
      }
    ]
  }
}
```

### Success — No active creators
```json
{
  "status": true,
  "message": "Data fetched successfully",
  "data": { "creators": [] }
}
```

### Fail — Server error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Response Field Notes

| Field | Key | Notes |
|-------|-----|-------|
| Profile ID | `id` | uuid |
| Display name | `name` | `creator_profiles.profile_name` |
| Handle | `username` | — |
| Avatar | `profilepic` | nullable — `creator_profiles.avatar` |
| Follower count | `followers` | ⚠️ No is_active filter — all follow rows counted |
| Platforms | `platforms` | ⚠️ Array of strings (plat_name only), not objects |

---

## ⚠️ Important Differences vs Other SPs

| Feature | `get_creators` | `get_following_list` / `search_profiles` |
|---------|---------------|------------------------------------------|
| `followers` filter | No `is_active` filter | `is_active = true` only |
| `platforms` format | `["YouTube", "Twitch"]` strings | `[{platform_id, platform_name, logo_url}]` objects |
| Response wrapper | `data.creators[]` | `data[]` direct |

---

## Logic Flow

1. SELECT from `creator_profiles` WHERE `status = 'active'`
2. Per profile: subquery COUNT from `follows` (no is_active filter)
3. Per profile: subquery `json_agg(p.plat_name)` — platform names only
4. Wrap in `data.creators` — `coalesce(..., '[]')` ensures never null
5. EXCEPTION block catches all errors

---

## SQL Reference

See [`functions/follow/get_creators.md`](../../../functions/follow/get_creators.md)
