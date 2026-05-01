# SP: `get_event_list`

**Endpoint:** `POST /rpc/get_event_list`
**Group:** Events
**Description:** Returns events split into `live` and `today` sections based on date logic. When `p_user_id` is provided, only events from profiles the user follows are returned — used for the dashboard feed. Behavior changes depending on whether the requested date is in the past, today, or the future. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| p_user_id | uuid | No | null | When provided — only events from followed profiles are returned |
| p_date | date | No | CURRENT_DATE | Date to fetch events for — in viewer's local timezone |
| p_timezone | text | No | `'UTC'` | Viewer's IANA timezone — e.g. `'Asia/Kolkata'`, `'America/New_York'`. All dates/times returned in this timezone |
| p_device_ip | text | No | null | Device IP — accepted but not stored |

### Request Example — Dashboard (followed events only)
```json
{
  "p_user_id":  "uuid...",
  "p_date":     "2026-04-02",
  "p_timezone": "Asia/Kolkata"
}
```

### Request Example — All events (no filter)
```json
{
  "p_date":     "2026-04-02",
  "p_timezone": "Asia/Kolkata"
}
```

---

## Date Logic — 3 Branches

### Branch 1: Past Date (`p_date < CURRENT_DATE`)
| Section | Result |
|---------|--------|
| `live` | Always `[]` empty |
| `today` | All events on that date (active creator profiles only) |

### Branch 2: Today (`p_date = CURRENT_DATE`)
| Section | Condition |
|---------|-----------|
| `live` | `livestream = true` AND `event_end_time IS NOT NULL` AND `NOW()` is between start and end times |
| `today` | upcoming events (`event_time > NOW()`) OR started events with no end time (`event_end_time IS NULL`) |

> Events that have an end time and are already ended are hidden from **both** sections.

### Branch 3: Future Date (`p_date > CURRENT_DATE`)
| Section | Result |
|---------|--------|
| `live` | Always `[]` empty |
| `today` | All events scheduled for that date (active creator profiles only) |

### Summary Table

| Scenario | `live` | `today` |
|----------|--------|---------|
| Past date | `[]` | All events of that day |
| Today — started + has end_time + not ended | Shows here | Not shown |
| Today — ended (has end_time and end < now) | Not shown | Not shown |
| Today — started + no end_time | Not shown | Shows here |
| Today — not started yet | Not shown | Shows here |
| Future date | `[]` | All events of that day |

---

## Response

### Success
```json
{
  "status": true,
  "message": "Event list fetched successfully",
  "data": {
    "live": [
      {
        "event_id":     "uuid",
        "profile_id":   "uuid",
        "profile_name": "Harshil Gaming",
        "profile_pic":  "url or null",
        "followers":    150,
        "event_title":  "Valorant Ranked Grind",
        "event_date":   "2026-03-30",
        "time":         "18:00:00",
        "end_time":     "20:00:00",
        "livestream":   true,
        "is_recurring": false,
        "platforms": [
          {
            "platform_id":   1,
            "platform_name": "YouTube",
            "logo_url":      "url or null",
            "streaming_url": "https://youtube.com/live/..."
          }
        ]
      }
    ],
    "today": []
  }
}
```

> Both `live` and `today` always return as arrays (empty `[]` if no results — never `null`).

### Fail — Server error
```json
{
  "status": false,
  "message": "Something went wrong",
  "error": "<sqlerrm>"
}
```

---

## Response Fields

| Field | Source | Notes |
|-------|--------|-------|
| event_id | event_mst.event_id | — |
| profile_id | creator_profiles.id | — |
| profile_name | creator_profiles.profile_name | — |
| profile_pic | creator_profiles.avatar | nullable |
| followers | COUNT from follows WHERE is_active=true | live calculated |
| event_title | event_mst.title | — |
| event_date | converted from event_timezone → p_timezone | viewer's local date |
| time | converted from event_timezone → p_timezone | viewer's local time |
| end_time | converted from event_timezone → p_timezone | nullable — viewer's local time |
| livestream | event_mst.livestream | — |
| is_recurring | event_mst.is_recurring | — |
| platforms | joined from event_platforms + platforms | array, never null |

---

## Notes

- `event_date` and `time` in the response are returned in the **viewer's local timezone** (`p_timezone`)
- Live/upcoming checks use `AT TIME ZONE e.event_timezone` to get the correct UTC moment for comparison with `NOW()`
- Only events from `creator_profiles` with `status = 'active'` are returned
- Events are ordered by `event_time ASC` within each section
- `streaming` array uses `coalesce(..., '[]'::json)` — never null
- `logo_url` in streaming can be null (platforms.logo_url is nullable)
- `p_device_ip` is accepted but has no effect on the query
- `ep.platform_id::bigint` cast required — event_platforms.platform_id is `int4`, platforms.plat_id is `int8`

---

## SQL Reference

See [`functions/events/get_event_list.md`](../../../functions/events/get_event_list.md)
