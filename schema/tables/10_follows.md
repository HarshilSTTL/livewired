# `10_follows`

```sql
-- Table: follows
-- Purpose: User → creator profile follow relationships (soft delete pattern)
--          Also stores the follower's per-profile reminder preference (YouTube bell-icon model):
--          when reminder_enabled = true, the user automatically receives a notification
--          reminder_minutes minutes before every event on that profile, including every
--          occurrence of a recurring series.
-- Doc: docs/database/tables/10_follows.md

CREATE TABLE IF NOT EXISTS public.follows (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          uuid        REFERENCES public.users(id),
    profile_id       uuid        REFERENCES public.creator_profiles(id),
    created_at       timestamptz NULL DEFAULT now(),     -- nullable
    is_active        bool        DEFAULT true,
    unfollowed_at    timestamptz NULL,                   -- nullable; set on unfollow
    reminder_enabled boolean     NOT NULL DEFAULT false, -- follower opts in to auto-reminders
    reminder_minutes int         NOT NULL DEFAULT 10     -- minutes before event_time to fire (1..1440)
);

-- FK name: fk_user    → user_id    references public.users.id
-- FK name: fk_profile → profile_id references public.creator_profiles.id

-- Migration: run once in Supabase SQL editor
--   ALTER TABLE public.follows
--     ADD COLUMN IF NOT EXISTS reminder_enabled boolean NOT NULL DEFAULT false,
--     ADD COLUMN IF NOT EXISTS reminder_minutes int     NOT NULL DEFAULT 10;

-- Soft delete rules:
-- Follow:    INSERT (is_active=true, unfollowed_at=null)
-- Unfollow:  UPDATE SET is_active=false, unfollowed_at=now()
--            (reminder_enabled/minutes preserved across unfollow so re-follow restores choice)
-- Re-follow: UPDATE SET is_active=true, unfollowed_at=null, created_at=now()

-- Reminder rules:
--   reminder_enabled = false → no auto-reminders for this follower
--   reminder_enabled = true  → auto-reminders fire reminder_minutes before EVERY event on
--                              this profile (parent and every recurring child occurrence)
--   reminder_minutes range  = 1 to 1440 (1 minute to 24 hours)
--   Dedup: follow-level reminders are suppressed for events where the follower has a manual
--          event_reminders row (manual takes precedence). See follow_reminder_dispatches for
--          the exactly-once delivery guarantee.
```
