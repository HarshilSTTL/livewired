# SP: `get_profile_events` (v1 & v2)

**Endpoints:** 
- **v1:** `POST /rpc/get_profile_events` (previous, unordered)
- **v2:** `POST /rpc/get_profile_events_v2` (current, preference-ordered) ✅ **RECOMMENDED**

**Group:** Events
**SQL:** [`functions/events/get_profile_events.md`](../../../functions/events/get_profile_events.md)

## App Screen

![Profile Events Screen](../../assets/screenshots/profile_events.png)

> This screen shows the weekly calendar (week navigator + day strip) and events grouped by date, each with time, title, platform icons, and bell icon. The ↻ icon on event title indicates a recurring event.
> Save screenshot as: `docs/assets/screenshots/profile_events.png`
**Tables read:** `event_mst` · `event_platforms` · `platforms` · `event_collaborators`

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
| `p_profile_id` | uuid | ✅ | The profile whose events to fetch |
| `p_week_start` | date | ✅ | First day of the week in **viewer's local timezone** (`YYYY-MM-DD`) |
| `p_timezone` | text | ❌ | Viewer's IANA timezone — e.g. `'Asia/Kolkata'`. All `event_date`/`event_time` values returned in this timezone. Default: `'UTC'` |

> `p_week_start` should be the **Sunday** of the displayed week (e.g. `2026-04-05`
> for the "Week of Apr 5–11" view). The SP calculates `week_end = week_start + 6 days` internally.

---

## Request Example

```json
{
  "p_profile_id": "profile-uuid",
  "p_week_start": "2026-04-05",
  "p_timezone":   "Asia/Kolkata"
}
```

---

## Response (v2 — Current ✅)

### Success (v2)
```json
{
  "status":  true,
  "message": "Events fetched successfully",
  "data": {
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
        "event_end_time":  "05:00:00",
        "livestream":      true,
        "video":           false,
        "is_collaborative": false,
        "is_recurring":    true,
        "collaborators":   null,
        "platforms": [
          {
            "platform_id":   2,
            "type":          "platform",
            "platform_name": "Twitch",
            "logo_url":      "https://cdn.example.com/twitch.png",
            "stream_url":    "https://twitch.tv/user/live"
          },
          {
            "platform_id":   1,
            "type":          "platform",
            "platform_name": "YouTube",
            "logo_url":      "https://cdn.example.com/yt.png",
            "stream_url":    "https://youtube.com/live/abc"
          }
        ],
        "additional_links": [
          {
            "platform_id":   5,
            "type":          "additional_link",
            "platform_name": "Discord",
            "logo_url":      "https://cdn.example.com/discord.png",
            "stream_url":    "https://discord.com/invite/abc"
          }
        ]
      }
    ]
  }
}
```

---

## Response (v1 — Previous)

### Success (v1)
```json
{
  "status":  true,
  "message": "Events fetched successfully",
  "data": {
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
        "event_end_time":  "05:00:00",
        "livestream":      true,
        "video":           false,
        "is_collaborative": false,
        "is_recurring":    true,
        "collaborators":   null,
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

---

## Key Differences: v1 vs v2

| Feature | v1 | v2 |
|---------|----|----|
| **Platform Ordering** | By name alphabetically | By user drag-drop preferences |
| **Type Field** | ❌ No | ✅ Yes (`platform`, `additional_link`) |
| **Platform Grouping** | Single array | `platforms` (1-4) + `additional_links` (5+) |
| **Preference Support** | ❌ No | ✅ Uses `profile_link_preferences` table |
| **Endpoint** | `/rpc/get_profile_events` | `/rpc/get_profile_events_v2` |

**Recommendation:** Use v2 for new implementations. v1 maintained for backwards compatibility.

### No events this week
```json
{
  "status":  true,
  "message": "Events fetched successfully",
  "data": {
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
| `week_start` / `week_end` | Echo back the date range fetched |
| `events` | Flat array sorted by `event_date ASC`, `event_time ASC`. Always array, never null |
| `event_id` | The child occurrence row's own UUID (use for single-event actions) |
| `parent_event_id` | Present on recurring occurrences — the parent/template event UUID. null for non-recurring |
| `event_date` | The actual date of this occurrence |
| `event_end_time` | Nullable — if present, the event has a defined end time |
| `is_collaborative` | `true` → event has collaborators enabled. Shown for both owner events and events where this profile is an accepted collaborator |
| `is_recurring` | `true` → show ↻ icon on the event card |
| `livestream` | `true` → show live indicator |
| `description` | Nullable — omit or show placeholder in UI |
| `collaborators` | Array of collaborator objects with `profile_id`, `profile_name`, `avatar`, `status` ('pending' \| 'accepted' \| 'declined'); null if no collaborators |
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
4. SELECT from event_mst WHERE:
   - (profile_id = p_profile_id
      OR COALESCE(parent_event_id, event_id) IN accepted collaborators for this profile)
     → includes own events AND events where this profile is an accepted collaborator
   - event_date BETWEEN p_week_start AND v_week_end
   - is_deleted = false
   - (is_recurring = false OR parent_event_id IS NOT NULL)
     → returns non-recurring events + recurring child occurrences
     → excludes recurring parent/template rows
5. For each event: subquery platforms using is_overridden CASE:
   WHERE ep.event_id = CASE
     WHEN e.is_overridden THEN e.event_id
     ELSE COALESCE(e.parent_event_id, e.event_id)
   END
   → is_overridden = true → child was edited via p_scope='this', use its own platforms
   → is_overridden = false → child inherits parent's platforms (default)
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
       → events[{ title, event_date, event_time, is_collaborative, is_recurring,
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
