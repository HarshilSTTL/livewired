# SP: `get_notifications`

**Endpoint:** `POST /rpc/get_notifications`
**Group:** Notifications
**SQL:** [`functions/notifications/get_notifications.md`](../../../functions/notifications/get_notifications.md)
**Tables read:** `notifications`, `creator_profiles`, `event_collaborators` (for collaboration notifications)

---

## Overview

Returns the authenticated user's notification history from the past 2 days, sorted latest first.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | uuid | ✅ | The authenticated user's ID |

---

## Request Example

```json
{
  "p_user_id": "uuid..."
}
```

---

## Response

### Success — Reminder Notification

```json
{
  "status": true,
  "message": "Notifications fetched successfully",
  "data": [
    {
      "id":         "uuid",
      "title":      "Harshil Gaming goes live in 10 min!",
      "body":       "Valorant Ranked Grind",
      "data": {
        "type":             "reminder",
        "event_id":         "uuid",
        "profile_id":       "uuid",
        "reminder_minutes": 10
      },
      "is_read":    false,
      "created_at": "2026-04-09T14:30:00+00:00",
      "profile_id": "ace2c42d-d493-4513-bea5-78858654d5ee",
      "profile_name": "Harshil Gaming",
      "avatar": "base64...",
      "collaborators": null
    }
  ]
}
```

### Success — Collaboration Invite Notification

```json
{
  "status": true,
  "message": "Notifications fetched successfully",
  "data": [
    {
      "id":         "uuid",
      "title":      "You've been invited to collaborate",
      "body":       "Weekly Meetup",
      "data": {
        "type":              "collaborator_invite",
        "event_id":          "uuid",
        "invited_by_profile_id": "uuid"
      },
      "is_read":    false,
      "created_at": "2026-04-09T14:30:00+00:00",
      "profile_id": "ace2c42d-d493-4513-bea5-78858654d5ee",
      "profile_name": "Harshil Gaming",
      "avatar": "base64...",
      "collaborators": [
        {
          "profile_id":   "uuid",
          "profile_name": "Alice",
          "avatar":       "base64...",
          "status":       "accepted"
        },
        {
          "profile_id":   "uuid",
          "profile_name": "Bob",
          "avatar":       "base64...",
          "status":       "pending"
        }
      ]
    }
  ]
}
```

> `data` always returns as an array — `[]` if no notifications in the past 2 days.
> `collaborators` is `null` for non-collaboration notifications; an array of collaborator objects for `type: 'collaborator_invite'`.

### Error
```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Response Fields

| Field | Source | Notes |
|-------|--------|-------|
| id | notifications.id | UUID |
| title | notifications.title | Push notification title |
| body | notifications.body | Push notification body (event title) |
| data | notifications.data | jsonb payload — type, event_id, profile_id, reminder_minutes, invited_by_profile_id, etc. |
| is_read | notifications.is_read | `false` = unread · `true` = read |
| created_at | notifications.created_at | UTC timestamp |
| profile_id | creator_profiles.id | UUID of the related profile (owner of the event or inviter) |
| profile_name | creator_profiles.profile_name | Display name of the related profile |
| avatar | creator_profiles.avatar | Profile picture Base64 (nullable) |
| collaborators | event_collaborators | `null` for non-collaboration notifications; array of collaborator objects for `type: 'collaborator_invite'`. Each collaborator has: `profile_id`, `profile_name`, `avatar`, `status` ('pending' \| 'accepted' \| 'declined'). Sorted by `invited_at`. |

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_user_id is required` | `p_user_id` is null |
| `Something went wrong` | Unhandled DB exception |

---

## Notes

- Only notifications created within the **past 2 days** (`NOW() - INTERVAL '2 days'`) are returned
- **Cleared notifications are excluded** — notifications with `is_cleared = true` do not appear in this list (use [`clear_notifications`](clear_notifications.md) to hide notifications)
- Results are ordered by `created_at DESC` (latest first)
- Returns `[]` (empty array) if the user has no notifications in that window — never `null`
- **Profile context** — each notification includes the related profile's `profile_id`, `profile_name`, and `avatar` for easy identification of which profile the notification is about
- **Collaborators** — for collaboration-related notifications (`data.type = 'collaborator_invite'`), the `collaborators` array includes all active (non-deleted) collaborators on the event with their profile info and current status. For non-collaboration notifications, `collaborators` is `null`.

---

## Related

- [`get_unread_notification_count`](get_unread_notification_count.md) — badge count for unread notifications
- [`mark_notifications_read`](mark_notifications_read.md) — mark all or specific notifications as read
- [`clear_notifications`](clear_notifications.md) — clear (hide) all or specific notifications
- [`process_event_reminders`](../../../functions/notifications/process_event_reminders.md) — cron job that inserts notifications
