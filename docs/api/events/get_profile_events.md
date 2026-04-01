# SP: `get_profile_events`

**Endpoint:** `POST /rpc/get_profile_events`
**Group:** Events
**SQL:** [`functions/events/get_profile_events.md`](../../../functions/events/get_profile_events.md)
**Tables read:** `creator_profiles` · `event_mst` · `event_platforms` · `platforms`

---

## Overview

Returns all events for a specific profile for a **7-day window** starting from `p_week_start`.
Used for the calendar/event list on the **profile view page**.

Events are sorted by `event_date ASC`, `event_time ASC`. Flutter groups them by date
to render the day-by-day list. Specific date taps filter the already-loaded week data client-side.

### How recurring events appear

`create_event` pre-generates a child row in `event_mst` for every occurrence date when a
recurring event is created. This SP simply queries by date — recurring events appear automatically
on every correct date without any special logic.

The filter `(is_recurring = false OR parent_event_id IS NOT NULL)` excludes the recurring
parent/template row (which holds the definition but has no meaningful display date).

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_username` | text | ✅ | The profile's username (resolved to profile_id internally) |
| `p_week_start` | date | ✅ | First day of the week to display (`YYYY-MM-DD`) |

> `p_week_start` should be the **Sunday** of the displayed week (e.g. `2026-04-05`
> for the "Week of Apr 5–11" view). The SP calculates `week_end = week_start + 6 days` internally.

---

## Request Example

```json
{
  "p_username":   "john_doe",
  "p_week_start": "2026-04-05"
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Events fetched successfully",
  "data": {
    "username":   "john_doe",
    "week_start": "2026-04-05",
    "week_end":   "2026-04-11",
    "events": [
      {
        "event_id":        "child-occurrence-uuid",
        "parent_event_id": "parent-template-uuid",
        "title":           "Metroid Monday!",
        "description":     null,
        "event_date":      "2026-04-06",
        "event_time":      "03:00:00",
        "livestream":      true,
        "video":           false,
        "is_recurring":    true,
        "platforms": [
          {
            "platform_id":   1,
            "platform_name": "YouTube",
            "logo_url":      "https://cdn.example.com/yt.png",
            "stream_url":    "https://youtube.com/live/abc"
          }
        ]
      }
    ]
  }
}
```

### No events this week
```json
{
  "status":  true,
  "message": "Events fetched successfully",
  "data": {
    "username":   "john_doe",
    "week_start": "2026-04-05",
    "week_end":   "2026-04-11",
    "events": []
  }
}
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Response Field Notes

| Field | Notes |
|---|---|
| `username` | Echoes back the username passed in |
| `week_start` / `week_end` | Echo back the date range fetched |
| `events` | Flat array sorted by `event_date ASC`, `event_time ASC`. Always array, never null |
| `event_id` | The child occurrence row's own UUID (use for single-event actions) |
| `parent_event_id` | Present on recurring occurrences — the parent/template event UUID. null for non-recurring |
| `event_date` | The actual date of this occurrence |
| `is_recurring` | `true` → show ↻ icon on the event card |
| `livestream` | `true` → show live indicator |
| `description` | Nullable — omit or show placeholder in UI |
| `platforms` | Each entry has `logo_url` (platform icon) + `stream_url` (tap to open stream) |
| `platforms[].logo_url` | From `platforms` table — use as platform icon image |
| `platforms[].stream_url` | From `event_platforms` on the parent event — deep link to the stream |

---

## Flutter Usage

```dart
// Group events by date client-side for the day list:
Map<String, List<Event>> grouped = {};
for (var event in events) {
  grouped.putIfAbsent(event.eventDate, () => []).add(event);
}

// Navigate week:
DateTime nextWeekStart = currentWeekStart.add(Duration(days: 7));
// Call get_profile_events again with new p_week_start — recurring events
// appear automatically because their rows already exist in the database.
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Username is required` | `p_username` is null or empty |
| `Week start date is required` | `p_week_start` is null |
| `Profile not found` | No profile matches that username |
| `Something went wrong` | Unhandled exception |

---

## Logic Flow

```
1. Null check: p_username, p_week_start
2. SELECT id FROM creator_profiles WHERE username = p_username → v_profile_id
   Return error if not found
3. Calculate v_week_end = p_week_start + 6 days
4. SELECT from event_mst WHERE:
   - profile_id = v_profile_id
   - event_date BETWEEN p_week_start AND v_week_end
   - (is_recurring = false OR parent_event_id IS NOT NULL)
     → returns non-recurring events + recurring child occurrences
     → excludes recurring parent/template rows
5. For each event: subquery platforms
   WHERE ep.event_id = COALESCE(e.parent_event_id, e.event_id)
   → recurring children inherit platforms from their parent
   ⚠️ Cast event_platforms.platform_id::bigint to join platforms.plat_id
6. RETURN week_start, week_end, events[] sorted by event_date ASC, event_time ASC
```

---

## Profile View Flow (Both APIs Together)

```
User taps a profile card
 │
 ├── get_profile_by_id(p_profile_id)
 │     → profile_name, avatar, followers, bio, status
 │     → platforms[{ logo_url, channel_url }]   ← icons shown in Links row
 │     → tags[]
 │
 └── get_profile_events(p_profile_id, week_start)
       → events[{ title, event_date, event_time, is_recurring,
                  platforms[{ logo_url, stream_url }] }]
                  ↑ icons shown on event cards

User swipes week left/right
 └── get_profile_events(p_profile_id, new_week_start)
     Recurring events appear automatically — their rows already exist in event_mst
```

> **Note:** `platforms` in `get_profile_by_id` comes from `creator_platform_accounts`
> (the creator's channel URLs). `platforms` in `get_profile_events` comes from
> `event_platforms` on the parent event (stream URLs for that specific event).
> Both use `platforms.logo_url` for the icon.

---

## Related

- [`get_profile_by_id`](../profiles/get_profile_by_id.md) — profile detail (call together on profile open)
- [`create_event`](create_event.md) — creates the event + pre-generates all recurring occurrence rows
- [`get_event_list`](get_event_list.md) — global event feed (all profiles, date-based)
- [`event_mst` table](../../database/tables/08_event_mst.md)
- [`event_recurring` table](../../database/tables/13_event_recurring.md)
- [`event_platforms` table](../../database/tables/09_event_platforms.md)
