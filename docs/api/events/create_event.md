# SP: `create_event`

**Endpoint:** `POST /rpc/create_event`
**Group:** Events
**SQL:** [`functions/events/create_event.md`](../../../functions/events/create_event.md)
**Tables written:** `event_mst` (INSERT) · `event_platforms` (INSERT) · `event_recurring` (INSERT if recurring)

---

## Overview

Creates a new event for a creator profile and optionally links it to streaming platforms.

For **recurring events**, the SP automatically pre-generates individual rows in `event_mst`
for every matching date between `recurring_start_date` and `recurring_end_date`. This means
querying events for any specific date will find them directly — no runtime expansion required.

---

## Recurring Event Pre-generation

When `p_is_recurring = true`, `create_event` inserts:

| What | `parent_event_id` | Purpose |
|---|---|---|
| **1 parent row** in `event_mst` | `NULL` | Stores the event definition (title, time, type) |
| **1 row** in `event_recurring` | — | Stores the recurrence rule (days, type, interval, dates) |
| **1 row** in `event_platforms` per platform | — | Stored on parent; all children inherit |
| **N child rows** in `event_mst` | `<parent event_id>` | One row per computed occurrence date |

Each child row has the correct `event_date` for its occurrence. `get_profile_events` returns
child rows directly by date — no calculation at query time.

If `p_recurring_end_date` is not provided, occurrences are generated **up to 1 year** from `p_recurring_start_date`.

### Occurrence date generation algorithm

| `recurring_type` | How occurrence dates are computed |
|---|---|
| `weekly` | For each day in `recurring_days`: find first occurrence of that weekday on/after `start_date`, then step +7×interval days until `end_date` |
| `first` | For each day in `recurring_days`: find the first occurrence of that weekday in each calendar month from `start_date` to `end_date` |
| `last` | For each day in `recurring_days`: find the last occurrence of that weekday in each calendar month |

### Example — weekly / Mon+Wed / every 2 weeks / Apr–May 2026

`p_recurring_days=["Mon","Wed"]`, `p_recurring_type="weekly"`, `p_recurring_interval=2`, `p_recurring_start_date=2026-04-06`

Rows inserted into `event_mst`:

| Row | `parent_event_id` | `event_date` |
|---|---|---|
| Parent | NULL | 2026-04-06 (p_event_date) |
| Child 1 | parent id | 2026-04-06 (Mon) |
| Child 2 | parent id | 2026-04-08 (Wed) |
| Child 3 | parent id | 2026-04-20 (Mon — skip week) |
| Child 4 | parent id | 2026-04-22 (Wed — skip week) |
| Child 5 | parent id | 2026-05-04 (Mon) |
| ... | parent id | ... |

---

## Parameters

### Core (always required/optional)

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `p_profile_id` | uuid | ✅ | — | Profile creating the event |
| `p_user_id` | uuid | ✅ | — | Caller's user ID (ownership check) |
| `p_title` | text | ✅ | — | Event title |
| `p_event_date` | date | ✅ | — | Date of the event in creator's local timezone (`YYYY-MM-DD`) |
| `p_event_time` | time | ✅ | — | Time of the event in creator's local timezone (`HH:MM:SS`) |
| `p_event_end_time` | time | ❌ | null | Optional end time in creator's local timezone (`HH:MM:SS`). If less than `p_event_time`, treated as next-day (cross-midnight). Cannot equal `p_event_time`. |
| `p_timezone` | text | ❌ | `'UTC'` | Creator's IANA timezone — e.g. `'America/New_York'`, `'Asia/Kolkata'` |
| `p_description` | text | ❌ | null | Event description |
| `p_livestream` | boolean | ❌ | false | Is this a live stream? |
| `p_video` | boolean | ❌ | false | Is this a video premiere? |
| `p_is_recurring` | boolean | ❌ | false | Is this recurring? If true, recurring params below are required |
| `p_platforms` | jsonb | ❌ | null | Platforms to stream on (see format below) |

### Recurring (required when `p_is_recurring = true`)

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_recurring_days` | text[] | ✅ | Days the event recurs. e.g. `["Mon","Wed","Fri"]` |
| `p_recurring_type` | text | ✅ | `'weekly'` · `'first'` · `'last'` |
| `p_recurring_interval` | int | ✅ when type=weekly | 1–12 weeks. Must be null for `first`/`last` |
| `p_recurring_start_date` | date | ✅ | When the recurring schedule begins |
| `p_recurring_end_date` | date | ❌ | When recurring ends. If omitted, generates 1 year of occurrences |

### p_platforms format

```json
[
  { "platform_id": 1, "stream_url": "https://youtube.com/live/abc123" },
  { "platform_id": 2, "stream_url": "https://twitch.tv/handle" }
]
```

---

## `recurring_type` + `recurring_interval` Mapping

| UI (Repeats dropdown) | `p_recurring_type` | `p_recurring_interval` |
|-----------------------|--------------------|------------------------|
| Every week            | `"weekly"`         | `1`                    |
| Every 2nd week        | `"weekly"`         | `2`                    |
| Every 3rd week        | `"weekly"`         | `3`                    |
| Every 4th week        | `"weekly"`         | `4`                    |
| Custom (slider 1–12)  | `"weekly"`         | `1`–`12`               |
| First                 | `"first"`          | omit / null            |
| Last                  | `"last"`           | omit / null            |

---

## Request Examples

### Non-recurring event
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_title":      "Special Stream",
  "p_event_date": "2026-04-15",
  "p_event_time": "18:00:00",
  "p_event_end_time": "20:00:00",
  "p_timezone":   "America/New_York",
  "p_livestream": true
}
```

### Recurring — Every 2nd week on Mon/Wed/Fri
```json
{
  "p_profile_id":             "profile-uuid",
  "p_user_id":                "user-uuid",
  "p_title":                  "Weekly Gaming Session",
  "p_event_date":             "2026-04-08",
  "p_event_time":             "20:00:00",
  "p_event_end_time":         "22:00:00",
  "p_livestream":             true,
  "p_is_recurring":           true,
  "p_recurring_days":         ["Mon", "Wed", "Fri"],
  "p_recurring_type":         "weekly",
  "p_recurring_interval":     2,
  "p_recurring_start_date":   "2026-04-08",
  "p_recurring_end_date":     "2026-12-31",
  "p_platforms": [
    { "platform_id": 1, "stream_url": "https://youtube.com/live/xyz" }
  ]
}
```

### Recurring — First occurrence of Mon/Tue in each month
```json
{
  "p_profile_id":           "profile-uuid",
  "p_user_id":              "user-uuid",
  "p_title":                "Monthly Recap",
  "p_event_date":           "2026-04-06",
  "p_event_time":           "19:00:00",
  "p_event_end_time":       "20:00:00",
  "p_is_recurring":         true,
  "p_recurring_days":       ["Mon", "Tue"],
  "p_recurring_type":       "first",
  "p_recurring_start_date": "2026-04-06"
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Event created successfully",
  "data": {
    "event_id": "parent-event-uuid"
  }
}
```

> `event_id` returned is the **parent** event_id. All child occurrences link back to it
> via `parent_event_id`. Use this ID to update or delete the entire recurring series.

### Error
```json
{
  "status":  false,
  "message": "<reason>"
}
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Profile ID is required` | `p_profile_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Profile not found, access denied, or profile is not active` | Profile doesn't exist, wrong owner, or status ≠ 'active' |
| `Event title is required` | `p_title` null or empty |
| `Event date is required` | `p_event_date` is null |
| `Event time is required` | `p_event_time` is null |
| `Event end time cannot be the same as event start time` | `p_event_end_time = p_event_time` (zero-duration). Values less than start time are valid — treated as next day |
| `One or more platform IDs are invalid` | `platform_id` not in `platforms` table |
| `Stream URL is required for each platform` | Platform object missing `stream_url` |
| `Recurring days are required` | `p_recurring_days` null or empty when `p_is_recurring = true` |
| `Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun` | Invalid day string in array |
| `recurring_type must be weekly, first, or last` | Invalid or null `p_recurring_type` |
| `recurring_interval is required for weekly type` | `p_recurring_interval` null when type='weekly' |
| `recurring_interval must be between 1 and 12` | Interval out of range |
| `recurring_interval must be null for first/last type` | Interval passed when type='first' or 'last' |
| `Recurring start date is required` | `p_recurring_start_date` null when `p_is_recurring = true` |
| `Recurring end date must be after start date` | `p_recurring_end_date <= p_recurring_start_date` |
| `Something went wrong` | Unhandled exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Null check: p_profile_id, p_user_id
2. Ownership + active check on creator_profiles
3. Required field checks: title, event_date, event_time
4. Platform validation (if p_platforms non-null/non-empty)
5. Recurring validation (only if p_is_recurring = true):
   ├── recurring_days: non-null, non-empty, all valid abbreviations
   ├── recurring_type: must be 'weekly' | 'first' | 'last'
   ├── If type='weekly': interval required, must be 1–12
   ├── If type='first'/'last': interval must be null
   ├── recurring_start_date: required
   └── recurring_end_date: if provided, must be > start_date
6. Convert (p_event_date + p_event_time) from p_timezone → UTC → v_utc_date, v_utc_time
7. INSERT parent row into event_mst with UTC date/time + event_timezone → returns v_event_id
7. If p_platforms non-null/non-empty:
   └── INSERT into event_platforms (on parent only; children inherit)
8. If p_is_recurring = true:
   ├── INSERT into event_recurring (recurrence rule for parent)
   ├── v_safe_end = COALESCE(p_recurring_end_date, p_recurring_start_date + 1 year)
   └── Generate child occurrence rows:
       weekly → FOREACH day: find first_occ >= start, WHILE occ <= safe_end: INSERT, advance +7×interval
       first  → FOREACH day: WHILE month <= safe_end: INSERT first weekday of month (if in range), advance month
       last   → FOREACH day: WHILE month <= safe_end: INSERT last weekday of month (if in range), advance month
9. RETURN success with parent event_id
```

---

## Related

- [`update_event`](update_event.md) — update event + recurring schedule
- [`delete_event`](delete_event.md) — delete event (cascades to all child occurrences)
- [`get_profile_events`](get_profile_events.md) — fetch events for a week (reads pre-generated child rows)
- [`get_event_list`](get_event_list.md) — read events by date
- [`event_mst` table](../../database/tables/08_event_mst.md)
- [`event_platforms` table](../../database/tables/09_event_platforms.md)
- [`event_recurring` table](../../database/tables/13_event_recurring.md)
