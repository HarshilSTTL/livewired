# SP: `get_profile_events`

**Endpoint:** `POST /rpc/get_profile_events`
**Group:** Events
**SQL:** [`functions/events/get_profile_events.md`](../../../functions/events/get_profile_events.md)
**Tables read:** `event_mst` · `event_platforms` · `platforms`

---

## Overview

Returns all events for a specific profile for a **7-day window** starting from
`p_week_start`. Used for the calendar/event list on the **profile view page**.

Each event includes the streaming platforms with their **logo** and **stream URL**
so Flutter can display platform icons directly on the event card.

Events are returned as a flat array sorted by `event_date ASC`, `event_time ASC`.
Flutter groups them by date to render the day-by-day list.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_profile_id` | uuid | ✅ | The profile whose events to fetch |
| `p_week_start` | date | ✅ | First day of the week to display (`YYYY-MM-DD`) |

> `p_week_start` should be the **Sunday** of the displayed week (e.g. `2026-03-29`
> for the "Week of Apr 5" view). The SP calculates `week_end = week_start + 6 days`
> internally.

---

## Request Example

```json
{
  "p_profile_id": "profile-uuid",
  "p_week_start": "2026-03-29"
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
    "week_start": "2026-03-29",
    "week_end":   "2026-04-04",
    "events": [
      {
        "event_id":     "uuid-1",
        "title":        "Metroid Monday!",
        "description":  null,
        "event_date":   "2026-03-30",
        "event_time":   "03:00:00",
        "livestream":   true,
        "video":        false,
        "is_recurring": true,
        "platforms": [
          {
            "platform_id":   1,
            "platform_name": "YouTube",
            "logo_url":      "https://cdn.example.com/yt.png",
            "stream_url":    "https://youtube.com/live/abc"
          },
          {
            "platform_id":   4,
            "platform_name": "Kick",
            "logo_url":      "https://cdn.example.com/kick.png",
            "stream_url":    "https://kick.com/handle"
          }
        ]
      },
      {
        "event_id":     "uuid-2",
        "title":        "Metroid Monday!",
        "description":  null,
        "event_date":   "2026-03-30",
        "event_time":   "10:00:00",
        "livestream":   true,
        "video":        false,
        "is_recurring": false,
        "platforms": [
          {
            "platform_id":   2,
            "platform_name": "Rumble",
            "logo_url":      "https://cdn.example.com/rumble.png",
            "stream_url":    "https://rumble.com/handle"
          },
          {
            "platform_id":   3,
            "platform_name": "Twitch",
            "logo_url":      "https://cdn.example.com/twitch.png",
            "stream_url":    "https://twitch.tv/handle"
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
    "week_start": "2026-03-29",
    "week_end":   "2026-04-04",
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
| `week_start` / `week_end` | Echo back the date range fetched |
| `events` | Flat array sorted by `event_date ASC`, `event_time ASC`. Always array, never null |
| `is_recurring` | `true` → show ↻ icon on the event card |
| `livestream` | `true` → show live indicator |
| `description` | Nullable — omit or show placeholder in UI |
| `platforms` | Each entry has `logo_url` (platform icon) + `stream_url` (tap to open stream) |
| `platforms[].logo_url` | From `platforms` table — use as platform icon image |
| `platforms[].stream_url` | From `event_platforms` table — deep link to the stream |

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
// Call get_profile_events again with new p_week_start
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Profile ID is required` | `p_profile_id` is null |
| `Week start date is required` | `p_week_start` is null |
| `Profile not found` | No profile with that ID |
| `Something went wrong` | Unhandled exception |

---

## Logic Flow

```
1. Null check: p_profile_id, p_week_start
2. Check profile exists in creator_profiles
3. Calculate v_week_end = p_week_start + 6 days
4. SELECT events WHERE profile_id = p_profile_id
   AND event_date BETWEEN p_week_start AND v_week_end
   ├── For each event: subquery platforms from event_platforms + platforms
   │   ⚠️ Cast event_platforms.platform_id::bigint to join platforms.plat_id
   └── ORDER BY event_date ASC, event_time ASC
5. RETURN week_start, week_end, events[]
```

---

## Profile View Flow (Both APIs Together)

```
User taps a profile card
 │
 ├── get_profile_by_id(p_profile_id)
 │     → profile_name, avatar_url, followers, bio, status
 │     → platforms[{ logo_url, channel_url }]   ← icons shown in Links row
 │     → tags[]
 │
 └── get_profile_events(p_profile_id, week_start)
       → events[{ title, event_date, event_time, is_recurring, platforms[{ logo_url, stream_url }] }]
                                                               ↑ icons shown on event cards

User swipes week left/right
 └── get_profile_events(p_profile_id, new_week_start)   ← only this re-fetches
```

> **Note:** `platforms` in `get_profile_by_id` comes from `creator_platform_accounts`
> (the creator's channel URLs). `platforms` in `get_profile_events` comes from
> `event_platforms` (stream URLs for that specific event). Both use `platforms.logo_url`
> for the icon.

---

## Related

- [`get_profile_by_id`](../profiles/get_profile_by_id.md) — profile detail (call together on profile open)
- [`get_event_list`](get_event_list.md) — global event feed (all profiles, date-based)
- [`create_event`](create_event.md) — create a new event
- [`event_mst` table](../../database/tables/08_event_mst.md)
- [`event_platforms` table](../../database/tables/09_event_platforms.md)
