# SP: `update_event`

**Endpoint:** `POST /rpc/update_event`
**Group:** Events
**SQL:** [`functions/events/update_event.md`](../../../functions/events/update_event.md)
**Tables written:** `event_mst` · `event_platforms` · `event_recurring`

---

## Overview

Updates a single event. All fields except `p_event_id` and `p_user_id` are optional — only passed (non-null) fields are applied (COALESCE pattern). Only the event **owner** can update — collaborators do not have update permission.

**Platforms:** `null` = don't touch · `[]` = clear all · `[{...}]` = replace all

**Recurring:** Pass `p_recurring_days` to trigger a recurring rule update. All existing child occurrence rows are deleted and regenerated from the new rules. Any recurring field not passed keeps its existing value.

---

## Parameters

### Core fields

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to update |
| `p_user_id` | uuid | ✅ | Must own the profile that created this event |
| `p_title` | text | ❌ | New title |
| `p_description` | text | ❌ | New description |
| `p_event_date` | date | ❌ | New date in creator's local timezone (`YYYY-MM-DD`) |
| `p_event_time` | time | ❌ | New time in creator's local timezone (`HH:MM:SS`) |
| `p_event_end_time` | time | ❌ | Optional end time (`HH:MM:SS`). If less than start time, treated as next-day (cross-midnight). Cannot equal start time. |
| `p_timezone` | text | ❌ | Creator's IANA timezone — e.g. `'America/New_York'` |
| `p_livestream` | boolean | ❌ | Toggle livestream flag |
| `p_video` | boolean | ❌ | Toggle video flag |
| `p_is_collaborative` | boolean | ❌ | Enable or disable collaborative mode |
| `p_platforms` | jsonb | ❌ | `null` = no change · `[]` = clear · `[{...}]` = replace |

### Recurring fields (pass `p_recurring_days` to trigger recurring update)

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_recurring_days` | text[] | ❌ | Days to recur — e.g. `["Mon","Wed"]`. Triggers full child regeneration |
| `p_recurring_type` | text | ❌ | `'weekly'` · `'first'` · `'last'` — kept from existing if not passed |
| `p_recurring_interval` | int | ❌ | 1–12 weeks (weekly type only) |
| `p_recurring_start_date` | date | ❌ | New start date for the recurring schedule |
| `p_recurring_end_date` | date | ❌ | New end date (null = open-ended) |

> Passing `p_recurring_days` is the trigger. Any recurring field not passed keeps its current value via COALESCE.

---

## Request Examples

### Update title only
```json
{
  "p_event_id": "uuid...",
  "p_user_id":  "uuid...",
  "p_title":    "Metroid Monday — Special Edition"
}
```

### Update recurring schedule — change to every 2 weeks
```json
{
  "p_event_id":           "uuid...",
  "p_user_id":            "uuid...",
  "p_recurring_days":     ["Mon", "Wed"],
  "p_recurring_type":     "weekly",
  "p_recurring_interval": 2,
  "p_recurring_end_date": "2026-12-31"
}
```

### Replace platforms
```json
{
  "p_event_id":  "uuid...",
  "p_user_id":   "uuid...",
  "p_platforms": [
    { "platform_id": 1, "stream_url": "https://youtube.com/live/abc" },
    { "platform_id": 2, "stream_url": "https://twitch.tv/creatorone" }
  ]
}
```

### Clear all platforms
```json
{
  "p_event_id":  "uuid...",
  "p_user_id":   "uuid...",
  "p_platforms": []
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Event updated successfully" }
```

### Error
```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id and p_user_id are required` | Either required param is null |
| `Event not found or access denied` | No matching event, caller is not the owner or an accepted collaborator |
| `Event end time cannot be the same as event start time` | Final end time equals final start time (zero-duration). End time less than start time is valid — treated as next day |
| `One or more platform IDs are invalid` | A `platform_id` in `p_platforms` does not exist |
| `Stream URL is required for each platform` | A platform object is missing `stream_url` |
| `Recurring days cannot be empty` | `p_recurring_days` passed as empty array |
| `Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun` | Invalid day string |
| `recurring_type must be weekly, first, or last` | Invalid type value |
| `recurring_interval is required for weekly type` | Interval null when type is weekly |
| `recurring_interval must be between 1 and 12` | Interval out of range |
| `recurring_interval must be null for first/last type` | Interval passed for first/last |
| `Recurring start date is required` | No start date in DB or passed |
| `Recurring end date must be after start date` | End ≤ start |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null check: p_event_id, p_user_id
2. Ownership check: event_mst JOIN creator_profiles
3. Validate p_platforms (if provided and non-empty)
4. If p_recurring_days IS NOT NULL:
   - Fetch existing event_recurring row (for COALESCE)
   - Merge passed values over existing
   - Validate merged recurring rule
5. UPDATE event_mst with COALESCE for all optional fields
6. If p_platforms IS NOT NULL:
   - DELETE + INSERT event_platforms (full replace)
7. If p_recurring_days IS NOT NULL:
   - UPDATE event_recurring with merged values
   - DELETE all child rows (WHERE parent_event_id = p_event_id)
   - Fetch parent row (profile_id, title, description, event_time, event_timezone, etc.)
   - Regenerate child rows using same algorithm as create_event
     weekly → FOREACH day: find first occ, step +7×interval until safe_end
     first/last → FOREACH day: WHILE month <= safe_end: insert first/last weekday of month
8. Return success
```

---

## Related

- [`get_event_by_id`](get_event_by_id.md) — fetch current event state before editing
- [`create_event`](create_event.md) — original creation
- [`delete_event`](delete_event.md) — remove this event
- [`event_recurring` table](../../database/tables/13_event_recurring.md)
