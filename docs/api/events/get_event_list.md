# SP: `get_event_list`

**Endpoint:** `POST /rpc/get_event_list`
**Group:** Events
**Description:** Returns events split into `live` and `today` sections based on date logic. Behavior changes depending on whether the requested date is in the past, today, or the future. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| p_date | date | No | CURRENT_DATE | Date to fetch events for |
| p_device_ip | text | No | null | Device IP — accepted but not stored |

### Request Example
```json
{
  "p_date": "2026-03-27",
  "p_device_ip": "197.65.65.23"
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
| `live` | `livestream = true` AND `event_time <= current_time` AND `event_time >= (current_time - 3 hours)` |
| `today` | `event_time > current_time` (not yet started) |

> ⚠️ **Terminated events** (started > 3 hours ago) are hidden from **both** sections.

### Branch 3: Future Date (`p_date > CURRENT_DATE`)
| Section | Result |
|---------|--------|
| `live` | Always `[]` empty |
| `today` | All events scheduled for that date (active creator profiles only) |

### Summary Table

| Scenario | `live` | `today` |
|----------|--------|---------|
| Past date | `[]` | All events of that day |
| Today — started, within 3h | Shows here | Not shown |
| Today — started, > 3h ago | Not shown (terminated) | Not shown |
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
        "event_id": "uuid",
        "profile_name": "Harshil Gaming",
        "profile_pic": "url or null",
        "username": "harshil_gaming",
        "followers": 150,
        "event_title": "Valorant Ranked Grind",
        "event_date": "2026-03-30",
        "time": "18:00:00",
        "livestream": true,
        "is_recurring": false,
        "streaming": [
          {
            "platform_id": 1,
            "platform_name": "YouTube",
            "logo_url": "url or null",
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
| profile_name | creator_profiles.profile_name | — |
| profile_pic | creator_profiles.avatar | nullable |
| username | creator_profiles.username | — |
| followers | COUNT from follows WHERE is_active=true | live calculated |
| event_title | event_mst.title | — |
| event_date | event_mst.event_date | — |
| time | event_mst.event_time | — |
| livestream | event_mst.livestream | — |
| is_recurring | event_mst.is_recurring | — |
| streaming | joined from event_platforms + platforms | array, never null |

---

## Notes

- Only events from `creator_profiles` with `status = 'active'` are returned
- Events are ordered by `event_time ASC` within each section
- `streaming` array uses `coalesce(..., '[]'::json)` — never null
- `logo_url` in streaming can be null (platforms.logo_url is nullable)
- `p_device_ip` is accepted but has no effect on the query
- `ep.platform_id::bigint` cast required — event_platforms.platform_id is `int4`, platforms.plat_id is `int8`

---

## SQL Reference

See [`functions/events/get_event_list.md`](../../../functions/events/get_event_list.md)
