# SP: `delete_event`

**Endpoint:** `POST /rpc/delete_event`
**Group:** Events
**SQL:** [`functions/events/delete_event.md`](../../../functions/events/delete_event.md)
**Tables written:** `event_mst` (CASCADE → `event_platforms` · `event_recurring` · child `event_mst` rows)

---

## Overview

Hard deletes a single event. The caller must own the profile that created the event.

For recurring parent events, the cascade automatically removes all child occurrence rows (any row in `event_mst` where `parent_event_id` matches). Platform links and recurring rules are also removed via CASCADE.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to delete |
| `p_user_id` | uuid | ✅ | Must own the profile that created this event |

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
| Ownership check | Event must belong to a `creator_profiles` row owned by `p_user_id` |
| Recurring parent | Deleting the parent removes all child occurrence rows automatically (CASCADE on `parent_event_id`) |
| `event_platforms` | Removed via CASCADE on `event_id` |
| `event_recurring` | Removed via CASCADE on `event_id` |
| Hard delete | Row is permanently removed — no soft delete / status change |

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id and p_user_id are required` | Either param is null |
| `Event not found or access denied` | No event with that ID, or it belongs to a different user |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null check: p_event_id, p_user_id
2. DELETE FROM event_mst
   USING creator_profiles
   WHERE event_id   = p_event_id
     AND profile_id = creator_profiles.id
     AND user_id    = p_user_id
3. Check FOUND:
   - NOT FOUND → "Event not found or access denied"
4. CASCADE automatically removes:
   - child event_mst rows (parent_event_id FK)
   - event_platforms rows (event_id FK)
   - event_recurring rows (event_id FK)
5. Return success
```

---

## Related

- [`get_event_by_id`](get_event_by_id.md) — confirm event details before deleting
- [`update_event`](update_event.md) — edit instead of delete
- [`create_event`](create_event.md) — original creation
