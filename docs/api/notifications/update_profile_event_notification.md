# SP: `update_profile_event_notification`

**Endpoint:** `POST /rpc/update_profile_event_notification`
**Group:** Notifications
**SQL:** [`functions/notifications/update_profile_event_notification.md`](../../../functions/notifications/update_profile_event_notification.md)
**Tables written:** `profile_event_notifications` (INSERT / UPDATE)

---

## Overview

Allows a profile owner to configure global event notifications for their profile. When enabled, the profile owner receives notifications for ANY event created on that profile, based on their configured notification type and timing.

Notifications can fire:
- **`before_event`** — X minutes before the event starts (configurable 1–1440 minutes)
- **`on_event_start`** — when the event actually starts
- **`both`** — both before AND at start time (separate notifications)

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `p_user_id` | uuid | ✅ | The profile owner (must match `creator_profiles.user_id`) |
| `p_profile_id` | uuid | ✅ | The profile to configure notifications for |
| `p_notification_enabled` | boolean | ✅ | `true` = enable notifications · `false` = disable |
| `p_notification_type` | text | ❌ | One of: `before_event` · `on_event_start` · `both`. Defaults to `'before_event'` |
| `p_reminder_minutes` | int | ❌ | 1–1440 (minutes before event). Only used for `before_event` or `both` types. If omitted, defaults to 10. |

---

## Request Examples

### Enable notifications 5 minutes before any event

```json
{
  "p_user_id":              "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_profile_id":           "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_notification_enabled": true,
  "p_notification_type":    "before_event",
  "p_reminder_minutes":     5
}
```

### Enable notifications when events start

```json
{
  "p_user_id":              "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_profile_id":           "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_notification_enabled": true,
  "p_notification_type":    "on_event_start"
}
```

### Enable notifications both before and at event start

```json
{
  "p_user_id":              "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_profile_id":           "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_notification_enabled": true,
  "p_notification_type":    "both",
  "p_reminder_minutes":     15
}
```

### Disable profile event notifications

```json
{
  "p_user_id":              "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_profile_id":           "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_notification_enabled": false
}
```

---

## Response

### Success — Enabled

```json
{
  "status":  true,
  "message": "Profile event notifications enabled",
  "data": {
    "profile_id":             "ace2c42d-d493-4513-bea5-78858654d5ee",
    "notification_enabled":   true,
    "notification_type":      "before_event",
    "reminder_minutes":       5
  }
}
```

### Success — Disabled

```json
{
  "status":  true,
  "message": "Profile event notifications disabled",
  "data": {
    "profile_id":             "ace2c42d-d493-4513-bea5-78858654d5ee",
    "notification_enabled":   false,
    "notification_type":      "before_event",
    "reminder_minutes":       10
  }
}
```

### Error

```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id and p_profile_id are required` | Either UUID is null |
| `p_notification_enabled is required` | Boolean flag missing |
| `p_notification_type must be one of: before_event, on_event_start, both` | Invalid type passed |
| `p_reminder_minutes must be between 1 and 1440` | Value outside range (only validated for before_event/both types) |
| `Profile not found` | Profile doesn't exist |
| `You do not own this profile` | Caller is not the profile owner |
| `Something went wrong` | Unhandled DB exception |

---

## Notification Payload

When a profile event notification fires (via the `process_event_reminders` cron), the inserted `notifications.data` looks like:

**Before event:**
```json
{
  "type":             "profile_event",
  "event_id":         "<the event ID>",
  "profile_id":       "<the profile ID>",
  "reminder_minutes": 5,
  "fired_at":         "before_event"
}
```

**At event start:**
```json
{
  "type":             "profile_event",
  "event_id":         "<the event ID>",
  "profile_id":       "<the profile ID>",
  "fired_at":         "on_event_start"
}
```

The title is `"<profile_name> event starting: <event_title>"`; the body is the full event description or title.

---

## Behavioural Notes

- **Profile ownership** — only the profile owner (user_id on creator_profiles) can configure notifications for that profile
- **One setting per profile** — each profile owner has one notification setting per profile they own (even if they own multiple profiles)
- **Applies to all events** — the setting applies to every event created on that profile, past and future (only active/non-deleted events)
- **Independent from follower reminders** — this is separate from per-follower auto-reminders. Profile owners get these notifications regardless of follow status.
- **Recurring series** — each child occurrence is its own row in `event_mst`, so the same profile setting fires once per occurrence
- **Disable/re-enable** — disabling (`notification_enabled = false`) preserves your settings (`notification_type`, `reminder_minutes`) so they're restored if you re-enable later

---

## Logic Flow

```
1. Null check: p_user_id, p_profile_id, p_notification_enabled
2. Validate p_notification_type ∈ ['before_event', 'on_event_start', 'both']
3. If type includes 'before_event': range-check p_reminder_minutes ∈ [1, 1440]
4. Locate profile by p_profile_id; fetch owner (creator_profiles.user_id)
5. If not found → error "Profile not found"
6. If caller ≠ owner → error "You do not own this profile"
7. v_final_minutes = COALESCE(p_reminder_minutes, 10)
8. INSERT/UPDATE profile_event_notifications with settings (ON CONFLICT)
9. Return { status: true, message, data: { profile_id, notification_enabled, notification_type, reminder_minutes } }
```

---

## Related

- [`process_event_reminders`](../../../functions/notifications/process_event_reminders.md) — cron job that fires profile event notifications
- [`update_follow_reminder`](../follow/update_follow_reminder.md) — per-follower auto-reminders (different from this profile-owner system)
- [`profile_event_notifications` table](../../database/tables/17_profile_event_notifications.md)
- [`creator_profiles` table](../../database/tables/05_creator_profiles.md)
