# `process_event_reminders`

```sql
-- Function: process_event_reminders
-- Group: Notifications
-- Type: Cron job — runs every minute via pg_cron
-- Schedule: * * * * *

CREATE OR REPLACE FUNCTION process_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- ── Insert notifications for due reminders ────────────────────────────────
    INSERT INTO notifications (user_id, title, body, data)
    SELECT
        er.user_id,
        cp.profile_name || ' goes live in ' || er.reminder_minutes || ' min!',
        e.title,
        json_build_object(
            'type',             'reminder',
            'event_id',         e.event_id,
            'profile_id',       cp.id,
            'reminder_minutes', er.reminder_minutes
        )
    FROM event_reminders er
    JOIN event_mst        e  ON e.event_id  = er.event_id
    JOIN creator_profiles cp ON cp.id       = e.profile_id
    WHERE er.is_notified = false
      AND e.is_deleted   = false
      AND cp.status      = 'active'
      AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone
            BETWEEN NOW() + ((er.reminder_minutes - 0.5) * interval '1 minute')
                AND NOW() + ((er.reminder_minutes + 0.5) * interval '1 minute');

    -- ── Mark reminders as notified ────────────────────────────────────────────
    UPDATE event_reminders er
    SET is_notified = true
    FROM event_mst e
    WHERE er.event_id    = e.event_id
      AND er.is_notified = false
      AND e.is_deleted   = false
      AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone
            BETWEEN NOW() + ((er.reminder_minutes - 0.5) * interval '1 minute')
                AND NOW() + ((er.reminder_minutes + 0.5) * interval '1 minute');

END;
$$;
```

> **Note:** `data` column on `notifications` is `jsonb`.
> Do NOT cast `json_build_object(...)::text` — it will fail with
> `column "data" is of type jsonb but expression is of type text`.
> `json_build_object()` → `json` → implicitly cast to `jsonb` ✅
