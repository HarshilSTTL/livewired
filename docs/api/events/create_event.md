# SP: `create_event`

**Endpoint:** `POST /rpc/create_event`
**Group:** Events
**SQL:** [`functions/events/create_event.md`](../../../functions/events/create_event.md)
**Tables written:** `event_mst` (INSERT) · `event_platforms` (INSERT)

---

## Overview

Creates a new event for a creator profile and optionally links it to one or more streaming
platforms. Both tables are written in a single atomic call. The event belongs to a profile
(not directly to a user) — ownership is verified by checking that `profile_id` belongs to
`p_user_id` and is `'active'`.

---

## Parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `p_profile_id` | uuid | ✅ | — | Profile creating the event (must belong to `p_user_id`) |
| `p_user_id` | uuid | ✅ | — | Caller's user ID (ownership check) |
| `p_title` | text | ✅ | — | Event title |
| `p_event_link` | text | ✅ | — | Primary stream/event URL |
| `p_event_date` | date | ✅ | — | Date of the event (`YYYY-MM-DD`) |
| `p_event_time` | time | ✅ | — | Time of the event (`HH:MM:SS`) |
| `p_description` | text | ❌ | null | Event description (nullable) |
| `p_livestream` | boolean | ❌ | false | Is this a live stream? (drives live section in `get_event_list`) |
| `p_video` | boolean | ❌ | false | Is this a video premiere? |
| `p_is_recurring` | boolean | ❌ | false | Is this a repeating event? |
| `p_platforms` | jsonb | ❌ | null | Platforms to stream on (see format below) |

### p_platforms format

```json
[
  { "platform_id": 1, "stream_url": "https://youtube.com/live/abc123" },
  { "platform_id": 2, "stream_url": "https://twitch.tv/handle" }
]
```

> ⚠️ `platform_id` is stored as **`int4`** in `event_platforms` (not int8). The SP handles
> this cast internally — pass a normal integer from Flutter.

---

## Request Examples

### Minimal (no platforms)
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_title":      "My Live Stream",
  "p_event_link": "https://youtube.com/live/xyz",
  "p_event_date": "2026-04-15",
  "p_event_time": "18:00:00",
  "p_livestream": true
}
```

### Full (with platforms)
```json
{
  "p_profile_id":   "profile-uuid",
  "p_user_id":      "user-uuid",
  "p_title":        "Gaming Session",
  "p_description":  "Weekly gaming stream",
  "p_event_link":   "https://youtube.com/live/xyz",
  "p_event_date":   "2026-04-15",
  "p_event_time":   "20:00:00",
  "p_livestream":   true,
  "p_video":        false,
  "p_is_recurring": true,
  "p_platforms": [
    { "platform_id": 1, "stream_url": "https://youtube.com/live/xyz" },
    { "platform_id": 2, "stream_url": "https://twitch.tv/handle" }
  ]
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
| `Profile not found, access denied, or profile is not active` | Profile doesn't exist, doesn't belong to `p_user_id`, or `status != 'active'` |
| `Event title is required` | `p_title` is null or empty string |
| `Event link is required` | `p_event_link` is null or empty string |
| `Event date is required` | `p_event_date` is null |
| `Event time is required` | `p_event_time` is null |
| `One or more platform IDs are invalid` | A `platform_id` not found in `platforms` table |
| `Stream URL is required for each platform` | A platform object missing `stream_url` |
| `Something went wrong` | Unhandled exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Null check: p_profile_id, p_user_id
2. Ownership + active check:
   creator_profiles WHERE id = p_profile_id AND user_id = p_user_id AND status = 'active'
3. Required field checks: p_title, p_event_link, p_event_date, p_event_time
4. Platform validation (if p_platforms non-null and non-empty):
   ├── All platform_ids must exist in platforms table (validated as ::bigint)
   └── All platform objects must have a non-empty stream_url
5. INSERT INTO event_mst → returns event_id
6. If p_platforms non-null and non-empty:
   └── For each platform: INSERT INTO event_platforms
       ⚠️ platform_id stored as int4 (cast from bigint on insert)
7. RETURN success with event_id
```

---

## ⚠️ Type Warning — event_platforms.platform_id

`event_platforms.platform_id` is **`int4`** while `platforms.plat_id` is **`int8`**.

The SP validates platform IDs using `::bigint` (to match `plat_id`) and inserts using
`::int4` (to match the column type). This is handled internally — no action required on
the Flutter side.

---

## Business Rules

- An event belongs to a **profile**, not directly to a user
- `p_livestream = true` → event appears in the **live section** of `get_event_list`
  when `event_time <= now() AND event_time >= now() - interval '3 hours'`
- `p_livestream` and `p_video` can both be false (scheduled event, not live)
- `p_platforms` null or `[]` → no `event_platforms` rows — event has no platform links
- `description` is stored as-is (nullable); `get_event_list` uses `coalesce(description, '')` for display

---

## Related

- [`update_event`](update_event.md) — update event details
- [`delete_event`](delete_event.md) — delete event
- [`get_event_list`](get_event_list.md) — read events by date (live/today/future logic)
- [`search_events`](../search/search_events.md) — search events by keyword
- [`event_mst` table](../../database/tables/08_event_mst.md)
- [`event_platforms` table](../../database/tables/09_event_platforms.md)
