# `process_event_reminders`

```sql
-- Function: process_event_reminders
-- Group: Notifications
-- Type: Cron job — runs every minute via pg_cron
-- Schedule: * * * * *
-- Tables: profile_event_notifications (SELECT), event_reminders (SELECT, UPDATE),
--         follows (SELECT), follow_reminder_dispatches (INSERT),
--         follow_event_subscription_dispatches (INSERT), notifications (INSERT)
--
-- Three reminder sources:
--   1. event_reminders   — manual, per-(user, event), set explicitly by the follower
--   2. follows.reminder_enabled   — event-specific follow-level reminders (YouTube-style bell-icon)
--   3. follows.event_notification_enabled — profile-level event subscriptions (notify on new events)
--
-- Precedence: Manual > Follow-level event subscriptions > Profile subscriptions
-- Manual reminders suppress both follow-level reminders AND profile subscriptions for same event.

CREATE OR REPLACE FUNCTION process_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- ══════════════════════════════════════════════════════════════════════════
    -- 1. MANUAL reminders — from event_reminders
    -- ══════════════════════════════════════════════════════════════════════════

    -- ── Insert notifications for due manual reminders ────────────────────────
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

    -- ── Mark manual reminders as notified ────────────────────────────────────
    UPDATE event_reminders er
    SET is_notified = true
    FROM event_mst e
    WHERE er.event_id    = e.event_id
      AND er.is_notified = false
      AND e.is_deleted   = false
      AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone
            BETWEEN NOW() + ((er.reminder_minutes - 0.5) * interval '1 minute')
                AND NOW() + ((er.reminder_minutes + 0.5) * interval '1 minute');

    -- ══════════════════════════════════════════════════════════════════════════
    -- 2. FOLLOW-LEVEL reminders — from follows.reminder_enabled
    -- ══════════════════════════════════════════════════════════════════════════
    -- Exactly-once delivery: INSERT into follow_reminder_dispatches with
    -- ON CONFLICT DO NOTHING. Only rows that actually land produce a
    -- notification. Manual event_reminders rows suppress the follow-level
    -- reminder for that event (manual takes precedence).
    -- Recurring children are individual event_mst rows, so each occurrence
    -- gets its own dispatch record and fires at its own due time.

    WITH dispatched AS (
        INSERT INTO follow_reminder_dispatches (user_id, event_id, notified_at)
        SELECT
            f.user_id,
            e.event_id,
            now()
        FROM follows f
        JOIN event_mst        e  ON e.profile_id = f.profile_id
        JOIN creator_profiles cp ON cp.id        = e.profile_id
        WHERE f.is_active        = true
          AND f.reminder_enabled = true
          AND e.is_deleted       = false
          AND cp.status          = 'active'
          AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone
                BETWEEN NOW() + ((f.reminder_minutes - 0.5) * interval '1 minute')
                    AND NOW() + ((f.reminder_minutes + 0.5) * interval '1 minute')
          -- Manual reminder suppresses follow-level reminder for that event
          AND NOT EXISTS (
              SELECT 1 FROM event_reminders er
              WHERE er.user_id  = f.user_id
                AND er.event_id = e.event_id
          )
          -- Defensive: a follower cannot be the profile owner, but in case the
          -- self-follow guard is ever bypassed, don't notify them about their own event.
          AND cp.user_id <> f.user_id
        ON CONFLICT (user_id, event_id) DO NOTHING
        RETURNING user_id, event_id
    )
    INSERT INTO notifications (user_id, title, body, data)
    SELECT
        d.user_id,
        cp.profile_name || ' goes live in ' || f.reminder_minutes || ' min!',
        e.title,
        json_build_object(
            'type',             'follow_reminder',
            'event_id',         e.event_id,
            'profile_id',       cp.id,
            'reminder_minutes', f.reminder_minutes
        )
    FROM dispatched d
    JOIN event_mst        e  ON e.event_id  = d.event_id
    JOIN creator_profiles cp ON cp.id       = e.profile_id
    JOIN follows          f  ON f.user_id   = d.user_id
                            AND f.profile_id = e.profile_id;

    -- ══════════════════════════════════════════════════════════════════════════
    -- 3. PROFILE-LEVEL event subscriptions — from follows.event_notification_enabled
    -- ══════════════════════════════════════════════════════════════════════════
    -- Followers subscribed to profile-level events get notifications when ANY event
    -- starts on the profile, at the configured time (before event or exactly at start).
    -- Exactly-once delivery: INSERT into follow_event_subscription_dispatches with
    -- ON CONFLICT DO NOTHING. Manual event_reminders rows suppress subscriptions.
    -- Recurring children are individual event_mst rows, so each occurrence fires separately.

    WITH dispatched_subscriptions AS (
        INSERT INTO follow_event_subscription_dispatches (user_id, event_id, notified_at)
        SELECT
            f.user_id,
            e.event_id,
            now()
        FROM follows f
        JOIN event_mst        e  ON e.profile_id = f.profile_id
        JOIN creator_profiles cp ON cp.id        = e.profile_id
        WHERE f.is_active                    = true
          AND f.event_notification_enabled   = true
          AND e.is_deleted                   = false
          AND cp.status                      = 'active'
          -- Suppress subscriptions if manual reminder exists for this event
          AND NOT EXISTS (
              SELECT 1 FROM event_reminders er
              WHERE er.user_id  = f.user_id
                AND er.event_id = e.event_id
          )
          -- Defensive: don't notify follower about their own profile's events
          AND cp.user_id <> f.user_id
          -- Trigger time calculation:
          -- If event_notification_minutes IS NULL → fire exactly at event start time
          -- If event_notification_minutes = 5/10/15 → fire X minutes before
          AND (
              -- Case A: Notify at event start (event_notification_minutes = NULL)
              (f.event_notification_minutes IS NULL
               AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone
                   BETWEEN NOW() - interval '0.5 minute'
                       AND NOW() + interval '0.5 minute'
              )
              OR
              -- Case B: Notify X minutes before event start
              (f.event_notification_minutes IS NOT NULL
               AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone
                   BETWEEN NOW() + ((f.event_notification_minutes - 0.5) * interval '1 minute')
                       AND NOW() + ((f.event_notification_minutes + 0.5) * interval '1 minute')
              )
          )
        ON CONFLICT (user_id, event_id) DO NOTHING
        RETURNING user_id, event_id
    )
    INSERT INTO notifications (user_id, title, body, data)
    SELECT
        ds.user_id,
        cp.profile_name || ': ' || e.title,
        e.title,
        json_build_object(
            'type',                       'follow_event_subscription',
            'event_id',                   e.event_id,
            'profile_id',                 cp.id,
            'notification_minutes',       f.event_notification_minutes,
            'fired_at',                   CASE
                WHEN f.event_notification_minutes IS NULL THEN 'at_event_start'
                ELSE f.event_notification_minutes || '_minutes_before'
            END
        )
    FROM dispatched_subscriptions ds
    JOIN event_mst        e  ON e.event_id  = ds.event_id
    JOIN creator_profiles cp ON cp.id       = e.profile_id
    JOIN follows          f  ON f.user_id   = ds.user_id
                            AND f.profile_id = e.profile_id;

END;
$$;
```

> **Note:** `data` column on `notifications` is `jsonb`.
> Do NOT cast `json_build_object(...)::text` — it will fail with
> `column "data" is of type jsonb but expression is of type text`.
> `json_build_object()` → `json` → implicitly cast to `jsonb` ✅
>
> **Cron schedule:** `* * * * *` (every minute). All three blocks use a ±0.5-minute time
> window (or ±0.5 second for on_event_start) to catch each event exactly once per minute of cron firings.
