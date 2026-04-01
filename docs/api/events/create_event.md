# SP: `create_event`

**Endpoint:** `POST /rpc/create_event`
**Group:** Events
**SQL:** [`functions/events/create_event.md`](../../../functions/events/create_event.md)
**Tables written:** `event_mst` (INSERT) · `event_platforms` (INSERT) · `event_recurring` (INSERT if recurring)

---

## Overview

Creates a new event for a creator profile and optionally links it to streaming platforms.
If the event is recurring, a row is also inserted into `event_recurring` with the full
schedule details. All three tables are written atomically.

---

## Parameters

### Core (always required/optional)

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `p_profile_id` | uuid | ✅ | — | Profile creating the event |
| `p_user_id` | uuid | ✅ | — | Caller's user ID (ownership check) |
| `p_title` | text | ✅ | — | Event title |
| `p_event_date` | date | ✅ | — | Date of the event (`YYYY-MM-DD`) |
| `p_event_time` | time | ✅ | — | Time of the event (`HH:MM:SS`) |
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
| `p_recurring_end_date` | date | ❌ | When recurring ends (null = open-ended) |

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
| --------------------- | ------------------ | ---------------------- |
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
    "event_id": "generated-uuid"
  }
}
```

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
6. INSERT INTO event_mst → returns event_id
7. If p_platforms non-null/non-empty:
   └── INSERT INTO event_platforms (platform_id stored as int4)
8. If p_is_recurring = true:
   └── INSERT INTO event_recurring
9. RETURN success with event_id
```

---

## Related

- [`update_event`](update_event.md) — update event + recurring schedule
- [`delete_event`](delete_event.md) — delete event (cascades to event_recurring)
- [`get_event_list`](get_event_list.md) — read events by date
- [`event_mst` table](../../database/tables/08_event_mst.md)
- [`event_platforms` table](../../database/tables/09_event_platforms.md)
- [`event_recurring` table](../../database/tables/13_event_recurring.md)
