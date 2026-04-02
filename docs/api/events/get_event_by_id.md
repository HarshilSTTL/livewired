# SP: `get_event_by_id`

**Endpoint:** `POST /rpc/get_event_by_id`
**Group:** Events
**SQL:** [`functions/events/get_event_by_id.md`](../../../functions/events/get_event_by_id.md)
**Tables read:** `event_mst` · `creator_profiles` · `event_platforms` · `platforms` · `event_recurring`

---

## Overview

Returns full detail for a single event by its ID. Used when the user taps an event card on the dashboard or profile page to open the event detail screen.

For recurring child events, platforms and recurring rules are inherited from the parent via `COALESCE(parent_event_id, event_id)`.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to fetch |

---

## Request Example

```json
{
  "p_event_id": "uuid..."
}
```

---

## Response

### Success
```json
{
  "status": true,
  "data": {
    "event_id":        "uuid...",
    "profile_id":      "uuid...",
    "parent_event_id": null,
    "title":           "Metroid Monday!",
    "description":     "Weekly gaming stream",
    "event_date":      "2026-04-06",
    "event_time":      "03:00:00",
    "livestream":      true,
    "video":           false,
    "is_recurring":    true,
    "created_at":      "2026-03-30T18:45:00Z",
    "creator": {
      "profile_id":   "uuid...",
      "profile_name": "Creator One",
      "username":     "creator_one",
      "avatar":       "https://..."
    },
    "platforms": [
      {
        "platform_id":   1,
        "platform_name": "YouTube",
        "logo_url":      "https://...",
        "stream_url":    "https://youtube.com/live/abc"
      }
    ],
    "recurring": {
      "recurring_type":       "weekly",
      "recurring_days":       ["Mon"],
      "recurring_interval":   1,
      "recurring_start_date": "2026-03-23",
      "recurring_end_date":   "2026-12-31"
    }
  }
}
```

### Not Found
```json
{ "status": false, "message": "Event not found" }
```

### Error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Response Field Notes

| Field | Notes |
|-------|-------|
| `parent_event_id` | `null` for non-recurring or parent template. UUID for recurring child occurrences |
| `recurring` | `null` if the event is not recurring |
| `platforms` | Inherited from parent for recurring child events. Always `[]` if none |
| `creator.avatar` | Supabase Storage URL (or null if not set) |
| `livestream` | `true` → show Live indicator on detail screen |
| `is_recurring` | `true` → show ↻ icon on detail screen |

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id is required` | `p_event_id` is null |
| `Event not found` | No event with that UUID |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null check: p_event_id
2. JOIN event_mst + creator_profiles on profile_id
3. Subquery platforms:
   WHERE ep.event_id = COALESCE(e.parent_event_id, e.event_id)
   → recurring children inherit platforms from parent row
4. Subquery recurring rules from event_recurring (NULL for non-recurring)
5. Return full event object or "Event not found"
```

---

## Related

- [`get_event_list`](get_event_list.md) — dashboard feed (tap card → this SP)
- [`get_profile_events`](get_profile_events.md) — profile weekly view (tap card → this SP)
- [`update_event`](update_event.md) — edit this event
- [`delete_event`](delete_event.md) — delete this event
