# `14_event_reminders`

```sql
-- Table: event_reminders
-- Purpose: Per-user per-event notification reminders
--          A user may set MULTIPLE reminder times for the same event
--          (e.g. 1 day before, 1 hour before, 10 minutes before).
--          pg_cron reads this table every minute and fires notifications when due.
-- Doc: docs/database/tables/14_event_reminders.md

CREATE TABLE IF NOT EXISTS public.event_reminders (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    event_id         uuid        NOT NULL REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
    reminder_minutes int         NOT NULL,          -- how many minutes before event to notify
    is_notified      boolean     NOT NULL DEFAULT false,  -- true after push has been sent
    is_deleted       boolean     NOT NULL DEFAULT false,  -- soft delete flag
    deleted_at       timestamptz NULL,                    -- timestamp of soft delete
    created_at       timestamptz DEFAULT now(),
    updated_at       timestamptz DEFAULT now(),
    UNIQUE (user_id, event_id, reminder_minutes)   -- multiple reminder times per user per event, but no exact duplicates
);

-- Migration: run once in Supabase SQL editor
--   ALTER TABLE public.event_reminders DROP CONSTRAINT IF EXISTS event_reminders_user_id_event_id_key;
--   ALTER TABLE public.event_reminders ADD CONSTRAINT event_reminders_user_id_event_id_reminder_minutes_key
--       UNIQUE (user_id, event_id, reminder_minutes);
--   Note: dropping the old (user_id, event_id) UNIQUE constraint is required first —
--   it would otherwise block inserting a second reminder time for the same user+event.
--
-- Soft delete: when a reminder is no longer needed, set is_deleted=true and deleted_at=now()
-- instead of deleting the row. Event queries must filter "is_deleted = false" to exclude deleted reminders.
```
