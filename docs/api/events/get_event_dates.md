# SP: `get_event_dates`

**Endpoint:** `POST /rpc/get_event_dates`
**Group:** Events
**SQL:** [`functions/events/get_event_dates.md`](../../../functions/events/get_event_dates.md)
**Tables read:** `event_mst`, `creator_profiles`, `follows`

---

## Overview

Returns all dates within a given month that have at least one event from the profiles
the current user follows. Each date includes an event count.

Used to highlight dots on a calendar view in Flutter.

| Scenario | What happens |
|---|---|
| Month has events from followed profiles | Returns array of `{date, count}` objects |
| Month has no events | Returns `"data": []` — not an error |
| Recurring events | Each occurrence (child row) counts as its own event on its own date |

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | Current user's ID |
| `p_year` | int | ✅ | Year — e.g. `2026` |
| `p_month` | int | ✅ | Month — `1` to `12` |

---

## Request Example

```json
{
  "p_user_id": "178fa2d8-97a4-49e0-aa2c-763f35f36634",
  "p_year":    2026,
  "p_month":   4
}
```

---

## Response

### Success — dates found
```json
{
  "status":  true,
  "message": "Event dates fetched successfully",
  "data": [
    { "date": "2026-04-03", "count": 1 },
    { "date": "2026-04-07", "count": 3 },
    { "date": "2026-04-15", "count": 2 }
  ]
}
```

### Success — no events in that month
```json
{
  "status":  true,
  "message": "Event dates fetched successfully",
  "data": []
}
```

### Error
```json
{
  "status":  false,
  "message": "Month must be between 1 and 12"
}
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `User ID is required` | `p_user_id` is null |
| `Year is required` | `p_year` is null |
| `Month is required` | `p_month` is null |
| `Month must be between 1 and 12` | `p_month` < 1 or > 12 |
| `Something went wrong` | Unhandled exception — `error` field contains detail |

---

## Logic Flow

```
1. Null check: p_user_id, p_year, p_month
2. Validate: p_month between 1 and 12
3. JOIN event_mst → creator_profiles → follows
   WHERE follows.user_id = p_user_id
     AND follows.is_active = true
     AND event_mst.is_deleted = false
     AND event_date falls in p_year / p_month
4. GROUP BY event_date, COUNT(*) per date
5. ORDER BY event_date ASC
6. Return array of {date, count}
```

---

## Notes

- Recurring child rows each have their own `event_date` in `event_mst` — no extra expansion needed, they are counted as individual events on their own dates
- Returns empty array (not error) when no events exist in the month — Flutter can render a blank calendar without error handling
- `date` field is returned as `YYYY-MM-DD` string

---

## Related

- [`get_event_list`](get_event_list.md) — fetch full event details for a specific date
- [`get_following_list`](../follow/get_following_list.md) — list of profiles the user follows
