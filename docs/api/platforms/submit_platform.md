# SP: `submit_platform`

**Endpoint:** `POST /rpc/submit_platform`
**Group:** Platform
**Description:** Saves a user's preferred platforms selected during onboarding. **Replaces all previous selections** — full delete + re-insert. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| p_user_id | uuid | Yes | The user saving preferences |
| p_platformid | int[] | Yes | Array of platform IDs (integer array) |

---

## Request Example

```json
{
  "p_user_id": "uuid...",
  "p_platformid": [1, 2, 3]
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Platforms saved successfully" }
```

### Fail — User not found
```json
{ "status": false, "message": "Invalid user_id", "error": "USER_NOT_FOUND" }
```

### Fail — Empty platform list
```json
{ "status": false, "message": "platformid is required", "error": "EMPTY_PLATFORM_LIST" }
```

### Fail — Invalid platform ID
```json
{ "status": false, "message": "One or more platform IDs are invalid", "error": "INVALID_PLATFORM_ID" }
```

### Fail — Server error
```json
{ "status": false, "message": "There was a problem in submit_platform", "error": "<sqlerrm>" }
```

---

## Error Cases

| Scenario | Error Code | Message |
|----------|------------|---------|
| user not in users table | `USER_NOT_FOUND` | `"Invalid user_id"` |
| p_platformid null or empty array | `EMPTY_PLATFORM_LIST` | `"platformid is required"` |
| any platform ID not in platforms table | `INVALID_PLATFORM_ID` | `"One or more platform IDs are invalid"` |
| DB/runtime exception | sqlerrm | `"There was a problem in submit_platform"` |

---

## Logic Flow

1. COUNT users WHERE id = p_user_id — error if 0 (USER_NOT_FOUND)
2. Check p_platformid not null and not empty (EMPTY_PLATFORM_LIST)
3. COUNT invalid platform IDs via `unnest()` — error if any invalid (INVALID_PLATFORM_ID)
4. DELETE all rows from `user_preferred_platforms` WHERE user_id = p_user_id
5. INSERT new rows: `SELECT p_user_id, unnest(p_platformid)`
6. Return success

---

## Notes

- **Replace-all pattern** — previous selections are always wiped and replaced
- `p_platformid` is `int[]` (integer array), not `bigint[]`
- `platform_id` in `user_preferred_platforms` is `int8` — the unnest cast is handled automatically by PostgreSQL
- Error responses include machine-readable `error` code alongside human `message`
- Used during onboarding flow after `get_all_platforms`

---

## SQL Reference

See [`functions/platforms/submit_platform.sql`](../../../functions/platforms/submit_platform.sql)
