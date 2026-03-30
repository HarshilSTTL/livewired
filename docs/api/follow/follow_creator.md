# SP: `follow_creator`

**Endpoint:** `POST /rpc/follow_creator`
**Group:** Follow
**Description:** Follow a creator profile. Handles re-follow by updating the existing row instead of inserting a new one. Uses `SECURITY DEFINER`.

> ⚠️ **Note:** `p_device_ip` is referenced inside the function body but is **not declared as a parameter** in the function signature. The device IP update block will not execute as written.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| p_user_id | uuid | Yes | The follower |
| p_profile_id | uuid | Yes | The profile to follow |

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
{ "status": true, "message": "Creator followed successfully" }
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

### Fail — Profile not found or inactive
```json
{ "status": false, "message": "Creator profile not found or inactive" }
```

### Fail — Own profile
```json
{ "status": false, "message": "You cannot follow your own profile" }
```

### Fail — Already following
```json
{ "status": false, "message": "You are already following this creator" }
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
| profile not found or status ≠ 'active' | `"Creator profile not found or inactive"` |
| profile.user_id = p_user_id (own profile) | `"You cannot follow your own profile"` |
| Row exists and is_active = true | `"You are already following this creator"` |
| DB/runtime exception | `"Something went wrong"` + sqlerrm |

---

## Logic Flow

1. Validate p_user_id not null
2. Validate p_profile_id not null
3. Check user exists in `users`
4. Check profile exists in `creator_profiles` with `status = 'active'`
5. Check profile does not belong to p_user_id (prevent self-follow)
6. Check if `follows` row exists for `(user_id, profile_id)`:
   - **Row exists + `is_active = false`** → re-follow: UPDATE `is_active=true`, `unfollowed_at=null`, `created_at=now()`
   - **Row exists + `is_active = true`** → already following error
7. **No row** → INSERT new follow row
8. Return success

---

## Follow State Machine

```
[No row] ──── follow_creator ────▶ [is_active=true]
                                          │
                                   unfollow_creator
                                          │
                                          ▼
                                   [is_active=false]
                                          │
                                   follow_creator (re-follow)
                                          │
                                          ▼
                                   [is_active=true]  ← same row updated
```

---

## SQL Reference

See [`functions/follow/follow_creator.sql`](../../../functions/follow/follow_creator.sql)
