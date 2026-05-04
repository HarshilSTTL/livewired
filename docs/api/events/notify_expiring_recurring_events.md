# SP: `notify_expiring_recurring_events`

**Endpoint:** `POST /rpc/notify_expiring_recurring_events`
**Group:** Events
**SQL:** [`functions/events/notify_expiring_recurring_events.md`](../../../functions/events/notify_expiring_recurring_events.md)
**Tables read:** `event_recurring` · `event_mst` · `creator_profiles`
**Tables written:** `notifications` (INSERT) · `event_recurring` (UPDATE `renewal_notified_at`)

---

## Overview

Scans all active recurring events whose `recurring_end_date` falls **within the next 7 days** and sends a renewal reminder notification to the event owner.

Once a notification is sent, `renewal_notified_at` is stamped on the `event_recurring` row — this prevents duplicate notifications if the function is called multiple times. If the owner updates the recurring schedule via `update_event`, `renewal_notified_at` is reset to `NULL` so a new notification can be sent for the updated end date.

**Intended usage:** scheduled daily at a fixed time via **pg_cron** — no parameters required.

```sql
SELECT cron.schedule(
    'notify-expiring-recurring-events',
    '0 9 * * *',
    $$SELECT notify_expiring_recurring_events()$$
);
```

---

## Parameters

None. This function takes no parameters.

---

## Request Example

```json
{}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "3 renewal notification(s) sent"
}
```

> Returns `"0 renewal notification(s) sent"` when no events are expiring within 7 days — this is not an error.

### Error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Notification Sent to Event Owner

| Field | Value |
|-------|-------|
| `title` | `"Recurring Event Ending Soon"` |
| `body` | `"Your recurring event "<event_title>" ends on <date>. Update the schedule to keep it going."` |
| `data.type` | `"recurring_renewal"` |
| `data.event_id` | UUID of the recurring parent event |
| `data.recurring_end_date` | The date the recurring schedule ends |

---

## Idempotency

| Scenario | Behaviour |
|----------|-----------|
| Called again same day after already running | No duplicate — `renewal_notified_at IS NOT NULL` skips those events |
| Owner updates recurring schedule (`update_event`) | `renewal_notified_at` reset to `NULL` → next run will notify again |
| Event deleted before run | `e.is_deleted = false` filter skips it |
| Owner profile deactivated | `cp.status = 'active'` filter skips it |

---

## Logic Flow

```
1. SELECT all event_recurring rows WHERE:
   - recurring_end_date BETWEEN today AND today + 7 days
   - renewal_notified_at IS NULL
   - event_mst.is_deleted = false
   - creator_profiles.status = 'active'
2. For each matching row:
   a. INSERT notification for the event owner
   b. UPDATE event_recurring SET renewal_notified_at = now()
3. Return count of notifications sent
```

---

## pg_cron Setup

Run this once in the Supabase SQL editor to schedule daily execution at 09:00 UTC:

```sql
SELECT cron.schedule(
    'notify-expiring-recurring-events',
    '0 9 * * *',
    $$SELECT notify_expiring_recurring_events()$$
);
```

To verify the job is registered:
```sql
SELECT * FROM cron.job WHERE jobname = 'notify-expiring-recurring-events';
```

To remove the schedule:
```sql
SELECT cron.unschedule('notify-expiring-recurring-events');
```

> `pg_cron` must be enabled in your Supabase project. Go to **Database → Extensions** and enable `pg_cron`.

---

## Related

- [`create_event`](create_event.md) — sets `recurring_end_date` (default: start + 3 months)
- [`update_event`](update_event.md) — resets `renewal_notified_at` when schedule changes
- [`event_recurring` table](../../database/tables/13_event_recurring.md)
