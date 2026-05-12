# `14_event_reminders`

```sql
-- Table: event_reminders
-- Purpose: Per-user per-event notification reminders
--          Each user sets their own reminder time for each event they care about.
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
    UNIQUE (user_id, event_id)   -- one active reminder per user per event
);

-- Migration: run once in Supabase SQL editor
--   CREATE TABLE IF NOT EXISTS public.event_reminders (
--       id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
--       user_id          uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
--       event_id         uuid        NOT NULL REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
--       reminder_minutes int         NOT NULL,
--       is_notified      boolean     NOT NULL DEFAULT false,
--       is_deleted       boolean     NOT NULL DEFAULT false,
--       deleted_at       timestamptz NULL,
--       created_at       timestamptz DEFAULT now(),
--       updated_at       timestamptz DEFAULT now(),
--       UNIQUE (user_id, event_id)
--   );
--
-- Soft delete: when a reminder is no longer needed, set is_deleted=true and deleted_at=now()
-- instead of deleting the row. Event queries must filter "is_deleted = false" to exclude deleted reminders.
```
