# API: `get_event_reminder`

## Overview

Retrieves the reminder configuration for a specific event that a user has set. Tells you whether the user has a reminder for this event and at what interval.

---

## Endpoint

```
POST /rpc/get_event_reminder
```

---

## Request

### Headers
```
Authorization: Bearer {{token}}
apiKey: {{apiKey}}
Content-Type: application/json
```

### Body

```json
{
  "p_user_id": "{{user-id}}",
  "p_event_id": "{{event-id}}"
}
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | `uuid` | ✅ | The authenticated user ID |
| `p_event_id` | `uuid` | ✅ | The event UUID |

---

## Response

### Success (Reminder exists)

```json
{
    "status": true,
    "data": {
        "has_reminder": true,
        "reminder_minutes": 15
    }
}
```

---

### Success (No reminder set)

```json
{
    "status": true,
    "data": {
        "has_reminder": false,
        "reminder_minutes": null
    }
}
```

---

### Error (Missing required parameters)

```json
{
    "status": false,
    "message": "p_user_id and p_event_id are required"
}
```

---

## Usage Examples

### cURL

```bash
curl -X POST https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc/get_event_reminder \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "apiKey: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_user_id": "550e8400-e29b-41d4-a716-446655440000",
    "p_event_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
  }'
```

### JavaScript / Fetch

```javascript
const response = await fetch(
  'https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc/get_event_reminder',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'apiKey': apiKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      p_user_id: userId,
      p_event_id: eventId
    })
  }
);

const result = await response.json();
console.log(result);
```

### Python

```python
import requests

url = "https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc/get_event_reminder"
headers = {
    "Authorization": f"Bearer {token}",
    "apiKey": api_key,
    "Content-Type": "application/json"
}
payload = {
    "p_user_id": user_id,
    "p_event_id": event_id
}

response = requests.post(url, headers=headers, json=payload)
result = response.json()
print(result)
```

---

## Status Codes

| Code | Meaning |
|------|---------|
| `true` | Request successful. Reminder status retrieved. |
| `false` | Request failed. Required parameters are missing or invalid. |

---

## Related APIs

- [`update_follow_reminder`](../follow/update_follow_reminder.md) — Set reminders for all events on a profile
- [`get_profile_reminder`](../follow/get_profile_reminder.md) — Get profile-level reminder status
- [`get_event_by_id`](../events/get_event_by_id.md) — Get event details
- [`get_event_list`](../events/get_event_list.md) — List user's followed events

---

## Notes

- Only active reminders (`is_deleted = false`) are checked.
- If no reminder exists for this event, returns `has_reminder: false` with `reminder_minutes: null`.
- When a reminder exists, `reminder_minutes` is the notification lead time (1–1440 minutes before event start).
- Does not validate if the event exists — simply returns "no reminder" if none is found.
