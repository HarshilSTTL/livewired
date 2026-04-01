# `08_event_mst`

```sql
-- Table: event_mst
-- Purpose: Master event records — creator schedules live events from their profiles
-- Doc: docs/database/tables/08_event_mst.md

CREATE TABLE IF NOT EXISTS public.event_mst (
    event_id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id        uuid        REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
    parent_event_id   uuid        NULL REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
    title             text,
    description       text        NULL,   -- nullable
    event_date        date,
    event_time        time,
    livestream        bool        DEFAULT false,
    video             bool        DEFAULT false,
    is_recurring      bool        DEFAULT false,
    created_at        timestamptz DEFAULT now(),
    updated_at        timestamptz NULL    -- nullable
);

-- FK name: event_mst_profile_id_fkey
-- FK name: event_mst_parent_event_id_fkey
--
-- parent_event_id usage:
--   NULL  → non-recurring event OR the parent/template row of a recurring series
--   <uuid> → a generated occurrence of the recurring series (child row)
--
-- When a recurring event is created, create_event inserts:
--   1. One parent row  (parent_event_id = NULL, is_recurring = true)
--   2. N child rows    (parent_event_id = parent.event_id, is_recurring = true)
--      one per occurrence date between recurring_start_date and recurring_end_date
--
-- Deleting the parent cascades to all child occurrences automatically.
-- event_platforms rows are only on the parent; children inherit via get_profile_events.
```
