# `18_follow_event_subscription_dispatches`

```sql
-- Table: follow_event_subscription_dispatches
-- Purpose: Exactly-once delivery ledger for profile-level event subscriptions
--          Records which (user, event) pairs have already sent a notification
--          via profile subscription (not manual reminders). Composite PK ensures
--          one notification per (user, event) pair even with cron retries.
-- Doc: docs/database/tables/18_follow_event_subscription_dispatches.md

CREATE TABLE IF NOT EXISTS public.follow_event_subscription_dispatches (
    user_id     uuid        NOT NULL REFERENCES public.users(id)        ON DELETE CASCADE,
    event_id    uuid        NOT NULL REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
    notified_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, event_id)
);

-- Composite PK: (user_id, event_id)
-- Semantics: "This user was notified about this event via profile subscription"
-- Dedup: INSERT ... ON CONFLICT (user_id, event_id) DO NOTHING
--        If cron fires twice for same (user, event), second insert is skipped silently.
-- Scope:  Profile-level subscriptions only — manual event_reminders use separate dispatch table

-- Migration: run once in Supabase SQL editor
--   CREATE TABLE IF NOT EXISTS public.follow_event_subscription_dispatches (
--       user_id     uuid        NOT NULL REFERENCES public.users(id)        ON DELETE CASCADE,
--       event_id    uuid        NOT NULL REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
--       notified_at timestamptz NOT NULL DEFAULT now(),
--       PRIMARY KEY (user_id, event_id)
--   );
```
