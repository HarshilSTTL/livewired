# SP: `postpone_recurring_occurrence`

**Endpoint:** `POST /rpc/postpone_recurring_occurrence`
**Group:** Events
**SQL:** [`functions/events/postpone_recurring_occurrence.md`](../../../functions/events/postpone_recurring_occurrence.md)
**Tables written:** `event_mst` (UPDATE)

---

## Overview

Moves a single occurrence in a recurring series to a new date and/or time. The parent event and all other occurrences remain untouched. Only the event owner can postpone occurrences.

The new date must not be in the past (≥ today). If `p_new_time` is omitted, the existing time is preserved.

Cannot be applied to:
- Parent events (`parent_event_id IS NULL`)
- Non-recurring events

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `p_event_id` | uuid | ✅ | The occurrence to postpone (child row, not parent) |
| `p_user_id` | uuid | ✅ | The event owner (must match `creator_profiles.user_id` for the event's profile) |
| `p_new_date` | date | ✅ | New date (must be ≥ today, not in the past) |
| `p_new_time` | time | ❌ | New time. If omitted, keeps the existing time. |

---

## Request Examples

### Change date only, keep existing time

```json
{
  "p_event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
  "p_user_id":  "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_new_date": "2026-05-20"
}
```

### Change both date and time

```json
{
  "p_event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
  "p_user_id":  "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_new_date": "2026-05-20",
  "p_new_time": "19:30:00"
}
```

---

## Response

### Success

```json
{
  "status":  true,
  "message": "Occurrence postponed",
  "data": {
    "event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
    "old_date": "2026-05-15",
    "new_date": "2026-05-20",
    "new_time": "19:30:00",
    "title":    "Weekly Meetup"
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
| `p_event_id, p_user_id, and p_new_date are required` | Any of these three parameters is null |
| `Event not found` | No event with that `event_id` exists |
| `You do not have permission to modify this event` | Caller is not the event owner |
| `Cannot postpone a parent event or non-recurring event` | `parent_event_id IS NULL` (not a child occurrence) |
| `New date cannot be in the past` | `p_new_date < CURRENT_DATE` |
| `Something went wrong` | Unhandled DB exception (see `error` field) |

---

## Behavioural Notes

- **Time preservation** — if `p_new_time` is omitted, the existing time from the child row is kept unchanged
- **Date-only change** — passing only `p_new_date` is the most common use case (e.g., "move Monday's meeting from May 15 to May 20")
- **Parent unaffected** — the parent event and recurring rule remain unchanged; only this child row is modified
- **Other occurrences unaffected** — all other child rows in the same series remain on their original schedules
- **Past-date rejection** — new_date must be ≥ CURRENT_DATE; cannot postpone to a historical date
- **Event list impact** — the occurrence now appears on the new date; old date will no longer show it in `get_event_list`
- **Reminders and follows** — if the occurrence had a `follow_reminder_dispatches` or `event_reminders` row with the old time, it may not fire at the new time. Consider the new schedule when updating manually-set reminders.

---

## Logic Flow

```
1. Null check: p_event_id, p_user_id, p_new_date
2. Locate event by p_event_id; fetch parent_event_id, profile_id, event_date, event_time, title
3. If not found → error "Event not found"
4. Fetch owner from creator_profiles.user_id
5. If caller ≠ owner → error "You do not have permission..."
6. If parent_event_id IS NULL → error "Cannot postpone a parent event..."
7. If p_new_date < CURRENT_DATE → error "New date cannot be in the past"
8. v_final_time = COALESCE(p_new_time, existing event_time)
9. UPDATE event_mst SET event_date = p_new_date, event_time = v_final_time
10. Return { status: true, message, data: { event_id, old_date, new_date, new_time, title } }
```

---

## Related

- [`skip_recurring_occurrence`](skip_recurring_occurrence.md) — remove a single occurrence (soft delete)
- [`update_event`](update_event.md) — update an event (series-level or per-occurrence)
- [`get_event_list`](get_event_list.md) — retrieve events
- [`event_mst` table](../../database/tables/08_event_mst.md)
