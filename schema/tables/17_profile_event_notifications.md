# `17_profile_event_notifications`

```sql
-- Table: profile_event_notifications
-- Purpose: Profile-level event notification settings for profile owners.
--          Allows a user to receive notifications for any event created on their profiles.
--          Separate from follow reminders (which are for followers of a profile).
-- Doc: docs/database/tables/17_profile_event_notifications.md

CREATE TABLE IF NOT EXISTS public.profile_event_notifications (
    id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id               uuid        NOT NULL REFERENCES public.users(id)            ON DELETE CASCADE,
    profile_id            uuid        NOT NULL REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
    notification_enabled  boolean     NOT NULL DEFAULT false,
    notification_type     text        NOT NULL DEFAULT 'before_event', -- 'before_event' | 'on_event_start' | 'both'
    reminder_minutes      int         NOT NULL DEFAULT 10,  -- 1-1440, only used when type includes 'before_event'
    created_at            timestamptz DEFAULT now(),
    updated_at            timestamptz DEFAULT now()
);

-- Unique constraint: one notification setting per (user, profile)
CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_event_notifications
    ON public.profile_event_notifications (user_id, profile_id);

-- Foreign keys:
--   user_id        → users.id           ON DELETE CASCADE
--   profile_id     → creator_profiles.id ON DELETE CASCADE

-- Migration: run once in Supabase SQL editor
--   CREATE TABLE IF NOT EXISTS public.profile_event_notifications (
--       id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
--       user_id               uuid        NOT NULL REFERENCES public.users(id)            ON DELETE CASCADE,
--       profile_id            uuid        NOT NULL REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
--       notification_enabled  boolean     NOT NULL DEFAULT false,
--       notification_type     text        NOT NULL DEFAULT 'before_event',
--       reminder_minutes      int         NOT NULL DEFAULT 10,
--       created_at            timestamptz DEFAULT now(),
--       updated_at            timestamptz DEFAULT now()
--   );
--
--   CREATE UNIQUE INDEX IF NOT EXISTS uq_profile_event_notifications
--       ON public.profile_event_notifications (user_id, profile_id);
```
