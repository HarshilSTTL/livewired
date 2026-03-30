# SP: `submit_tags`

**Endpoint:** `POST /rpc/submit_tags`
**Group:** Tags
**Description:** Saves a user's selected interest tags from onboarding. **Replaces all previous selections** — full delete + re-insert. Uses `SECURITY DEFINER`.

> ⚠️ **Response format differs from all other SPs.** This SP uses `resultFlag` instead of `status` as the boolean key.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| p_user_id | uuid | Yes | The user saving interests |
| p_tag_ids | bigint[] | Yes | Array of tag IDs |

---

## Request Example

```json
{
  "p_user_id": "uuid...",
  "p_tag_ids": [1, 2, 4, 7]
}
```

---

## Response

> ⚠️ Key is `resultFlag` (not `status`) — handle accordingly in Flutter/client code.

### Success
```json
{ "resultFlag": true, "message": "Data Updated successfully" }
```

### Fail — user_id missing
```json
{ "resultFlag": false, "message": "USER_id is required" }
```

### Fail — Empty tag array
```json
{ "resultFlag": false, "message": "TAGid array is required and must not be empty" }
```

### Fail — User not found
```json
{ "resultFlag": false, "message": "User not found" }
```

### Fail — Invalid tag ID
```json
{ "resultFlag": false, "message": "One or more tag IDs are invalid" }
```

### Fail — Server error
```json
{ "resultFlag": false, "message": "<sqlerrm>" }
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| p_user_id is null | `"USER_id is required"` |
| p_tag_ids null or empty | `"TAGid array is required and must not be empty"` |
| user not in users table | `"User not found"` |
| any tag_id not in tags table | `"One or more tag IDs are invalid"` |
| DB/runtime exception | sqlerrm message directly |

---

## Logic Flow

1. Validate p_user_id not null
2. Validate p_tag_ids not null and not empty
3. Check user exists in `users`
4. Check all tag_ids exist in `tags` via `UNNEST()` + NOT IN
5. DELETE all rows from `user_interests` WHERE user_id = p_user_id
6. INSERT new rows: `SELECT p_user_id, UNNEST(p_tag_ids)`
7. Return `resultFlag: true` on success

---

## Differences vs `submit_platform`

| Feature | `submit_platform` | `submit_tags` |
|---------|------------------|---------------|
| Response key | `status` | `resultFlag` ⚠️ |
| Array param type | `int[]` | `bigint[]` |
| Error codes | Machine-readable codes | Plain messages only |
| Validation order | user → array → validity | user_id → array → user exists → validity |

---

## SQL Reference

See [`functions/tags/submit_tags.sql`](../../../functions/tags/submit_tags.sql)
