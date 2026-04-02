# SP: `update_event`

**Endpoint:** `POST /rpc/update_event`
**Group:** Events
**SQL:** [`functions/events/update_event.md`](../../../functions/events/update_event.md)
**Tables written:** `event_mst` · `event_platforms`

---

## Overview

Updates a single event. All fields except `p_event_id` and `p_user_id` are optional — only passed (non-null) fields are applied (COALESCE pattern). Ownership is verified before any changes are made.

For platforms, three behaviours are supported based on what `p_platforms` is passed as:
- `null` → platforms are not touched
- `[]` → all platforms are cleared
- `[{...}]` → existing platforms are replaced with the new list

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to update |
| `p_user_id` | uuid | ✅ | Must own the profile that created this event |
| `p_title` | text | ❌ | New title |
| `p_description` | text | ❌ | New description |
| `p_event_date` | date | ❌ | New date (YYYY-MM-DD) |
| `p_event_time` | time | ❌ | New time (HH:MM:SS) |
| `p_livestream` | boolean | ❌ | Toggle livestream flag |
| `p_video` | boolean | ❌ | Toggle video flag |
| `p_platforms` | jsonb | ❌ | Platform list — `null` = no change · `[]` = clear · `[{...}]` = replace |

### `p_platforms` object shape

```json
{
  "platform_id": 1,
  "stream_url":  "https://youtube.com/live/abc"
}
```

---

## Request Examples

### Update title and date only
```json
{
  "p_event_id":   "uuid...",
  "p_user_id":    "uuid...",
  "p_title":      "Metroid Monday — Special Edition",
  "p_event_date": "2026-04-13"
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

### Access Denied / Not Found
```json
{ "status": false, "message": "Event not found or access denied" }
```

### Validation Error
```json
{ "status": false, "message": "One or more platform IDs are invalid" }
```
```json
{ "status": false, "message": "Stream URL is required for each platform" }
```

### Error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Response Field Notes

| Field | Notes |
|-------|-------|
| `p_platforms = null` | Existing platforms are untouched |
| `p_platforms = []` | All platform links for this event are deleted |
| `p_platforms = [{...}]` | DELETE + INSERT — full replacement, not a merge |
| COALESCE fields | Any field passed as `null` (or omitted) retains its current DB value |

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id and p_user_id are required` | Either required param is null |
| `Event not found or access denied` | No matching event, or event belongs to a different user |
| `One or more platform IDs are invalid` | A `platform_id` in `p_platforms` does not exist in `platforms` table |
| `Stream URL is required for each platform` | A platform object is missing `stream_url` or it is empty |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null check: p_event_id, p_user_id
2. Ownership check:
   JOIN event_mst + creator_profiles
   WHERE event_id = p_event_id AND user_id = p_user_id AND status = 'active'
3. Validate p_platforms (if not null and not empty):
   - All platform_id values must exist in platforms table
   - All objects must have a non-empty stream_url
4. UPDATE event_mst with COALESCE for all optional fields
5. If p_platforms IS NOT NULL:
   - DELETE FROM event_platforms WHERE event_id = p_event_id
   - INSERT new rows if p_platforms is non-empty
6. Return success
```

---

## Related

- [`get_event_by_id`](get_event_by_id.md) — fetch current event state before editing
- [`create_event`](create_event.md) — original creation
- [`delete_event`](delete_event.md) — remove this event
