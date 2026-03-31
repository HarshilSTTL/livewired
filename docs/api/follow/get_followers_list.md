# SP: `get_followers_list`

**Endpoint:** `POST /rpc/get_followers_list`
**Group:** Follow
**Description:** Returns all users who actively follow a specific creator profile, plus a total follower count. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| p_profile_id | uuid | Yes | The creator profile to get followers for |

---

## Request Example

```json
{
  "p_profile_id": "uuid..."
}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Followers list fetched successfully",
  "total_followers": 3,
  "data": [
    { "user_id": "uuid", "email": "alice@gmail.com", "followed_at": "2026-03-24T06:24:53+00:00" },
    { "user_id": "uuid", "email": "bob@gmail.com",   "followed_at": "2026-03-20T10:00:00+00:00" }
  ]
}
```

### Success — No followers
```json
{ "status": true, "message": "No followers found", "total_followers": 0, "data": [] }
```

### Fail — profile_id missing
```json
{ "status": false, "message": "profile_id is required" }
```

### Fail — Profile not found
```json
{ "status": false, "message": "Profile not found" }
```

### Fail — Server error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| p_profile_id is null | `"profile_id is required"` |
| profile not in creator_profiles | `"Profile not found"` |
| No active followers | `status: true, total_followers: 0, data: []` |
| DB/runtime exception | `"Something went wrong"` + sqlerrm |

---

## Logic Flow

1. Validate p_profile_id not null
2. Check profile exists in `creator_profiles`
3. SELECT from `follows` JOIN `users` WHERE `f.profile_id=? AND f.is_active=true`
4. ORDER BY `f.created_at DESC`
5. If NULL → return `total_followers: 0, data: []`
6. On success → separate COUNT query for `total_followers` + return data

---

## Difference vs `get_following_list`

| Feature | `get_following_list` | `get_followers_list` |
|---------|---------------------|---------------------|
| Input | user_id | profile_id |
| Returns | Profiles the user follows | Users who follow a profile |
| Includes platforms | Yes | No |
| Count in response | No | Yes (`total_followers`) |
| Filters profile status | Yes (active only) | No |

---

## SQL Reference

See [`functions/follow/get_followers_list.md`](../../../functions/follow/get_followers_list.md)
