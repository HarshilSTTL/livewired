# API: `get_profile_reminder`

## Overview

Retrieves the profile-level event notification settings for a profile that a user follows. Tells you whether the user has profile-level notifications (automatic event subscriptions) enabled and at what interval before event start.

---

## Endpoint

```
POST /rpc/get_profile_reminder
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
  "p_profile_id": "{{profile-id}}"
}
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | `uuid` | ✅ | The authenticated user ID |
| `p_profile_id` | `uuid` | ✅ | The creator profile UUID |

---

## Response

### Success (User follows and reminders enabled)

```json
{
    "status": true,
    "data": {
        "has_reminder": true,
        "reminder_minutes": 5
    }
}
```

---

### Success (User follows but reminders disabled)

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

### Error (User doesn't follow this profile)

```json
{
    "status": false,
    "message": "User not followed"
}
```

---

### Error (Missing required parameters)

```json
{
    "status": false,
    "message": "p_user_id and p_profile_id are required"
}
```

---

## Usage Examples

### cURL

```bash
curl -X POST https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc/get_profile_reminder \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "apiKey: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_user_id": "550e8400-e29b-41d4-a716-446655440000",
    "p_profile_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8"
  }'
```

### JavaScript / Fetch

```javascript
const response = await fetch(
  'https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc/get_profile_reminder',
  {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'apiKey': apiKey,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      p_user_id: userId,
      p_profile_id: profileId
    })
  }
);

const result = await response.json();
console.log(result);
```

### Python

```python
import requests

url = "https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc/get_profile_reminder"
headers = {
    "Authorization": f"Bearer {token}",
    "apiKey": api_key,
    "Content-Type": "application/json"
}
payload = {
    "p_user_id": user_id,
    "p_profile_id": profile_id
}

response = requests.post(url, headers=headers, json=payload)
result = response.json()
print(result)
```

---

## Status Codes

| Code | Meaning |
|------|---------|
| `true` | Request successful. User follows the profile. Check `has_reminder` for reminder status. |
| `false` | Request failed. User doesn't follow the profile, or required parameters are missing. |

---

## Related APIs

- [`update_follow_reminder`](../follow/update_follow_reminder.md) — Enable/disable reminders and set interval
- [`follow_creator`](../follow/follow_creator.md) — Start following a creator
- [`unfollow_creator`](../follow/unfollow_creator.md) — Stop following a creator

---

## Notes

- This retrieves **profile-level event notifications** (automatic subscriptions for all events on the profile).
- For manual per-event reminders, use [`get_event_reminder`](../events/get_event_reminder.md).
- Only active follows (`is_active = true`) are checked. Unfollowed profiles return an error.
- When notifications are disabled (`has_reminder: false`), `reminder_minutes` is `null`.
- When notifications are enabled, `reminder_minutes` contains the notification lead time in minutes before event start (NULL means at event start time).
