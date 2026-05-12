# `10_follows`

```sql
-- Table: follows
-- Purpose: User → creator profile follow relationships (soft delete pattern)
--          Stores TWO separate notification preferences:
--          1. reminder_enabled/reminder_minutes — event-specific manual reminders (per event)
--          2. event_notification_enabled/event_notification_minutes — profile-level subscriptions (all events)
-- Doc: docs/database/tables/10_follows.md

CREATE TABLE IF NOT EXISTS public.follows (
    id                           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                      uuid        REFERENCES public.users(id),
    profile_id                   uuid        REFERENCES public.creator_profiles(id),
    created_at                   timestamptz NULL DEFAULT now(),     -- nullable
    is_active                    bool        DEFAULT true,
    unfollowed_at                timestamptz NULL,                   -- nullable; set on unfollow
    reminder_enabled             boolean     NOT NULL DEFAULT false, -- event-specific reminders (manual per-event)
    reminder_minutes             int         NOT NULL DEFAULT 10,    -- minutes before event for manual reminders (1..1440)
    event_notification_enabled   boolean     NOT NULL DEFAULT false, -- profile-level event subscriptions
    event_notification_minutes   int         NULL                    -- minutes before event start (NULL = at start time)
);

-- FK name: fk_user    → user_id    references public.users.id
-- FK name: fk_profile → profile_id references public.creator_profiles.id

-- Migration: run once in Supabase SQL editor
--   ALTER TABLE public.follows
--     ADD COLUMN IF NOT EXISTS reminder_enabled boolean NOT NULL DEFAULT false,
--     ADD COLUMN IF NOT EXISTS reminder_minutes int     NOT NULL DEFAULT 10,
--     ADD COLUMN IF NOT EXISTS event_notification_enabled boolean NOT NULL DEFAULT false,
--     ADD COLUMN IF NOT EXISTS event_notification_minutes int NULL;

-- Soft delete rules:
-- Follow:    INSERT (is_active=true, unfollowed_at=null)
-- Unfollow:  UPDATE SET is_active=false, unfollowed_at=now()
--            (reminder_enabled/minutes preserved across unfollow so re-follow restores choice)
-- Re-follow: UPDATE SET is_active=true, unfollowed_at=null, created_at=now()

-- Event-specific reminder rules (manual per-event):
--   reminder_enabled = false → no auto-reminders for this follower
--   reminder_enabled = true  → auto-reminders fire reminder_minutes before EVERY event on
--                              this profile (parent and every recurring child occurrence)
--   reminder_minutes range  = 1 to 1440 (1 minute to 24 hours)
--   Dedup: follow-level reminders are suppressed for events where follower has manual
--          event_reminders row (manual takes precedence).

-- Profile-level event subscription rules (automatic for all events):
--   event_notification_enabled = false → no profile subscriptions
--   event_notification_enabled = true  → auto-notifications fire at configured time for ALL events
--   event_notification_minutes = NULL → notify exactly at event start time
--   event_notification_minutes = 5/10/15 → notify X minutes before event start
--   Minutes range = 5/10/15 (configurable; NULL also valid)
--   Dedup: profile-level notifications are suppressed for events where follower has a manual
--          event_reminders row (manual takes precedence). See follow_event_subscription_dispatches.
--   Persistence: settings persist across unfollow/re-follow cycles
--   Applies to: ALL events (recurring + non-recurring) on the profile
```
