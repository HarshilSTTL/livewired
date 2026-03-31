# SP: `is_creator`

> ⚠️ **Renamed:** Originally documented as `creator_enable`. Actual DB function name is `is_creator`.

**Endpoint:** `POST /rpc/is_creator`
**Group:** Profile
**Description:** Enables or disables creator mode for a user. Sets `role_id = 2` (creator) or `role_id = 1` (user) on the `users` table. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| p_user_id | uuid | Yes | The user to update |
| p_is_creator | boolean | Yes | `true` = enable creator, `false` = disable |
| p_device_ip | text | Yes | Current device IP — stored in updated_device_ip |

---

## Request Example

```json
{
  "p_user_id": "abc123...",
  "p_is_creator": true,
  "p_device_ip": "192.168.1.1"
}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Data updated successfully"
}
```

### Fail — User not found
```json
{
  "status": false,
  "message": "User not found",
  "error": "No user found with the given id"
}
```

### Fail — Server error
```json
{
  "status": false,
  "message": "Something went wrong",
  "error": "<sqlerrm>"
}
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| p_user_id not found in users | `"User not found"` |
| DB/runtime exception | `"Something went wrong"` + sqlerrm |

---

## Logic Flow

1. Check user exists — return error if not found
2. UPDATE `users` SET:
   - `role_id = 2` if `p_is_creator = true`, else `role_id = 1`
   - `updated_device_ip = p_device_ip`
   - `updated_at = now()`
3. Return success
4. EXCEPTION block catches all other errors

---

## Effect on Other SPs

After `is_creator` sets `role_id = 2`:
- User can call `create_profile` (which checks `role_id = 2`)
- User can create and manage creator profiles and events

After `is_creator` sets `role_id = 1`:
- User loses creator permissions
- Existing profiles remain but new ones cannot be created

---

## SQL Reference

See [`functions/profiles/creator_enable.md`](../../../functions/profiles/creator_enable.md)
