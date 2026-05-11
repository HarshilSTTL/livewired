# `process_event_reminders`

```sql
-- Function: process_event_reminders
-- Group: Notifications
-- Type: Cron job — runs every minute via pg_cron
-- Schedule: * * * * *
-- Tables: profile_event_notifications (SELECT), event_reminders (UPDATE),
--         follow_reminder_dispatches (INSERT), notifications (INSERT)
--
-- Three reminder sources:
--   1. profile_event_notifications — profile owner notifications for events on their profiles
--   2. event_reminders   — manual, per-(user, event), set explicitly by the follower
--   3. follows           — automatic, per-(user, profile), YouTube-style bell-icon opt-in
--
-- Profile owner reminders fire for any event on their own profiles (before_event, on_event_start, or both).
-- Manual and follow-level reminders have same behavior: manual takes precedence over follow-level
-- for the same event.

CREATE OR REPLACE FUNCTION process_event_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    -- ══════════════════════════════════════════════════════════════════════════
    -- 1. PROFILE OWNER notifications — from profile_event_notifications
    -- ══════════════════════════════════════════════════════════════════════════
    -- Profile owners get notifications for any event on their profiles.
    -- Two types: 'before_event' (X min before) and 'on_event_start' (at start time).
    -- Each child occurrence fires separately.

    -- ── "Before event" profile notifications ────────────────────────────────
    INSERT INTO notifications (user_id, title, body, data)
    SELECT
        u.id,
        cp.profile_name || ' event starting: ' || e.title,
        e.title,
        json_build_object(
            'type',             'profile_event',
            'event_id',         e.event_id,
            'profile_id',       cp.id,
            'reminder_minutes', pen.reminder_minutes,
            'fired_at',         'before_event'
        )
    FROM profile_event_notifications pen
    JOIN creator_profiles cp ON cp.id = pen.profile_id
    JOIN users u ON u.id = pen.user_id
    JOIN event_mst e ON e.profile_id = cp.id
    WHERE pen.notification_enabled = true
      AND pen.notification_type IN ('before_event', 'both')
      AND e.is_deleted = false
      AND cp.status = 'active'
      AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone
            BETWEEN NOW() + ((pen.reminder_minutes - 0.5) * interval '1 minute')
                AND NOW() + ((pen.reminder_minutes + 0.5) * interval '1 minute');

    -- ── "On event start" profile notifications ──────────────────────────────
    INSERT INTO notifications (user_id, title, body, data)
    SELECT
        u.id,
        cp.profile_name || ' event starting: ' || e.title,
        e.title,
        json_build_object(
            'type',       'profile_event',
            'event_id',   e.event_id,
            'profile_id', cp.id,
            'fired_at',   'on_event_start'
        )
    FROM profile_event_notifications pen
    JOIN creator_profiles cp ON cp.id = pen.profile_id
    JOIN users u ON u.id = pen.user_id
    JOIN event_mst e ON e.profile_id = cp.id
    WHERE pen.notification_enabled = true
      AND pen.notification_type IN ('on_event_start', 'both')
      AND e.is_deleted = false
      AND cp.status = 'active'
      -- Fire when event start time is now (within ±0.5 minute window)
      AND (e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone
            BETWEEN NOW() - interval '0.5 minute'
                AND NOW() + interval '0.5 minute';

    -- ══════════════════════════════════════════════════════════════════════════
    -- 2. MANUAL reminders — from event_reminders
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
    -- 3. FOLLOW-LEVEL reminders — from follows.reminder_enabled
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
