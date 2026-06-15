# Event Conflict Check API

## Overview
The `check_event_conflict_v2` endpoint validates whether a proposed event time overlaps with existing scheduled events for a user's profile.

## Endpoint

### v2.0 (Current) ✅
```
POST /rest/v1/rpc/check_event_conflict_v2
```

### v1.0 (Deprecated)
```
POST /rest/v1/rpc/check_event_conflict
```

## Authentication
Required: Bearer token (Supabase anon or authenticated key)

---

## Request

### Headers
```
Content-Type: application/json
Authorization: Bearer YOUR_ANON_KEY
```

### Body — Editing Non-Recurring Event
```json
{
  "p_profile_id": "e84d4d2e-2474-4e30-a031-ca411e4c391e",
  "p_event_date": "2026-06-01",
  "p_event_time": "14:00:00",
  "p_event_end_time": "15:00:00",
  "p_event_id": "abc-123-event-id"
}
```

### Body — Editing Recurring Event Occurrence
```json
{
  "p_profile_id": "e84d4d2e-2474-4e30-a031-ca411e4c391e",
  "p_event_date": "2026-06-01",
  "p_event_time": "14:00:00",
  "p_event_end_time": "15:00:00",
  "p_event_id": "abc-123-mon-occurrence",
  "p_parent_event_id": "abc-123-parent"
}
```

### Body — Creating New Event (No exclusion)
```json
{
  "p_profile_id": "e84d4d2e-2474-4e30-a031-ca411e4c391e",
  "p_event_date": "2026-06-01",
  "p_event_time": "14:00:00",
  "p_event_end_time": "15:00:00"
}
```

### Parameters

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `p_profile_id` | uuid | Yes | User's profile ID |
| `p_event_date` | date | Yes | Event date (YYYY-MM-DD) |
| `p_event_time` | time | Yes | Event start time (HH:MM:SS) |
| `p_event_end_time` | time | No | Event end time (HH:MM:SS). If omitted, treats start time as point-in-time |
| `p_event_id` | uuid | No | Event ID being edited — exclude this specific occurrence from conflict check |
| `p_parent_event_id` | uuid | No | **For recurring events only** — Parent series ID. Exclude entire recurring series (all occurrences) from conflict check. Use when editing any occurrence of a recurring event |

---

## Response

### 200 OK - No Conflict
```json
{
  "status": true,
  "has_conflict": false,
  "message": "No conflicts found."
}
```

### 200 OK - No End Time Provided (Point-In-Time Check)
Treats start time as point-in-time and checks if it falls within existing events:

**Example 1: Conflict detected (start time falls within existing event)**
```json
{
  "status": true,
  "has_conflict": true,
  "message": "You already have an event scheduled at this time.",
  "conflicting_event_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "conflicting_event_title": "Team Meeting",
  "conflicting_event_date": "2026-06-01",
  "conflicting_event_time": "13:00:00",
  "conflicting_event_end_time": "18:00:00"
}
```

**Example 2: No conflict (start time outside existing event duration)**
```json
{
  "status": true,
  "has_conflict": false,
  "message": "No conflicts found."
}
```

### 200 OK - Conflict Detected
```json
{
  "status": true,
  "has_conflict": true,
  "message": "You already have an event scheduled at this time.",
  "conflicting_event_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "conflicting_event_title": "Team Meeting",
  "conflicting_event_date": "2026-06-01",
  "conflicting_event_time": "14:00:00",
  "conflicting_event_end_time": "15:00:00"
}
```

### Error Response
```json
{
  "status": false,
  "has_conflict": false,
  "message": "Error checking conflicts",
  "error": "operator does not exist: bigint = uuid"
}
```

---

## Use Cases

### 1. Creating a New Event
When user selects a time for a new event, check for conflicts:

```javascript
const response = await fetch('/rest/v1/rpc/check_event_conflict', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer token'
  },
  body: JSON.stringify({
    p_profile_id: 'e84d4d2e-2474-4e30-a031-ca411e4c391e',
    p_event_date: '2026-06-01',
    p_event_time: '14:00:00',
    p_event_end_time: '15:00:00'
  })
});

const result = await response.json();
if (result.has_conflict) {
  // Show warning in date picker
  showWarning('You already have an event scheduled at this time.');
}
```

### 2. Editing an Existing Event
When editing event time, exclude the current event from conflict check:

```javascript
const response = await fetch('/rest/v1/rpc/check_event_conflict', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer token'
  },
  body: JSON.stringify({
    p_profile_id: 'e84d4d2e-2474-4e30-a031-ca411e4c391e',
    p_event_date: '2026-06-01',
    p_event_time: '14:30:00',
    p_event_end_time: '15:30:00',
    p_event_id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'  // Exclude this event from check
  })
});

const result = await response.json();
if (result.has_conflict) {
  // Show warning
}
```

### 3. Request Without End Time (Point-In-Time Check)
When end time is not provided, checks if start time conflicts with any existing event:

```javascript
const response = await fetch('/rest/v1/rpc/check_event_conflict', {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer token'
  },
  body: JSON.stringify({
    p_profile_id: 'e84d4d2e-2474-4e30-a031-ca411e4c391e',
    p_event_date: '2026-06-01',
    p_event_time: '14:00:00'
    // p_event_end_time: omitted (treats 14:00:00 as point-in-time)
  })
});

// If existing event is 13:00:00 - 18:00:00:
// Response: { status: true, has_conflict: true, message: "You already have an event...", ... }

// If no event at 14:00:00:
// Response: { status: true, has_conflict: false, message: "No conflicts found." }
```

### 4. Real-Time Validation in Date Picker
Validate as user selects times (only checks if end time is provided):

```javascript
// On start/end time change
async function validateEventTimes(startTime, endTime) {
  // Only check if both times provided
  if (!startTime || !endTime) return;
  
  const result = await fetch('/rest/v1/rpc/check_event_conflict', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${sessionToken}`
    },
    body: JSON.stringify({
      p_profile_id: currentProfileId,
      p_event_date: eventDate,
      p_event_time: startTime,
      p_event_end_time: endTime  // Required for conflict check
    })
  }).then(r => r.json());
  
  if (result.has_conflict) {
    showConflictWarning(result.message);
    document.getElementById('conflict-warning').style.display = 'block';
  } else {
    document.getElementById('conflict-warning').style.display = 'none';
  }
}
```

---

## Conflict Detection Rules

An event conflicts if:
```
existing_event.start < new_event.end AND existing_event.end > new_event.start
```

**Example scenarios:**
| Existing | New | Result |
|----------|-----|--------|
| 2:00 - 3:00 PM | 2:30 - 3:30 PM | ❌ CONFLICT |
| 2:00 - 3:00 PM | 1:30 - 2:30 PM | ❌ CONFLICT |
| 2:00 - 3:00 PM | 3:00 - 4:00 PM | ✅ OK |
| 2:00 - 3:00 PM | 1:00 - 2:00 PM | ✅ OK |

---

## Excluded Events

The function automatically excludes:
- Events with `status = 'deleted'`
- Events with `status = 'cancelled'`
- The event being edited (if `p_event_id` provided)

---

## Error Handling

| Error | Cause | Solution |
|-------|-------|----------|
| `Profile ID is required` | p_profile_id is null | Ensure profile ID is provided |
| `Start time and end time are required` | Missing time parameters | Provide both start and end times |
| `Start time must be before end time` | start_time >= end_time | Validate time order |
| `Could not choose the best candidate function` | Multiple function overloads | Ensure parameters match uuid types exactly |

---

## Frontend Integration Example

```javascript
const EventDatePicker = () => {
  const [showWarning, setShowWarning] = useState(false);
  const [warningMessage, setWarningMessage] = useState('');

  const handleTimeChange = async (eventDate, eventTime, eventEndTime) => {
    // Call conflict check API
    const response = await fetch('/rest/v1/rpc/check_event_conflict', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${sessionToken}`
      },
      body: JSON.stringify({
        p_profile_id: currentProfileId,
        p_event_date: eventDate,
        p_event_time: eventTime,
        p_event_end_time: eventEndTime
      })
    });

    const data = await response.json();

    if (data.has_conflict) {
      setShowWarning(true);
      setWarningMessage(data.message);
    } else {
      setShowWarning(false);
    }
  };

  return (
    <div className="date-picker">
      <input 
        type="datetime-local" 
        onChange={(e) => handleTimeChange(e.target.value, endTime)}
      />
      {showWarning && (
        <div className="warning-message" style={{ color: 'red' }}>
          ⚠️ {warningMessage}
        </div>
      )}
    </div>
  );
};
```

---

## Performance Notes

- ✅ Function indexes on (profile_id, status, start_time, end_time) for optimal performance
- ✅ Returns immediately with first conflict (no need to scan all events)
- ✅ Suitable for real-time validation in date picker
- ✅ Debounce API calls (300ms) to reduce database load

---

## Version History
- **v1.0** (2026-06-01) - Initial release for event conflict detection

