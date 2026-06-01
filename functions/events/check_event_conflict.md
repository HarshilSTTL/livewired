# `check_event_conflict`

## Overview
Checks if a proposed event time conflicts with existing scheduled events for a profile.

## Endpoint
```
POST /rest/v1/rpc/check_event_conflict
```

## Purpose
Validates event scheduling times to prevent double-booking. Used in date/time picker to show real-time conflict warnings.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_profile_id` | bigint | ✅ Yes | Profile ID to check conflicts for |
| `p_start_time` | timestamp with time zone | ✅ Yes | Event start time (ISO 8601 format) |
| `p_end_time` | timestamp with time zone | ✅ Yes | Event end time (ISO 8601 format) |
| `p_event_id` | bigint | ❌ No | Event ID to exclude when editing |

---

## Response Format

### Success - No Conflict
```json
{
  "status": true,
  "has_conflict": false,
  "message": "No conflicts found."
}
```

### Success - Conflict Found
```json
{
  "status": true,
  "has_conflict": true,
  "message": "You already have an event scheduled at this time.",
  "conflicting_event_id": 123,
  "conflicting_event_name": "Team Meeting",
  "conflicting_event_start": "2026-06-01T14:00:00+00",
  "conflicting_event_end": "2026-06-01T15:00:00+00"
}
```

### Error
```json
{
  "status": false,
  "has_conflict": false,
  "message": "Error checking conflicts",
  "error": "error details"
}
```

---

## Usage Examples

### Creating New Event (No existing event to exclude)
```bash
curl -X POST 'https://your-project.supabase.co/rest/v1/rpc/check_event_conflict' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -d '{
    "p_profile_id": 1,
    "p_start_time": "2026-06-01T14:00:00Z",
    "p_end_time": "2026-06-01T15:00:00Z"
  }'
```

### Editing Existing Event (Exclude current event from check)
```bash
curl -X POST 'https://your-project.supabase.co/rest/v1/rpc/check_event_conflict' \
  -H 'Content-Type: application/json' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -d '{
    "p_profile_id": 1,
    "p_start_time": "2026-06-01T14:00:00Z",
    "p_end_time": "2026-06-01T15:00:00Z",
    "p_event_id": 42
  }'
```

### JavaScript/React Example
```javascript
async function checkEventConflict(profileId, startTime, endTime, eventId = null) {
  const response = await fetch('{{url}}/rest/v1/rpc/check_event_conflict', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer {{ANON_KEY}}'
    },
    body: JSON.stringify({
      p_profile_id: profileId,
      p_start_time: startTime,
      p_end_time: endTime,
      p_event_id: eventId
    })
  });

  return await response.json();
}

// Usage in date picker
const result = await checkEventConflict(
  1, 
  '2026-06-01T14:00:00Z', 
  '2026-06-01T15:00:00Z'
);

if (result.has_conflict) {
  showWarning(result.message); // Shows: "You already have an event scheduled at this time."
}
```

---

## Overlap Detection Logic

An event conflicts if its time range overlaps with any existing event:

```
existing_start < new_end AND existing_end > new_start = CONFLICT
```

### Conflict Examples
| Existing Event | New Event | Overlap? |
|---|---|---|
| 2:00 PM - 3:00 PM | 2:30 PM - 3:30 PM | ✅ YES |
| 2:00 PM - 3:00 PM | 1:30 PM - 2:30 PM | ✅ YES |
| 2:00 PM - 3:00 PM | 3:00 PM - 4:00 PM | ❌ NO |
| 2:00 PM - 3:00 PM | 1:00 PM - 2:00 PM | ❌ NO |
| 2:00 PM - 3:00 PM | 1:30 PM - 3:30 PM | ✅ YES |

---

## Important Notes

✅ **What it does:**
- Checks ALL non-deleted, non-cancelled events for the profile
- Detects any time overlap
- Allows editing same event by excluding it from check
- Returns conflict details for logging

✅ **When to use:**
- When user selects date/time in event creation form
- When user edits event time
- Real-time validation (call on time selection change)

⚠️ **Excludes:**
- Events with status `deleted`
- Events with status `cancelled`
- The current event being edited (if p_event_id provided)

---

## Testing

Test in Supabase SQL Editor:
```sql
-- Test: No conflict
SELECT check_event_conflict(
    1::bigint,
    '2026-06-05T14:00:00Z'::timestamp with time zone,
    '2026-06-05T15:00:00Z'::timestamp with time zone,
    NULL
);

-- Test: With conflict (if you have overlapping events)
SELECT check_event_conflict(
    1::bigint,
    '2026-06-01T14:30:00Z'::timestamp with time zone,
    '2026-06-01T15:30:00Z'::timestamp with time zone,
    NULL
);

-- Test: Editing event (exclude own event)
SELECT check_event_conflict(
    1::bigint,
    '2026-06-01T14:00:00Z'::timestamp with time zone,
    '2026-06-01T15:00:00Z'::timestamp with time zone,
    42::bigint
);
```

---

## Commit History
- **2026-06-01** - Initial creation of check_event_conflict function for event scheduling conflict detection

