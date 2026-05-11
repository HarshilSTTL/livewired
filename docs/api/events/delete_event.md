# SP: `delete_event`

**Endpoint:** `POST /rpc/delete_event`
**Group:** Events
**SQL:** [`functions/events/delete_event.md`](../../../functions/events/delete_event.md)
**Tables written:** `event_mst` (UPDATE), `event_reminders` (soft delete), `event_collaborators` (soft delete)

---

## Overview

Soft-deletes an event with scope control for recurring series. Uses the same scope logic as `update_event`:
- **`'this'`** — delete only a single occurrence (child row)
- **`'all'`** — delete entire recurring series (parent + all children) OR single event

The UI presents two options on the delete confirmation:
- **"For This Only"** → passes `scope: 'this'` (only that occurrence)
- **"For All"** → passes `scope: 'all'` (entire series)

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| `p_event_id` | uuid | ✅ | — | The event to delete (can be parent or child occurrence) |
| `p_user_id` | uuid | ✅ | — | The event owner (must match creator_profiles.user_id for the event's profile) |
| `p_scope` | text | ❌ | `'all'` | `'this'` (single occurrence) or `'all'` (entire series/event) |

---

## Request Examples

### Delete single occurrence ("For This Only")

```json
{
  "p_event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
  "p_user_id":  "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_scope":    "this"
}
```

### Delete entire recurring series ("For All")

```json
{
  "p_event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
  "p_user_id":  "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_scope":    "all"
}
```

### Delete non-recurring event (scope defaults to 'all')

```json
{
  "p_event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
  "p_user_id":  "be7bb571-1811-49f7-9bd5-a7db98c47815"
}
```

---

## Response

### Success — Occurrence deleted

```json
{
  "status": true,
  "message": "Occurrence deleted",
  "data": {
    "event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
    "scope": "this",
    "title": "Weekly Meetup",
    "deleted_at": "2026-05-11T14:30:00+00:00"
  }
}
```

### Success — Series deleted

```json
{
  "status": true,
  "message": "Recurring series deleted (13 occurrences)",
  "data": {
    "event_id": "f8d4c2a1-7e9b-4c3d-8f2e-1a5b6c7d8e9f",
    "parent_event_id": null,
    "scope": "all",
    "title": "Weekly Meetup",
    "occurrences_deleted": 13,
    "deleted_at": "2026-05-11T14:30:00+00:00"
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
| `p_scope must be either "this" or "all"` | Invalid scope value passed |
| `Event not found` | No event with that `event_id` exists |
| `You do not have permission to delete this event` | Caller is not the event owner |
| `Cannot delete "this" on a parent or non-recurring event. Use scope="all" to delete the entire series.` | Tried to delete scope='this' on a parent/non-recurring event |
| `Something went wrong` | Unhandled DB exception |

---

## Scope Behavior

### Scope = `'this'` (Single Occurrence)

**Only works on child occurrences** (`parent_event_id IS NOT NULL`)

- Soft deletes only that specific occurrence (`is_deleted = true`)
- Parent event and all other occurrences remain intact
- Associated reminders for this event are soft-deleted
- Associated collaborators for this event are soft-deleted
- Error if attempted on parent or non-recurring event

**Use case:** User wants to cancel just Monday's event, keep the rest of the series

### Scope = `'all'` (Entire Series / Single Event)

**Works on any event** (parent, child, or non-recurring)

- If called on a **child occurrence**: deletes the parent AND all child occurrences
- If called on a **parent/template**: deletes the parent AND all child occurrences
- If called on a **non-recurring event**: deletes that single event
- Soft deletes ALL reminders and collaborators associated with the series/event
- Returns count of deleted occurrences for recurring series

**Use case:** User cancels entire event series or single event

---

## Response Fields

| Field | Notes |
|-------|-------|
| `status` | `true` = deletion successful |
| `message` | Human-readable message. For recurring: shows occurrence count. For single: "Event deleted" |
| `data.event_id` | The original event_id passed in the request |
| `data.parent_event_id` | Present when scope='all' and event is recurring. Null for single events |
| `data.scope` | The scope that was used ('this' or 'all') |
| `data.title` | The event title (for confirmation/logging) |
| `data.occurrences_deleted` | Count of deleted occurrences (only for recurring series with scope='all') |
| `data.deleted_at` | UTC timestamp when deletion occurred |

---

## UI Integration

On the delete confirmation screen, show two options:

```
🗑️ Delete Event

⚠️ "Weekly Meetup" occurs every Monday

[For This Only] → passes scope: 'this'
[For All]       → passes scope: 'all'

[Cancel]
```

---

## Soft Delete Notes

- All deletions are **soft deletes** (`is_deleted = true`, `deleted_at` set)
- Rows are not removed from database, can be restored if needed
- Event list queries must filter `is_deleted = false` to exclude deleted events
- Reminders and collaborator records for deleted events are also soft-deleted
- Soft delete cascades to associated follow_reminder_dispatches via event_mst FK

---

## Related

- [`skip_recurring_occurrence`](skip_recurring_occurrence.md) — alternative to soft-delete for single occurrences
- [`update_event`](update_event.md) — update events (uses same scope logic)
- [`get_event_list`](get_event_list.md) — fetch events (filters deleted)
- [`get_profile_events`](get_profile_events.md) — fetch profile events (filters deleted)
- [`event_mst` table](../../database/tables/08_event_mst.md)
