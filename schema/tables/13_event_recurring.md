# `13_event_recurring`

```sql
-- Table: event_recurring
-- Purpose: Stores recurring schedule details for events where is_recurring = true
-- Doc: docs/database/tables/13_event_recurring.md
--
-- Notes:
--   • One row per recurring event (1:1 with event_mst where is_recurring = true)
--   • ON DELETE CASCADE — deleting the event removes this row automatically
--   • recurring_type = 'weekly' → recurring_interval required (1–12)
--   • recurring_type = 'first' or 'last' → recurring_interval must be NULL
--   • recurring_end_date is optional (open-ended recurring if NULL)

CREATE TABLE IF NOT EXISTS public.event_recurring (
    id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id             uuid        REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
    recurring_days       text[],     -- e.g. {'Mon','Tue','Wed'} — at least one value required
    recurring_type       text,       -- 'weekly' | 'first' | 'last'
    recurring_interval   int         DEFAULT NULL,  -- 1–12 weeks (only for 'weekly' type)
    recurring_start_date date,       -- when the recurring schedule begins
    recurring_end_date   date        DEFAULT NULL,  -- when recurring ends; always populated (default = start + 3 months)
    renewal_notified_at  timestamptz DEFAULT NULL,  -- set when renewal notification is sent; NULL = not yet notified
    created_at           timestamptz DEFAULT now()
);

-- FK: event_recurring_event_id_fkey → event_mst.event_id ON DELETE CASCADE
-- Migration: run once in Supabase SQL editor
--   ALTER TABLE public.event_recurring ADD COLUMN IF NOT EXISTS renewal_notified_at timestamptz DEFAULT NULL;
```
