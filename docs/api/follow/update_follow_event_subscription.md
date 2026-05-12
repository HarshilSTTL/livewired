# SP: `update_follow_event_subscription`

**Endpoint:** `POST /rpc/update_follow_event_subscription`
**Group:** Follow
**SQL:** [`functions/follow/update_follow_event_subscription.md`](../../../functions/follow/update_follow_event_subscription.md)

---

## Overview

Allows followers to enable/disable and configure **profile-level event subscriptions**. When enabled, the follower receives automatic notifications for **ALL events** created on a profile they follow, at the configured time.

Different from `update_follow_reminder` (event-specific manual reminders).

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_user_id` | uuid | ✅ | The logged-in user |
| `p_profile_id` | uuid | ✅ | The profile to subscribe to |
| `p_event_notification_enabled` | boolean | ✅ | Enable/disable subscription |
| `p_event_notification_minutes` | int | ❌ | Minutes before event: 1-1440, or NULL (default: NULL = at event start) |

---

## Request Examples

### Example 1: Enable subscription — Notify 5 minutes before
```json
{
  "p_user_id":                    "user-uuid",
  "p_profile_id":                 "profile-uuid",
  "p_event_notification_enabled": true,
  "p_event_notification_minutes": 5
}
```

### Example 2: Enable subscription — Notify 10 minutes before
```json
{
  "p_user_id":                    "user-uuid",
  "p_profile_id":                 "profile-uuid",
  "p_event_notification_enabled": true,
  "p_event_notification_minutes": 10
}
```

### Example 3: Enable subscription — Notify exactly at event start
```json
{
  "p_user_id":                    "user-uuid",
  "p_profile_id":                 "profile-uuid",
  "p_event_notification_enabled": true,
  "p_event_notification_minutes": null
}
```

### Example 4: Disable subscription
```json
{
  "p_user_id":                    "user-uuid",
  "p_profile_id":                 "profile-uuid",
  "p_event_notification_enabled": false
}
```

### Example 5: Change minutes (5 → 15)
```json
{
  "p_user_id":                    "user-uuid",
  "p_profile_id":                 "profile-uuid",
  "p_event_notification_enabled": true,
  "p_event_notification_minutes": 15
}
```

---

## Response

### Success — Enabled (5 minutes before)
```json
{
  "status": true,
  "message": "Profile event subscription enabled",
  "data": {
    "profile_id": "profile-uuid",
    "profile_name": "Harshil Gaming",
    "event_notification_enabled": true,
    "event_notification_minutes": 5,
    "notification_type": "5_minutes_before"
  }
}
```

### Success — Enabled (at event start)
```json
{
  "status": true,
  "message": "Profile event subscription enabled",
  "data": {
    "profile_id": "profile-uuid",
    "profile_name": "Harshil Gaming",
    "event_notification_enabled": true,
    "event_notification_minutes": null,
    "notification_type": "at_event_start"
  }
}
```

### Success — Disabled
```json
{
  "status": true,
  "message": "Profile event subscription disabled",
  "data": {
    "profile_id": "profile-uuid",
    "profile_name": "Harshil Gaming",
    "event_notification_enabled": false,
    "event_notification_minutes": null,
    "notification_type": "disabled"
  }
}
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---|---|
| `User ID is required` | `p_user_id` is null |
| `Profile ID is required` | `p_profile_id` is null |
| `Profile not found` | No profile with that ID |
| `You do not follow this profile` | User doesn't have active follow relationship |
| `Event notification minutes must be between 1 and 1440, or NULL (at start)` | Minutes outside valid range (1-1440) |
| `Something went wrong` | Unhandled exception |

---

## Behavioral Notes

**Enable/Disable:**
- `p_event_notification_enabled = true` → subscription active
- `p_event_notification_enabled = false` → subscription disabled; `p_event_notification_minutes` ignored (set to NULL)

**Notification Timing:**
- `p_event_notification_minutes = NULL` → notify exactly at event start time
- `p_event_notification_minutes = 1 to 1440` → notify X minutes before event start
- Range: 1 minute to 24 hours (1440 minutes)

**Applies to All Events:**
- Notifications fire for ALL events on the profile (recurring + non-recurring)
- For recurring series: notification fires once per occurrence

**Persistence:**
- Settings persist across unfollow/re-follow cycles
- If user unfollows, settings stored; if they re-follow same profile, settings restored

**Manual Reminders Win:**
- If user sets a manual reminder (`event_reminders` table) on a specific event
- Profile subscription notification is suppressed for that event (manual takes priority)
- Both systems do NOT fire for same event

**Separate from `update_follow_reminder`:**
- `update_follow_reminder` = event-specific manual reminders (per-event basis)
- `update_follow_event_subscription` = profile-level automatic subscriptions (all events)
- These are two independent systems

---

## UI Integration

### Subscription Settings Screen
When user opens subscription settings for a followed profile:

```
Profile: "Harshil Gaming"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔔 Notify me about new events
   
   ☐ Disabled
   ☑ Enabled
   
   When to notify:
   ○ Exactly at event start
   ○ 5 minutes before
   ✓ 10 minutes before
   ○ 15 minutes before
```

---

## Related

- [`update_follow_reminder`](update_follow_reminder.md) — event-specific manual reminders
- [`follows` table](../../database/tables/10_follows.md)
- [`follow_event_subscription_dispatches` table](../../database/tables/18_follow_event_subscription_dispatches.md)
- [`process_event_reminders` cron](../../functions/notifications/process_event_reminders.md) — processes subscriptions
