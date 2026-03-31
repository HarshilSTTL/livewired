# `08_event_mst`

```sql
-- Table: event_mst
-- Purpose: Master event records — creator schedules live events from their profiles
-- Doc: docs/database/tables/08_event_mst.md

CREATE TABLE IF NOT EXISTS public.event_mst (
    event_id     uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id   uuid        REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
    title        text,
    description  text        NULL,   -- nullable
    event_date   date,
    event_time   time,
    livestream   bool        DEFAULT false,
    video        bool        DEFAULT false,
    is_recurring bool        DEFAULT false,
    created_at   timestamptz DEFAULT now(),
    updated_at   timestamptz NULL    -- nullable
);

-- FK name: event_mst_profile_id_fkey
```
