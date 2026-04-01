# SP: `get_following_list`

**Endpoint:** `POST /rpc/get_following_list`
**Group:** Follow
**Description:** Returns all creator profiles a user actively follows, with live follower count and platforms. Only active profiles included. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| p_user_id | uuid | Yes | The user whose following list to fetch |

---

## Request Example

```json
{
  "p_user_id": "uuid..."
}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Following list fetched successfully",
  "data": [
    {
      "profile_id": "uuid",
      "profile_name": "Harshil Gaming",
      "username": "harshil_gaming",
      "avatar": null,
      "bio": "I stream games daily",
      "status": "active",
      "followers": 150,
      "platforms": [
        { "platform_id": 1, "platform_name": "YouTube", "logo_url": "url or null" }
      ],
      "followed_at": "2026-03-24T06:24:53+00:00"
    }
  ]
}
```

### Success — No following
```json
{ "status": true, "message": "No following found", "data": [] }
```

### Fail — user_id missing
```json
{ "status": false, "message": "user_id is required" }
```

### Fail — User not found
```json
{ "status": false, "message": "User not found" }
```

### Fail — Server error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| p_user_id is null | `"user_id is required"` |
| user not in users table | `"User not found"` |
| User follows no one / all unfollowed | `status: true, "No following found", data: []` |
| DB/runtime exception | `"Something went wrong"` + sqlerrm |

---

## Logic Flow

1. Validate p_user_id not null
2. Check user exists in `users`
3. SELECT from `follows` JOIN `creator_profiles`
   - WHERE `f.user_id = p_user_id AND f.is_active = true AND cp.status = 'active'`
   - ORDER BY `f.created_at DESC`
4. Per profile: subquery for live `followers` count + `platforms` array
5. If NULL → return `status: true, data: []`
6. Return results

---

## Response Field Notes

| Field | Notes |
|-------|-------|
| `avatar` | nullable — handle in UI |
| `bio` | nullable — handle in UI |
| `followers` | live COUNT from follows WHERE is_active=true |
| `platforms` | from `creator_platform_accounts` JOIN `platforms` — always array |
| `followed_at` | = `follows.created_at` (nullable) |

---

## SQL Reference

See [`functions/follow/get_following_list.md`](../../../functions/follow/get_following_list.md)
