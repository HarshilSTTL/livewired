# SP: `delete_event`

**Endpoint:** `POST /rpc/delete_event`
**Group:** Events
**SQL:** [`functions/events/delete_event.md`](../../../functions/events/delete_event.md)
**Tables written:** `event_mst`

---

## Overview

Soft deletes a single event. Sets `is_deleted = true` and `deleted_at = now()` on the event row. Only the event **owner** can delete — collaborators do not have delete permission.

For recurring parent events, all child occurrence rows are also soft deleted in the same operation.

The rows are **not removed** from the database — they are hidden from all public queries automatically.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to delete |
| `p_user_id` | uuid | ✅ | Must be the event owner |

---

## Request Example

```json
{
  "p_event_id": "uuid...",
  "p_user_id":  "uuid..."
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Event deleted successfully" }
```

### Not Found / Access Denied
```json
{ "status": false, "message": "Event not found or access denied" }
```

### Error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Response Field Notes

| Field | Notes |
|-------|-------|
| Soft delete | Sets `event_mst.is_deleted = true` + `deleted_at = now()` |
| Recurring parent | All child occurrence rows (`parent_event_id = p_event_id`) are also soft deleted |
| Already deleted | Returns "Event not found or access denied" if `is_deleted` is already `true` |
| Public reads | `get_event_list`, `get_event_by_id`, `get_profile_events`, `search_events` all filter `is_deleted = false` |

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id and p_user_id are required` | Either param is null |
| `Event not found or access denied` | No event with that ID, already deleted, or caller is not the owner |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null check: p_event_id, p_user_id
2. Ownership + existence check:
   JOIN event_mst + creator_profiles
   WHERE event_id = p_event_id AND user_id = p_user_id AND is_deleted = false
3. Soft delete the event (parent or standalone):
   UPDATE event_mst SET is_deleted = true, deleted_at = now()
   WHERE event_id = p_event_id
4. Soft delete all child occurrences:
   UPDATE event_mst SET is_deleted = true, deleted_at = now()
   WHERE parent_event_id = p_event_id AND is_deleted = false
5. Return success
```

---

## Related

- [`get_event_by_id`](get_event_by_id.md) — confirm event details before deleting
- [`update_event`](update_event.md) — edit instead of delete
- [`delete_profile`](../profiles/delete_profile.md) — soft deletes a profile and all its events
