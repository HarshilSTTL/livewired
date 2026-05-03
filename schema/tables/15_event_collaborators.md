# `15_event_collaborators`

```sql
-- Table: event_collaborators
-- Purpose: Tracks collaborator invites for collaborative events.
--          One row per invited profile per event. Status moves from
--          pending → accepted | declined. Soft delete allows re-inviting.
-- Doc: docs/database/tables/15_event_collaborators.md

CREATE TABLE IF NOT EXISTS public.event_collaborators (
    id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id       uuid        NOT NULL REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
    profile_id     uuid        NOT NULL REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
    invited_by     uuid        NOT NULL REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
    status         text        NOT NULL DEFAULT 'pending',  -- 'pending' | 'accepted' | 'declined'
    invited_at     timestamptz DEFAULT now(),
    responded_at   timestamptz NULL,       -- set when collaborator responds
    updated_at     timestamptz DEFAULT now(),
    is_deleted     boolean     NOT NULL DEFAULT false,
    deleted_at     timestamptz NULL
);

-- Partial unique index: only one active invite per (event, profile).
-- Soft-deleted rows are excluded, so re-inviting after removal is allowed.
CREATE UNIQUE INDEX IF NOT EXISTS uq_event_collaborators_active
    ON public.event_collaborators (event_id, profile_id)
    WHERE is_deleted = false;

-- FK: event_collaborators_event_id_fkey   → event_mst.event_id     ON DELETE CASCADE
-- FK: event_collaborators_profile_id_fkey → creator_profiles.id    ON DELETE CASCADE
-- FK: event_collaborators_invited_by_fkey → creator_profiles.id    ON DELETE CASCADE

-- Migration: run once in Supabase SQL editor
--   CREATE TABLE IF NOT EXISTS public.event_collaborators ( ... );  -- full DDL above
--   CREATE UNIQUE INDEX IF NOT EXISTS uq_event_collaborators_active
--       ON public.event_collaborators (event_id, profile_id) WHERE is_deleted = false;
--
--   Also add is_collaborative to event_mst:
--   ALTER TABLE public.event_mst
--       ADD COLUMN IF NOT EXISTS is_collaborative boolean NOT NULL DEFAULT false;
```
