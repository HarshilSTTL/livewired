# SP: `update_follow_reminder`

**Endpoint:** `POST /rpc/update_follow_reminder`
**Group:** Follow
**SQL:** [`functions/follow/update_follow_reminder.md`](../../../functions/follow/update_follow_reminder.md)
**Tables written:** `follows` (UPDATE)

---

## Overview

YouTube-style bell icon — lets a follower opt in to automatic reminders for **every event** on a profile they follow, and choose how many minutes before each event to be notified. Applies to one-off events and to **every occurrence of a recurring series** (each child occurrence is a separate row in `event_mst`, so the same per-follower setting covers all of them).

The follower must have an active follow row (`is_active = true`) for the target profile. Settings persist across unfollow/re-follow cycles.

Two reminder sources coexist:
- **Manual** ([`event_reminders`](../../database/tables/14_event_reminders.md)) — per-(user, event), set explicitly.
- **Follow-level** (this SP) — per-(user, profile), automatic.

If both apply to the same event, the **manual reminder takes precedence** and the follow-level reminder is suppressed for that event.

---

## Parameters

| Param | Type | Required | Notes |
|-------|------|----------|-------|
| `p_user_id` | uuid | ✅ | The follower |
| `p_profile_id` | uuid | ✅ | The profile to enable/disable reminders for |
| `p_reminder_enabled` | boolean | ✅ | `true` = bell on (auto-notify) · `false` = bell off |
| `p_reminder_minutes` | int | ❌ | 1–1440 (minutes before event). If omitted, keeps the existing stored value (default `10`). |

---

## Request Examples

### Enable reminders, 5 min before each event

```json
{
  "p_user_id":          "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_profile_id":       "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_reminder_enabled": true,
  "p_reminder_minutes": 5
}
```

### Enable reminders, keep previously-set timing

```json
{
  "p_user_id":          "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_profile_id":       "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_reminder_enabled": true
}
```

### Disable reminders (turn bell off)

```json
{
  "p_user_id":          "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_profile_id":       "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_reminder_enabled": false
}
```

---

## Response

### Success — enabled

```json
{
  "status":  true,
  "message": "Reminders enabled for this profile",
  "data": {
    "reminder_enabled": true,
    "reminder_minutes": 5
  }
}
```

### Success — disabled

```json
{
  "status":  true,
  "message": "Reminders disabled for this profile",
  "data": {
    "reminder_enabled": false,
    "reminder_minutes": 10
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
| `p_reminder_enabled is required` | Boolean flag missing (cannot be inferred) |
| `p_reminder_minutes must be between 1 and 1440` | Value outside the 1-minute to 24-hour range |
| `You must follow this profile before setting a reminder` | No active follow row for `(p_user_id, p_profile_id)` |
| `Something went wrong` | Unhandled DB exception (see `error` field for SQLERRM) |

---

## Notification payload

When a follow-level reminder fires (via the `process_event_reminders` cron), the inserted `notifications.data` looks like:

```json
{
  "type":             "follow_reminder",
  "event_id":         "<the event being reminded about>",
  "profile_id":       "<the profile being followed>",
  "reminder_minutes": 5
}
```

`type = 'follow_reminder'` distinguishes this from a manual reminder (`type = 'reminder'`). The title is `"<profile_name> goes live in N min!"`; the body is the event's `title`.

---

## Behavioural Notes

- **Recurring series** — each child occurrence is its own row in `event_mst`. The cron iterates over events on the profile, so the follower receives one reminder per occurrence (Mondays for 3 months → 13 reminders). No separate recurring-reminder configuration is needed.
- **Manual override** — if the follower has a manual `event_reminders` row for a given event, the follow-level reminder for that event is suppressed (manual wins). Either reminder fires once.
- **Exactly-once delivery** — the cron uses [`follow_reminder_dispatches`](../../database/tables/16_follow_reminder_dispatches.md) with `ON CONFLICT (user_id, event_id) DO NOTHING` to guarantee no duplicate notifications, even if the cron runs twice in the same minute.
- **Unfollow** — flips `is_active = false`. The cron skips inactive follows. Settings (`reminder_enabled`, `reminder_minutes`) are preserved on the row so re-following restores the previous choice.
- **Self-follow guard** — `follow_creator` prevents following your own profile. The cron has a defensive `cp.user_id <> f.user_id` filter in case this is ever bypassed.

---

## Logic Flow

```
1. Null check: p_user_id, p_profile_id, p_reminder_enabled
2. Range check: p_reminder_minutes ∈ [1, 1440] (only when caller passed a value)
3. Locate active follow row for (p_user_id, p_profile_id)
   - Not found → error "You must follow this profile before setting a reminder"
4. v_final_minutes = COALESCE(p_reminder_minutes, existing.reminder_minutes)
5. UPDATE follows SET reminder_enabled = p_reminder_enabled, reminder_minutes = v_final_minutes
6. Return { status, message, data: { reminder_enabled, reminder_minutes } }
```

---

## Related

- [`follow_creator`](follow_creator.md) — create the follow relationship (prerequisite)
- [`unfollow_creator`](unfollow_creator.md) — flips `is_active = false` (preserves reminder settings)
- [`process_event_reminders`](../events/process_event_reminders.md) — cron that fires the actual notifications
- [`follows` table](../../database/tables/10_follows.md)
- [`follow_reminder_dispatches` table](../../database/tables/16_follow_reminder_dispatches.md)
- [`event_reminders` table](../../database/tables/14_event_reminders.md)
