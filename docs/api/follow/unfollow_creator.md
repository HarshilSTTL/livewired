# SP: `unfollow_creator`

**Endpoint:** `POST /rpc/unfollow_creator`
**Group:** Follow
**Description:** Unfollow a creator profile. Soft delete — sets `is_active = false` and `unfollowed_at = now()`. Row is kept for analytics. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| p_user_id | uuid | Yes | The follower |
| p_profile_id | uuid | Yes | The profile to unfollow |

---

## Request Example

```json
{
  "p_user_id": "uuid...",
  "p_profile_id": "uuid..."
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Creator unfollowed successfully" }
```

### Fail — user_id missing
```json
{ "status": false, "message": "user_id is required" }
```

### Fail — profile_id missing
```json
{ "status": false, "message": "profile_id is required" }
```

### Fail — User not found
```json
{ "status": false, "message": "User not found" }
```

### Fail — Not following
```json
{ "status": false, "message": "You are not following this creator" }
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
| p_profile_id is null | `"profile_id is required"` |
| user not in users table | `"User not found"` |
| No active follow row found | `"You are not following this creator"` |
| DB/runtime exception | `"Something went wrong"` + sqlerrm |

---

## Logic Flow

1. Validate p_user_id not null
2. Validate p_profile_id not null
3. Check user exists in `users`
4. Check active follow: `follows WHERE user_id=? AND profile_id=? AND is_active=true`
5. UPDATE `follows` SET `is_active=false`, `unfollowed_at=now()`
6. Return success

---

## Notes

- **Soft delete** — row stays in `follows` with `is_active = false`
- `unfollowed_at` is set to `now()` for analytics/history
- Re-following is handled by `follow_creator` SP (updates same row)
- Does not check profile status — can unfollow even suspended/deleted profiles

---

## SQL Reference

See [`functions/follow/unfollow_creator.sql`](../../../functions/follow/unfollow_creator.sql)
