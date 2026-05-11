# SP: `skip_recurring_occurrence`

**Endpoint:** `POST /rpc/skip_recurring_occurrence`
**Group:** Events
**SQL:** [`functions/events/skip_recurring_occurrence.md`](../../../functions/events/skip_recurring_occurrence.md)
**Tables written:** `event_mst` (UPDATE)

---

## Overview

Soft-deletes a single occurrence in a recurring series by setting `is_deleted = true` on that child row. The parent event and all other occurrences remain untouched. Only the event owner can skip occurrences.

Cannot be applied to:
- Parent events (`parent_event_id IS NULL`)
- Non-recurring events

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `p_event_id` | uuid | ✅ | The occurrence to skip (child row, not parent) |
| `p_user_id` | uuid | ✅ | The event owner (must match `creator_profiles.user_id` for the event's profile) |

---

## Request Example

```json
{
  "p_event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
  "p_user_id":  "be7bb571-1811-49f7-9bd5-a7db98c47815"
}
```

---

## Response

### Success

```json
{
  "status":  true,
  "message": "Occurrence skipped",
  "data": {
    "event_id":   "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
    "event_date": "2026-05-15",
    "title":      "Weekly Meetup"
  }
}
```

### Error

```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id and p_user_id are required` | Either UUID is null |
| `Event not found` | No event with that `event_id` exists |
| `You do not have permission to modify this event` | Caller is not the event owner |
| `Cannot skip a parent event or non-recurring event` | `parent_event_id IS NULL` (not a child occurrence) |
| `Something went wrong` | Unhandled DB exception (see `error` field) |

---

## Behavioural Notes

- **Soft delete only** — the child row remains in the database with `is_deleted = true`, so it can be restored if needed
- **Parent unaffected** — the parent event and recurring rule remain unchanged
- **Other occurrences unaffected** — other child rows in the same series continue to generate normally
- **Event list filtering** — `get_event_list` and similar queries must filter `is_deleted = false` to exclude skipped occurrences
- **Follows and reminders** — any `follow_reminder_dispatches` or `event_reminders` rows for this event_id should also be ignored (deleted or skipped) to avoid notifying about a non-existent occurrence

---

## Logic Flow

```
1. Null check: p_event_id, p_user_id
2. Locate event by p_event_id; fetch parent_event_id, profile_id, event_date, title
3. If not found → error "Event not found"
4. Fetch owner from creator_profiles.user_id
5. If caller ≠ owner → error "You do not have permission..."
6. If parent_event_id IS NULL → error "Cannot skip a parent event..."
7. UPDATE event_mst SET is_deleted = true WHERE event_id = p_event_id
8. Return { status: true, message, data: { event_id, event_date, title } }
```

---

## Related

- [`postpone_recurring_occurrence`](postpone_recurring_occurrence.md) — move a single occurrence to a new date/time
- [`update_event`](update_event.md) — update an event (series-level or per-occurrence)
- [`get_event_list`](get_event_list.md) — retrieve events (must filter `is_deleted = false`)
- [`event_mst` table](../../database/tables/08_event_mst.md)
