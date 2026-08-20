# `update_event`

## Version History

### v2.5 (Current — 2026-08-20) ✅
- **Function name:** `update_event_v2_5`
- **Endpoint:** `POST /rpc/update_event_v2_5`
- **Change from v2.4:** Adds `p_event_end_date`, matching `create_event_v4`, so an
  event can safely run past midnight without relying on "end_time < start_time" as
  an implicit signal.
  - `p_event_end_date` (optional) — like every other scalar field here, `null` means
    "leave the current end date untouched"; it does not default back to the start
    date on every edit.
  - End time validation is now a real datetime comparison against the resolved final
    `(event_date, event_time)` / `(event_end_date, event_end_time)` pair, for both
    `p_scope='this'` and `p_scope='all'`. Previously only exact time-of-day equality
    was rejected.
  - Recurring rule regeneration (`p_scope='all'` + `p_recurring_days=[...]`) carries
    the series' end-date offset (days between start and end) onto every freshly
    generated sibling occurrence, same as `event_time`/`event_end_time` are already
    copied onto every sibling.

### v2.4 (Previous — 2026-08-12)
- **Function name:** `update_event_v2_4`
- **Endpoint:** `POST /rpc/update_event_v2_4`
- **Change from v2.3:** Adds the missing ability to convert a recurring event back into
  a non-recurring one. Every prior version silently no-oped on this: `v_update_recurring`
  only ever fired when `p_recurring_days` was a non-empty array, so passing `null` (or `[]`)
  to "clear" recurrence never touched `is_recurring`, `event_recurring`, or the sibling
  occurrences — the event stayed recurring no matter what was sent.
  - `p_recurring_days: []` (empty array, **not** `null`) is now the explicit "make this
    event non-recurring" signal — `null` still means "leave recurrence untouched", matching
    the existing null-vs-`[]` convention already used by `p_platforms` and `p_collaborator_ids`.
  - Only valid with `p_scope='all'` (same restriction as changing/adding a recurring rule) —
    `p_scope='this'` with `p_recurring_days=[]` is rejected with the same
    "use scope 'all'" error as `p_recurring_days=[...]`.
  - A no-op if the event isn't currently recurring (nothing to remove).
  - Deletes every sibling occurrence and the `event_recurring` rule row, then collapses the
    edited event (`p_event_id`) back into a standalone row: if it was a child occurrence,
    it absorbs the series identity (`parent_event_id = NULL`, `is_recurring = false`) and the
    now-empty hidden template row is deleted (mirroring the v2.3 first-conversion logic, in
    reverse); if `p_event_id` was itself the hidden template, `is_recurring` is just flipped
    to `false` on it directly.
  - This whole collapse runs **before** Branch A/B, not after (fixed during testing — see
    `updates/2026-08-12.md`): if it ran after, any `p_platforms`/`p_collaborator_ids` sent in
    the same request got written to the old (soon-to-be-deleted) template instead of the
    surviving `p_event_id`, then vanished when the template was dropped. The collapse also
    now copies the template's existing platforms/collaborators onto `p_event_id` first (only
    if it doesn't already have its own), so a plain "just remove recurring, don't touch
    anything else" call doesn't silently strip platforms/collaborators that `p_event_id` was
    only seeing via `COALESCE(parent_event_id, event_id)` fallback.
  - No `notifications` row is inserted on collaborator invite/re-invite anymore — the
    "Collaboration Invite" notification that every prior version sent as a side effect of
    syncing `p_collaborator_ids` has been removed (same version, updated in place before
    first deployment — see `updates/2026-08-12.md`). Invite/remove behavior on
    `event_collaborators` itself is unchanged.
  - **Fixes data loss on established recurring series edits:** editing the recurring rule
    of an already-established series (`p_scope='all'` + `p_recurring_days=[...]`, not a
    first conversion) previously deleted **every** child occurrence unconditionally — v2.2
    and v2.3 both did this, including deleting `p_event_id` itself if it happened to be a
    child, cascading away its own `event_platforms`/`event_collaborators` rows and replacing
    it with a freshly generated row under a brand-new `event_id`. `p_event_id` is now always
    excluded from that delete-and-regenerate, so the occurrence actually being edited keeps
    its identity and any per-occurrence platform/collaborator override on it survives. Every
    other sibling is still deleted and regenerated fresh, unchanged from before.
  - **Fixes `duplicate key value violates unique constraint "uq_event_collaborators_active"`
    on collaborator sync:** the "find existing row" lookup in the invite/re-invite loop
    (`SELECT id, is_deleted FROM event_collaborators WHERE event_id=... AND profile_id=...
    LIMIT 1`) had no `ORDER BY`. A profile can legitimately have both an old soft-deleted
    row and a current active row for the same `(event_id, profile_id)` (that's how
    re-inviting after removal works) — without an explicit order, Postgres can return
    either one. If it returned the soft-deleted row while an active row for that same
    profile also existed, the code fell through to the re-invite branch and tried to flip
    the soft-deleted row back to active, creating two active rows for the same
    `(event_id, profile_id)` — violating the partial unique index. This bug dates back to
    v2.0 (every version inherited it unchanged) and was just latent until enough repeated
    add/remove testing on the same event+profile produced both row states at once. Fixed
    by adding `ORDER BY is_deleted ASC` so the active row is always picked when one exists.
    **This bug is present in the currently-deployed `update_event_v2_4` — requires a
    redeploy of this SQL to take effect** (see `updates/2026-08-12.md`).

### v2.3 (Previous — 2026-08-11)
- **Function name:** `update_event_v2_3`
- **Endpoint:** `POST /rpc/update_event_v2_3`
- **Change from v2.2:** Fixes converting a non-recurring event into a recurring one
  (`p_scope='this'`/`'all'` + `p_recurring_days` on an event whose `parent_event_id`
  was `NULL` and `is_recurring` was `false`):
  - The event being edited (`p_event_id`) is now converted into the first child
    occurrence of the new series instead of being left as the series' hidden
    parent/template row while a brand-new duplicate row gets generated for the
    same date. A fresh hidden template row is created to hold the recurrence
    rule, and `p_event_id` is re-pointed at it (`parent_event_id`) — the caller's
    event id keeps working and no longer disappears from `get_profile_events`
    (which excludes `is_recurring = true AND parent_event_id IS NULL` rows).
  - `event_recurring` is now upserted (`UPDATE`, then `INSERT` if no row existed)
    instead of only `UPDATE`d. Previously, converting a non-recurring event left
    `event_recurring` with zero rows for that series (the `UPDATE` silently
    affected 0 rows), so every occurrence read back `"recurring": null` even
    though `is_recurring` was `true`.
  - The new hidden template inherits the edited event's platforms and
    already-active collaborators (copied, not moved) so sibling occurrences —
    which fall back to `COALESCE(parent_event_id, event_id)` for both — see the
    same data the user had already set, instead of it vanishing once
    `p_event_id` stops being its own parent.
  - Does not change behavior for events that were already part of a recurring
    series — regenerating an established series' occurrences is unaffected.

### v2.2 (Previous — 2026-08-10)
- **Function name:** `update_event_v2_2`
- **Endpoint:** `POST /rpc/update_event_v2_2`
- **Change from v2.1:** `p_is_collaborative` is now scope-aware
  - `p_scope='this'` → updates `is_collaborative` only on the occurrence itself (`p_event_id`).
  - `p_scope='all'` → updates the parent + all children, same as before.
  - Fixes: passing `p_is_collaborative=false` alongside a `p_scope='this'` collaborator
    removal (e.g. clearing the last collaborator on one occurrence) was turning off
    `is_collaborative` for the WHOLE recurring series, not just that occurrence.
  - No schema or read-path change needed — `is_collaborative` already exists per-row on
    every occurrence and every read SP already reads it directly (no parent fallback);
    only the write path was wrongly forcing it onto every row regardless of scope.

### v2.1 (Previous — 2026-08-06)
- **Function name:** `update_event_v2_1`
- **Endpoint:** `POST /rpc/update_event_v2_1`
- **Change from v2.0:** Collaborator sync is now scope-aware
  - `p_scope='this'` → collaborators are synced against the occurrence itself
    (`event_id = p_event_id`), not the series parent. `event_mst.collaborators_overridden`
    is set `true` on that occurrence so reads know to use its own collaborator rows.
  - `p_scope='all'` → behaves like v2.0 (syncs the series parent), but first clears any
    per-occurrence overrides created by a prior `'this'`-scoped call, so children go back
    to inheriting the series list.
  - Fixes: updating collaborators with `p_scope='this'` no longer changes collaborators
    for every occurrence in the series.
- Requires new column `event_mst.collaborators_overridden` (see schema/tables/08_event_mst.md)
  and matching read-path changes in `get_event_by_id_v2`, `get_profile_events_v2_1`, `get_event_list_v2`.

### v2.0 (Previous — 2026-06-15)
- **Function name:** `update_event_v2`
- **Endpoint:** `POST /rpc/update_event_v2`
- **Change from v1:** Collaborator sync behavior
  - `null` → don't touch collaborators
  - `[]` → remove all collaborators
  - `[1,2,3]` → sync: add new, remove missing, keep existing

### v1.0 (Deprecated)
- **Function name:** `update_event`
- Collaborators were append-only (`[]` = don't touch)
- **Endpoint:** `POST /rpc/update_event`

---

## V2.5 Function (Current) ✅

```sql
-- Function: update_event_v2_5
-- Group: Events
-- Endpoint: POST /rpc/update_event_v2_5
-- Tables:   event_mst (UPDATE/INSERT/DELETE), event_platforms (DELETE+INSERT), event_recurring (UPDATE/INSERT/DELETE)
--           event_collaborators (INSERT/UPDATE/soft-delete)
-- Doc: docs/api/events/update_event.md
-- Version: 2.5 (2026-08-20)
--
-- Change from v2.4: Adds p_event_end_date, matching create_event_v4, so an event can
--   safely run past midnight without relying on "end_time < start_time" as an implicit
--   signal.
--   - p_event_end_date: null = leave the current end date untouched (same convention as
--     every other scalar field here — it does NOT reset to the start date on every edit).
--   - End time validation is now a real datetime comparison against the resolved final
--     (event_date, event_time) / (event_end_date, event_end_time) pair, for both
--     p_scope='this' and p_scope='all'. If no end date can be resolved (neither supplied
--     nor already on the row), it falls back to the resolved start date, matching
--     create_event_v4's default-to-start-date behavior.
--   - Recurring rule regeneration (p_scope='all' + p_recurring_days=[...]) computes the
--     day offset between the series' start and end date and reapplies it to every
--     freshly generated sibling occurrence's event_end_date, so a multi-day recurring
--     event keeps its duration on every occurrence — same treatment event_time/
--     event_end_time already get (copied verbatim onto every sibling).
--
-- DEPLOYMENT — this is a NEW function name (update_event_v2_5), no overload to drop.
-- Old callers on update_event_v2_4 keep working unchanged (see "V2.4 Function (Previous)" below).
-- Point the client at /rpc/update_event_v2_5 once deployed, then:
--   NOTIFY pgrst, 'reload schema';
--
-- Change from v2.3 (3): Fixes data loss when editing an already-established recurring
--   series' rule (p_scope='all' + p_recurring_days=[...], not a first conversion).
--   v2.2/v2.3 deleted EVERY child occurrence unconditionally on this path, including
--   p_event_id itself if it happened to be a child — cascading away its own
--   event_platforms/event_collaborators rows and replacing it with a freshly generated
--   row under a brand-new event_id. p_event_id is now always excluded from that
--   delete-and-regenerate, so the occurrence actually being edited keeps its identity
--   and any per-occurrence platform/collaborator override on it. Every other sibling is
--   still deleted and regenerated fresh, unchanged from before.
--
-- Change from v2.3 (2): No "Collaboration Invite" notification is sent on invite/
--   re-invite anymore — the notifications INSERT that every prior version fired as
--   a side effect of syncing p_collaborator_ids has been removed. Inviting/removing
--   collaborators via update_event still works exactly the same otherwise; only the
--   notification side effect is gone.
--
-- Change from v2.3 (1): Adds the missing ability to un-recur an event.
--
--   Every prior version only ever acted on p_recurring_days when it was a non-empty
--   array (v_update_recurring). Passing null OR [] both fell through as "no rule
--   change" — there was no code path that could ever set is_recurring = false, so a
--   recurring event stayed recurring no matter what was sent to try to clear it.
--
--   Fix: p_recurring_days = [] (empty array, NOT null) is now the explicit "make this
--   event non-recurring" signal, matching the null/[] convention already used by
--   p_platforms and p_collaborator_ids elsewhere in this same function. null keeps
--   meaning "leave recurrence untouched".
--
--   Only valid with p_scope='all' — p_scope='this' + p_recurring_days=[] is rejected
--   with the same "use scope 'all'" error as changing/adding a rule. A no-op if the
--   event isn't currently part of a recurring series.
--
--   On removal: every sibling occurrence and the event_recurring rule row are deleted,
--   then p_event_id collapses back into a standalone event — if it was a child
--   occurrence it absorbs the series identity (parent_event_id = NULL, is_recurring =
--   false) and the now-orphaned hidden template row is deleted (the v2.3
--   first-conversion logic, run in reverse); if p_event_id was itself the hidden
--   template, is_recurring is simply flipped to false on it directly.
--
-- Change from v2.2: Fixes converting a non-recurring event into a recurring one.
--
--   Bug 1 — duplicate instead of reuse: when p_event_id had parent_event_id IS NULL
--   and was_recurring = false (i.e. a plain single event being made recurring for
--   the first time), v2.2 treated p_event_id itself as the series' parent/template
--   row and regenerated occurrences from scratch — including a brand-new row for
--   the same date as p_event_id. Since get_profile_events excludes
--   (is_recurring = true AND parent_event_id IS NULL) rows, p_event_id effectively
--   vanished from listings and was replaced by the freshly generated duplicate.
--   Fix: on first conversion, create a new hidden template row (parent_event_id = NULL)
--   to own the recurrence rule, re-point p_event_id at it (parent_event_id = new
--   template id, is_recurring = true) so p_event_id stays visible as the series'
--   first occurrence, and skip generating a duplicate for that same date.
--
--   Bug 2 — recurring always null: event_recurring was only ever UPDATEd, never
--   INSERTed, so first-time conversions left zero event_recurring rows for the
--   series — every occurrence read back "recurring": null. Fix: UPDATE, then
--   INSERT if no row was found (upsert).
--
--   The new hidden template also inherits p_event_id's platforms and already-active
--   collaborators (copied, not moved) since sibling occurrences with
--   is_overridden/collaborators_overridden = false fall back to
--   COALESCE(parent_event_id, event_id) for both.
--
--   Editing an already-established recurring series (parent_event_id already set,
--   or is_recurring already true) is unchanged from v2.2.
--
-- Change from v2.1: p_is_collaborative is now scope-aware
--   p_scope='this' → updates is_collaborative only on the occurrence itself (p_event_id).
--   p_scope='all' → updates the parent + all children, same as before.
--
-- Change from v2.0: Collaborator sync behavior
--   p_collaborator_ids: null        = don't touch existing collaborators
--   p_collaborator_ids: []          = remove ALL collaborators (soft delete)
--   p_collaborator_ids: [id1,id2]   = SYNC — keep id1/id2, remove anyone not in list, add new ones
--
-- p_scope: 'all' (default) = update parent + all occurrences
--          'this'          = per-occurrence scalar/platform/collaborator overrides
-- p_platforms:        null = don't touch | [] = clear all | [...] = replace
-- p_recurring_days:   null = no rule change | [] = REMOVE recurring ('all' scope only) | [...] = update + regen ('all' scope only)
-- p_is_collaborative: always parent-level (applied to parent + all children when set)
-- p_collaborator_ids: 'all' scope = series-level (parent) | 'this' scope = occurrence-level
--                     (see collaborators_overridden on event_mst)
--
CREATE OR REPLACE FUNCTION update_event_v2_5(
    p_event_id             uuid,
    p_user_id              uuid,
    p_scope                text     DEFAULT 'all',
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_event_end_time       time     DEFAULT NULL,
    p_event_end_date       date     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_is_collaborative     boolean  DEFAULT NULL,
    p_collaborator_ids     uuid[]   DEFAULT NULL,
    p_platforms            jsonb    DEFAULT NULL,
    -- Recurring fields
    p_recurring_days       text[]   DEFAULT NULL,
    p_recurring_type       text     DEFAULT NULL,
    p_recurring_interval   int      DEFAULT NULL,
    p_recurring_start_date date     DEFAULT NULL,
    p_recurring_end_date   date     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Intent flags
    v_scope             text;
    v_update_recurring  boolean;
    v_remove_recurring  boolean;
    v_currently_recurring boolean;
    v_sync_collabs      boolean;   -- true when p_collaborator_ids IS NOT NULL (including [])
    v_has_scalar        boolean;
    v_has_platforms     boolean;
    v_occurrence_change boolean;

    v_platform          jsonb;

    -- Parent resolution
    v_parent_event_id    uuid;
    v_target_parent_id   uuid;

    -- First-time recurring conversion (v2.3)
    v_was_recurring       boolean;
    v_is_first_conversion boolean;
    v_new_parent_id       uuid;
    v_first_occ_date      date;

    -- End-time validation
    v_existing_event_date     date;
    v_existing_event_time     time;
    v_existing_event_end_date date;
    v_existing_event_end_time time;
    v_final_event_date        date;
    v_final_event_time        time;
    v_final_event_end_date    date;
    v_final_event_end_time    time;
    v_end_date_offset         int;

    -- Recurring rule build-up
    v_rec_days      text[];
    v_rec_type      text;
    v_rec_interval  int;
    v_rec_start     date;
    v_rec_end       date;
    v_safe_end      date;

    -- Child generation
    v_profile_id         uuid;
    v_title              text;
    v_description        text;
    v_event_date         date;
    v_event_time         time;
    v_event_end_date     date;
    v_event_end_time     time;
    v_event_tz           text;
    v_livestream         boolean;
    v_video              boolean;
    v_is_collaborative   boolean;
    v_day_name           text;
    v_dow_target         int;
    v_dow_start          int;
    v_days_ahead         int;
    v_first_occ          date;
    v_occ_date           date;
    v_month_start        date;
    v_month_end          date;
    v_dow_month_end      int;

    -- Collaborator sync
    v_owner_profile_id   uuid;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;
    v_existing_collab_id uuid;
    v_existing_deleted   boolean;
    v_effective_is_collab boolean;
    v_collab_target_id   uuid;   -- event_id collaborator rows are keyed to (occurrence when scope='this', parent when scope='all')

    v_success_message    text;
BEGIN

    -- ── 1. Required params ────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── 2. Normalise scope ────────────────────────────────────────────────────
    v_scope := COALESCE(NULLIF(trim(p_scope), ''), 'all');
    IF v_scope NOT IN ('all', 'this') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be ''all'' or ''this''');
    END IF;

    -- ── 3. Intent flags ───────────────────────────────────────────────────────
    v_update_recurring := p_recurring_days IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) > 0;

    -- v2.4: p_recurring_days = [] (empty, non-null) is the explicit "remove recurring"
    -- signal — null still means "don't touch", matching p_platforms/p_collaborator_ids.
    v_remove_recurring := p_recurring_days IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) = 0;

    -- v2 change: sync triggers on ANY non-null value, including empty array
    v_sync_collabs := p_collaborator_ids IS NOT NULL;

    -- v2.1: 'this' scope syncs the occurrence's OWN collaborator rows (event_id = p_event_id);
    -- 'all' scope syncs the series' collaborator rows (event_id = v_target_parent_id), same as v2.0.
    -- Resolved after v_scope is demoted below (step 6), so recompute isn't needed until then.

    v_has_scalar := p_title          IS NOT NULL OR p_description   IS NOT NULL
                 OR p_event_date     IS NOT NULL OR p_event_time    IS NOT NULL
                 OR p_event_end_time IS NOT NULL OR p_event_end_date IS NOT NULL
                 OR p_timezone       IS NOT NULL
                 OR p_livestream     IS NOT NULL OR p_video         IS NOT NULL;
    v_has_platforms     := p_platforms IS NOT NULL;
    v_occurrence_change := v_has_scalar OR v_has_platforms;

    -- ── 4. Ownership check ───────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── 5. Resolve parent event ──────────────────────────────────────────────
    SELECT parent_event_id, is_recurring INTO v_parent_event_id, v_was_recurring
    FROM event_mst WHERE event_id = p_event_id;

    v_target_parent_id := COALESCE(v_parent_event_id, p_event_id);

    -- v2.3: true only when p_event_id is not, and was never, part of any recurring
    -- series — i.e. this call is the one converting it into one for the first time.
    v_is_first_conversion := v_parent_event_id IS NULL AND COALESCE(v_was_recurring, false) = false;

    -- v2.4: true when p_event_id is currently part of a recurring series in any way
    -- (a child occurrence, or the hidden template/parent itself).
    v_currently_recurring := v_parent_event_id IS NOT NULL OR COALESCE(v_was_recurring, false);

    -- ── 6. Demote 'this' to 'all' for non-recurring events ───────────────────
    IF v_scope = 'this' AND v_parent_event_id IS NULL THEN
        v_scope := 'all';
    END IF;

    -- ── 6b. Resolve collaborator sync target ─────────────────────────────────
    v_collab_target_id := CASE WHEN v_scope = 'this' THEN p_event_id ELSE v_target_parent_id END;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule REMOVAL (v2.4) — p_recurring_days: [] (empty, non-null)
    -- is the explicit "make non-recurring" signal, matching the null/[] convention
    -- already used by p_platforms and p_collaborator_ids. null keeps meaning "leave
    -- recurrence untouched" (no code path here fires for it).
    --
    -- A no-op if the event isn't currently part of a recurring series.
    --
    -- Runs BEFORE Branch A/B on purpose: once this collapses p_event_id's identity
    -- and deletes the old hidden template, v_target_parent_id/v_collab_target_id
    -- must already point at the surviving row (p_event_id) so the scalar/platform/
    -- collaborator writes below land on it instead of on a row that's about to be
    -- deleted. Doing this after Branch A/B (as first drafted) silently discarded
    -- whatever Branch A/B had just written to the old template — e.g. a p_platforms
    -- payload sent in the same call ended up inserted onto the template's event_id,
    -- which was then deleted here, leaving the surviving event with no platforms.
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_remove_recurring AND v_currently_recurring THEN

        -- Drop every sibling occurrence except the one being edited.
        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id AND event_id != p_event_id;

        -- Drop the recurrence rule itself.
        DELETE FROM event_recurring WHERE event_id = v_target_parent_id;

        IF v_parent_event_id IS NOT NULL THEN
            -- p_event_id was a visible child occurrence relying on
            -- COALESCE(parent_event_id, event_id) fallback to the template's own
            -- platforms/collaborators (when not individually overridden). That
            -- fallback breaks the instant parent_event_id is cleared below, so copy
            -- the template's rows onto p_event_id first — but only if p_event_id
            -- doesn't already have its own (an existing per-occurrence override
            -- must win, not be duplicated alongside a copy of the template's).
            INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
            SELECT gen_random_uuid(), p_event_id, platform_id, stream_url, now()
            FROM event_platforms
            WHERE event_id = v_target_parent_id
              AND NOT EXISTS (SELECT 1 FROM event_platforms WHERE event_id = p_event_id);

            INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, responded_at, updated_at)
            SELECT gen_random_uuid(), p_event_id, profile_id, invited_by, status, invited_at, responded_at, now()
            FROM event_collaborators
            WHERE event_id = v_target_parent_id AND is_deleted = false
              AND NOT EXISTS (SELECT 1 FROM event_collaborators WHERE event_id = p_event_id AND is_deleted = false);

            -- p_event_id was a visible child occurrence — absorb the series identity
            -- into it (mirrors the v2.3 first-conversion logic above, in reverse) and
            -- drop the now-empty hidden template row that used to own the rule.
            UPDATE event_mst
            SET parent_event_id = NULL,
                is_recurring     = false,
                updated_at       = now()
            WHERE event_id = p_event_id;

            DELETE FROM event_mst WHERE event_id = v_target_parent_id;

            -- Every write below (Branch A/B scalar+platform update, is_collaborative,
            -- collaborator sync) must now target the row that actually survives.
            v_collab_target_id := p_event_id;
        ELSE
            -- p_event_id WAS the hidden template/parent itself — its own row
            -- survives (and already owns its platforms/collaborators directly),
            -- just flip the flag.
            UPDATE event_mst
            SET is_recurring = false,
                updated_at   = now()
            WHERE event_id = p_event_id;
        END IF;

        v_target_parent_id := p_event_id;

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH A: scope = 'this'
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'this' THEN

        IF v_update_recurring OR v_remove_recurring THEN
            RETURN json_build_object('status', false, 'message',
                'Recurring schedule cannot be changed for a single occurrence — use scope ''all''');
        END IF;

        IF v_has_scalar THEN
            SELECT event_date, event_time, event_end_date, event_end_time
            INTO v_existing_event_date, v_existing_event_time, v_existing_event_end_date, v_existing_event_end_time
            FROM event_mst WHERE event_id = p_event_id;

            v_final_event_date     := COALESCE(p_event_date,     v_existing_event_date);
            v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
            v_final_event_end_date := COALESCE(p_event_end_date, v_existing_event_end_date, v_final_event_date);
            v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

            IF v_final_event_end_time IS NOT NULL
               AND (v_final_event_end_date || ' ' || v_final_event_end_time)::timestamp
                   <= (v_final_event_date || ' ' || v_final_event_time)::timestamp THEN
                RETURN json_build_object('status', false, 'message', 'Event end date/time must be after the event start date/time');
            END IF;
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_occurrence_change THEN
            UPDATE event_mst
            SET title          = COALESCE(p_title,          title),
                description    = COALESCE(p_description,    description),
                event_date     = COALESCE(p_event_date,     event_date),
                event_time     = COALESCE(p_event_time,     event_time),
                event_end_date = COALESCE(p_event_end_date, event_end_date),
                event_end_time = COALESCE(p_event_end_time, event_end_time),
                event_timezone = COALESCE(p_timezone,       event_timezone),
                livestream     = COALESCE(p_livestream,     livestream),
                video          = COALESCE(p_video,          video),
                is_overridden  = true,
                updated_at     = now()
            WHERE event_id = p_event_id;
        END IF;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = p_event_id;
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), p_event_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event occurrence updated successfully';

    ELSE
    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH B: scope = 'all'
    -- ══════════════════════════════════════════════════════════════════════════

        SELECT event_date, event_time, event_end_date, event_end_time
        INTO v_existing_event_date, v_existing_event_time, v_existing_event_end_date, v_existing_event_end_time
        FROM event_mst WHERE event_id = v_target_parent_id;

        v_final_event_date     := COALESCE(p_event_date,     v_existing_event_date);
        v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
        v_final_event_end_date := COALESCE(p_event_end_date, v_existing_event_end_date, v_final_event_date);
        v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

        IF v_final_event_end_time IS NOT NULL
           AND (v_final_event_end_date || ' ' || v_final_event_end_time)::timestamp
               <= (v_final_event_date || ' ' || v_final_event_time)::timestamp THEN
            RETURN json_build_object('status', false, 'message', 'Event end date/time must be after the event start date/time');
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_update_recurring THEN

            IF EXISTS (
                SELECT 1 FROM unnest(p_recurring_days) AS d(day)
                WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
            END IF;

            SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
            INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
            FROM event_recurring WHERE event_id = v_target_parent_id;

            v_rec_days     := p_recurring_days;
            v_rec_type     := COALESCE(p_recurring_type,       v_rec_type);
            v_rec_start    := COALESCE(p_recurring_start_date, v_rec_start);
            v_rec_end      := COALESCE(p_recurring_end_date,   v_rec_end);

            IF v_rec_type IS NULL OR v_rec_type NOT IN ('weekly', 'first', 'last') THEN
                RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
            END IF;

            IF v_rec_type IN ('first', 'last') THEN
                v_rec_interval := NULL;
            ELSE
                v_rec_interval := COALESCE(p_recurring_interval, v_rec_interval);
                IF v_rec_interval IS NULL THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
                END IF;
                IF v_rec_interval < 1 OR v_rec_interval > 12 THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
                END IF;
            END IF;

            IF v_rec_start IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
            END IF;

            IF v_rec_end IS NOT NULL AND v_rec_end <= v_rec_start THEN
                RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
            END IF;

        END IF;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_date     = COALESCE(p_event_date,     event_date),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_date = COALESCE(p_event_end_date, event_end_date),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            updated_at     = now()
        WHERE event_id = v_target_parent_id;

        -- Children keep their own individual event_date (each occurrence's own day) —
        -- event_end_date is derived per-child as event_date + the series' day offset
        -- (end date minus start date) so a multi-day event keeps its duration on every
        -- occurrence, instead of every sibling getting the same absolute end date.
        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_date = CASE WHEN p_event_end_date IS NOT NULL OR p_event_end_time IS NOT NULL
                                   THEN event_date + (v_final_event_end_date - v_final_event_date)
                                   ELSE event_end_date END,
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            is_overridden  = false,
            updated_at     = now()
        WHERE parent_event_id = v_target_parent_id;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = v_target_parent_id;
            DELETE FROM event_platforms
            WHERE event_id IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id);
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), v_target_parent_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event updated successfully';

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: is_collaborative (v2.2 — now scope-aware, was always parent-level in v2.1)
    --
    -- scope='this' → applies only to the occurrence itself (p_event_id); every row already
    --                stores its own is_collaborative value and read SPs already read it
    --                directly (no fallback/COALESCE), so no schema or read-path change needed.
    -- scope='all'  → applies to the parent + all children, same as before.
    -- ══════════════════════════════════════════════════════════════════════════
    IF p_is_collaborative IS NOT NULL THEN
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET is_collaborative = p_is_collaborative,
                updated_at       = now()
            WHERE event_id = p_event_id;
        ELSE
            UPDATE event_mst
            SET is_collaborative = p_is_collaborative,
                updated_at       = now()
            WHERE event_id = v_target_parent_id
               OR parent_event_id = v_target_parent_id;
        END IF;
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule + regen (v2.3 — first-conversion reuses p_event_id
    -- as the series' first occurrence instead of duplicating it; event_recurring
    -- is upserted instead of only updated)
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_update_recurring THEN

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '3 months');
        v_rec_end  := v_safe_end;

        IF v_is_first_conversion THEN

            -- Create a new hidden template row to own the recurrence rule, so
            -- p_event_id can become a real (visible) occurrence instead of the
            -- series' excluded parent/template row.
            SELECT profile_id, title, description, event_date, event_time, event_end_date, event_end_time,
                   event_timezone, livestream, video, is_collaborative
            INTO v_profile_id, v_title, v_description, v_event_date, v_event_time, v_event_end_date, v_event_end_time,
                 v_event_tz, v_livestream, v_video, v_is_collaborative
            FROM event_mst WHERE event_id = v_target_parent_id;

            INSERT INTO event_mst (
                event_id, profile_id, parent_event_id, title, description,
                event_date, event_time, event_end_date, event_end_time, event_timezone,
                livestream, video, is_collaborative, is_recurring, created_at, updated_at
            )
            VALUES (
                gen_random_uuid(), v_profile_id, NULL, v_title, v_description,
                v_rec_start, v_event_time, v_rec_start + (v_event_end_date - v_event_date), v_event_end_time, v_event_tz,
                v_livestream, v_video, v_is_collaborative, true, now(), now()
            )
            RETURNING event_id INTO v_new_parent_id;

            -- Seed the template's platforms/collaborators from p_event_id (copy, not
            -- move) so siblings generated below — which fall back to
            -- COALESCE(parent_event_id, event_id) when not individually overridden —
            -- see what the user had already set, instead of it vanishing.
            INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
            SELECT gen_random_uuid(), v_new_parent_id, platform_id, stream_url, now()
            FROM event_platforms WHERE event_id = p_event_id;

            INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, responded_at, updated_at)
            SELECT gen_random_uuid(), v_new_parent_id, profile_id, invited_by, status, invited_at, responded_at, now()
            FROM event_collaborators WHERE event_id = p_event_id AND is_deleted = false;

            -- Re-point p_event_id at the new template — it becomes the first,
            -- already-visible occurrence of the series instead of being replaced.
            UPDATE event_mst
            SET parent_event_id = v_new_parent_id,
                is_recurring     = true,
                updated_at       = now()
            WHERE event_id = p_event_id;

            v_target_parent_id := v_new_parent_id;

            -- v_collab_target_id was resolved at step 6b against the OLD
            -- v_target_parent_id (p_event_id); re-point it so the collaborator
            -- sync section below (scope='all' only, since first conversion always
            -- runs as scope='all') writes to the new template like every other
            -- series-level field, instead of stranding invites on p_event_id where
            -- collaborators_overridden = false would never surface them.
            v_collab_target_id := v_new_parent_id;

        END IF;

        -- Upsert the recurrence rule — a plain UPDATE here silently no-ops on first
        -- conversion (no event_recurring row exists yet), leaving every occurrence's
        -- `recurring` field null.
        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end,
            renewal_notified_at  = NULL
        WHERE event_id = v_target_parent_id;

        IF NOT FOUND THEN
            INSERT INTO event_recurring (
                id, event_id, recurring_days, recurring_type,
                recurring_interval, recurring_start_date, recurring_end_date, created_at
            )
            VALUES (
                gen_random_uuid(), v_target_parent_id, v_rec_days, v_rec_type,
                v_rec_interval, v_rec_start, v_rec_end, now()
            );
        END IF;

        -- v2.4: p_event_id ALWAYS survives this regen, not just on first conversion —
        -- it's re-pointed at v_target_parent_id above on first conversion, or was
        -- already a child of an established series otherwise. Either way it must
        -- keep its own event_id so any per-occurrence platform/collaborator override
        -- on it (is_overridden/collaborators_overridden = true) isn't lost to a
        -- freshly generated replacement row for the same date. Prior versions
        -- (v2.2/v2.3) deleted every child unconditionally when editing an
        -- already-established series' rule, including p_event_id itself if it
        -- happened to be a child — silently wiping that occurrence's own platforms/
        -- collaborators (and giving it a brand-new event_id) on every such edit.
        -- Every OTHER sibling is still deleted and regenerated fresh, same as before.
        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id AND event_id != p_event_id;

        SELECT profile_id, title, description, event_date, event_time, event_end_date, event_end_time,
               event_timezone, livestream, video, is_collaborative
        INTO v_profile_id, v_title, v_description, v_event_date, v_event_time, v_event_end_date, v_event_end_time,
             v_event_tz, v_livestream, v_video, v_is_collaborative
        FROM event_mst WHERE event_id = v_target_parent_id;

        -- Day offset (end date minus start date) reapplied to every generated
        -- occurrence below so a multi-day recurring event keeps its duration.
        v_end_date_offset := v_event_end_date - v_event_date;

        -- The exact date p_event_id itself now occupies — never generate a
        -- duplicate occurrence for it, regardless of first-conversion status (v2.4).
        SELECT event_date INTO v_first_occ_date FROM event_mst WHERE event_id = p_event_id;

        IF v_rec_type = 'weekly' THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM v_rec_start)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := v_rec_start + v_days_ahead;
                v_occ_date   := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    IF v_first_occ_date IS NULL OR v_occ_date != v_first_occ_date THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_date, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_occ_date + v_end_date_offset, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_occ_date := v_occ_date + (7 * v_rec_interval);
                END LOOP;
            END LOOP;

        ELSIF v_rec_type IN ('first', 'last') THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_month_start := DATE_TRUNC('month', v_rec_start)::date;
                WHILE v_month_start <= v_safe_end LOOP
                    IF v_rec_type = 'first' THEN
                        v_days_ahead := (7 + v_dow_target - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date   := v_month_start + v_days_ahead;
                    ELSE
                        v_month_end     := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;
                    IF v_occ_date >= v_rec_start AND v_occ_date <= v_safe_end
                       AND (v_first_occ_date IS NULL OR v_occ_date != v_first_occ_date) THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_date, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_occ_date + v_end_date_offset, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;
            END LOOP;

        END IF;

    END IF;
    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: collaborator SYNC (v2.1 — scope-aware; v2.0 always synced the parent)
    --
    -- null            → skip entirely, don't touch collaborators
    -- []              → soft-delete ALL existing collaborators (at the resolved target)
    -- [id1, id2, ...] → soft-delete anyone NOT in list, invite anyone new (at the resolved target)
    --
    -- scope='this' → target is the occurrence itself (v_collab_target_id = p_event_id).
    --                event_collaborators rows are written against the CHILD's own event_id
    --                and event_mst.collaborators_overridden is flipped true on that child so
    --                read SPs know to use its own rows instead of the parent's.
    -- scope='all'  → target is the series parent (v_collab_target_id = v_target_parent_id,
    --                which v2.3 may have re-pointed at a freshly-created template on first
    --                conversion — see above), same as v2.0/v2.1/v2.2. Any prior
    --                per-occurrence overrides are discarded first so children go back to
    --                inheriting the series list.
    -- ══════════════════════════════════════════════════════════════════════════
    v_skipped_ids := ARRAY[]::uuid[];

    IF v_sync_collabs THEN

        -- Check is_collaborative before doing anything — read from whichever row collaborators
        -- are being synced against (the occurrence for scope='this', the parent for scope='all'),
        -- since is_collaborative is now scope-aware too (v2.2).
        v_effective_is_collab := COALESCE(
            p_is_collaborative,
            (SELECT is_collaborative FROM event_mst WHERE event_id = v_collab_target_id)
        );

        -- If turning off collaboration and passing ids, reject
        IF v_effective_is_collab = false
           AND COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN
            RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
        END IF;

        -- scope='all' → discard any per-occurrence collaborator overrides so children
        -- revert to inheriting the series list before the parent-level sync below.
        -- Soft-delete (is_deleted/deleted_at), matching every other collaborator removal
        -- in this function — event_collaborators has no hard-delete precedent anywhere.
        IF v_scope = 'all' THEN
            UPDATE event_collaborators
            SET is_deleted = true,
                deleted_at = now(),
                updated_at = now()
            WHERE event_id   IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id)
              AND is_deleted = false;

            UPDATE event_mst
            SET collaborators_overridden = false
            WHERE parent_event_id = v_target_parent_id;
        END IF;

        -- ── Step 1: Soft-delete collaborators NOT in the new list ─────────────
        -- Empty array = remove all; non-empty = remove only those absent from list
        UPDATE event_collaborators
        SET is_deleted = true,
            deleted_at = now(),
            updated_at = now()
        WHERE event_id   = v_collab_target_id
          AND is_deleted = false
          AND (
              COALESCE(array_length(p_collaborator_ids, 1), 0) = 0   -- [] → remove all
              OR profile_id != ALL(p_collaborator_ids)                 -- not in new list
          );

        -- ── Step 2: Invite/re-invite collaborators in the new list ────────────
        IF COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN

            SELECT cp.id
            INTO v_owner_profile_id
            FROM event_mst e
            JOIN creator_profiles cp ON cp.id = e.profile_id
            WHERE e.event_id = v_collab_target_id;

            -- Count accepted collaborators AFTER the removals above
            SELECT COUNT(*) INTO v_collab_count
            FROM event_collaborators
            WHERE event_id   = v_collab_target_id
              AND status     = 'accepted'
              AND is_deleted = false;

            FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

                IF v_collab_id IS NULL THEN CONTINUE; END IF;

                -- Skip the event owner
                IF v_collab_id = v_owner_profile_id THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Find existing row (active or previously soft-deleted). A profile can
                -- have BOTH an old soft-deleted row and a current active row for the
                -- same (event_id, profile_id) over time (that's how re-inviting after
                -- removal works) — ORDER BY is_deleted ASC guarantees the active row
                -- (is_deleted = false) is picked when one exists, instead of an
                -- arbitrary one. Without this, an unlucky pick of the soft-deleted row
                -- fell through to the re-invite branch below and tried to flip it back
                -- to active while a genuinely active row for that profile still
                -- existed — violating uq_event_collaborators_active.
                SELECT id, is_deleted
                INTO v_existing_collab_id, v_existing_deleted
                FROM event_collaborators
                WHERE event_id   = v_collab_target_id
                  AND profile_id = v_collab_id
                ORDER BY is_deleted ASC
                LIMIT 1;

                -- Already active → no change needed, skip
                IF v_existing_collab_id IS NOT NULL AND v_existing_deleted = false THEN
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Max 5 accepted collaborators
                IF v_collab_count >= 5 THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Validate the profile exists and is active
                SELECT user_id INTO v_invitee_user_id
                FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

                IF v_invitee_user_id IS NULL THEN
                    v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Re-invite (previously soft-deleted row exists)
                IF v_existing_collab_id IS NOT NULL THEN
                    UPDATE event_collaborators
                    SET status       = 'pending',
                        invited_by   = v_owner_profile_id,
                        invited_at   = now(),
                        responded_at = NULL,
                        updated_at   = now(),
                        is_deleted   = false,
                        deleted_at   = NULL
                    WHERE id = v_existing_collab_id;
                ELSE
                    -- New collaborator
                    INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, updated_at)
                    VALUES (gen_random_uuid(), v_collab_target_id, v_collab_id, v_owner_profile_id, 'pending', now(), now());
                END IF;

                -- v2.4: notification intentionally NOT sent on invite/re-invite —
                -- caller does not want a "Collaboration Invite" notification fired
                -- as a side effect of syncing the collaborator list via update_event.

                v_invitee_user_id    := NULL;
                v_existing_collab_id := NULL;

            END LOOP;

        END IF;

        -- scope='this' → mark this occurrence as having its own collaborator list
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET collaborators_overridden = true,
                updated_at               = now()
            WHERE event_id = p_event_id;
        END IF;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_success_message,
        'data', json_build_object(
            'skipped_collaborator_ids', v_skipped_ids
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```

---

## V2.4 Function (Previous)

```sql
-- Function: update_event_v2_4
-- Group: Events
-- Endpoint: POST /rpc/update_event_v2_4
-- Tables:   event_mst (UPDATE/INSERT/DELETE), event_platforms (DELETE+INSERT), event_recurring (UPDATE/INSERT/DELETE)
--           event_collaborators (INSERT/UPDATE/soft-delete)
-- Doc: docs/api/events/update_event.md
-- Version: 2.4 (2026-08-12)
--
-- Superseded by update_event_v2_5 (2026-08-20) — this version has no event_end_date
-- column and only rejects exact time-of-day equality between start/end time. Kept for
-- existing callers.
--
-- Change from v2.3 (3): Fixes data loss when editing an already-established recurring
--   series' rule (p_scope='all' + p_recurring_days=[...], not a first conversion).
--   v2.2/v2.3 deleted EVERY child occurrence unconditionally on this path, including
--   p_event_id itself if it happened to be a child — cascading away its own
--   event_platforms/event_collaborators rows and replacing it with a freshly generated
--   row under a brand-new event_id. p_event_id is now always excluded from that
--   delete-and-regenerate, so the occurrence actually being edited keeps its identity
--   and any per-occurrence platform/collaborator override on it. Every other sibling is
--   still deleted and regenerated fresh, unchanged from before.
--
-- Change from v2.3 (2): No "Collaboration Invite" notification is sent on invite/
--   re-invite anymore — the notifications INSERT that every prior version fired as
--   a side effect of syncing p_collaborator_ids has been removed. Inviting/removing
--   collaborators via update_event still works exactly the same otherwise; only the
--   notification side effect is gone.
--
-- Change from v2.3 (1): Adds the missing ability to un-recur an event.
--
--   Every prior version only ever acted on p_recurring_days when it was a non-empty
--   array (v_update_recurring). Passing null OR [] both fell through as "no rule
--   change" — there was no code path that could ever set is_recurring = false, so a
--   recurring event stayed recurring no matter what was sent to try to clear it.
--
--   Fix: p_recurring_days = [] (empty array, NOT null) is now the explicit "make this
--   event non-recurring" signal, matching the null/[] convention already used by
--   p_platforms and p_collaborator_ids elsewhere in this same function. null keeps
--   meaning "leave recurrence untouched".
--
--   Only valid with p_scope='all' — p_scope='this' + p_recurring_days=[] is rejected
--   with the same "use scope 'all'" error as changing/adding a rule. A no-op if the
--   event isn't currently part of a recurring series.
--
--   On removal: every sibling occurrence and the event_recurring rule row are deleted,
--   then p_event_id collapses back into a standalone event — if it was a child
--   occurrence it absorbs the series identity (parent_event_id = NULL, is_recurring =
--   false) and the now-orphaned hidden template row is deleted (the v2.3
--   first-conversion logic, run in reverse); if p_event_id was itself the hidden
--   template, is_recurring is simply flipped to false on it directly.
--
-- Change from v2.2: Fixes converting a non-recurring event into a recurring one.
--
--   Bug 1 — duplicate instead of reuse: when p_event_id had parent_event_id IS NULL
--   and was_recurring = false (i.e. a plain single event being made recurring for
--   the first time), v2.2 treated p_event_id itself as the series' parent/template
--   row and regenerated occurrences from scratch — including a brand-new row for
--   the same date as p_event_id. Since get_profile_events excludes
--   (is_recurring = true AND parent_event_id IS NULL) rows, p_event_id effectively
--   vanished from listings and was replaced by the freshly generated duplicate.
--   Fix: on first conversion, create a new hidden template row (parent_event_id = NULL)
--   to own the recurrence rule, re-point p_event_id at it (parent_event_id = new
--   template id, is_recurring = true) so p_event_id stays visible as the series'
--   first occurrence, and skip generating a duplicate for that same date.
--
--   Bug 2 — recurring always null: event_recurring was only ever UPDATEd, never
--   INSERTed, so first-time conversions left zero event_recurring rows for the
--   series — every occurrence read back "recurring": null. Fix: UPDATE, then
--   INSERT if no row was found (upsert).
--
--   The new hidden template also inherits p_event_id's platforms and already-active
--   collaborators (copied, not moved) since sibling occurrences with
--   is_overridden/collaborators_overridden = false fall back to
--   COALESCE(parent_event_id, event_id) for both.
--
--   Editing an already-established recurring series (parent_event_id already set,
--   or is_recurring already true) is unchanged from v2.2.
--
-- Change from v2.1: p_is_collaborative is now scope-aware
--   p_scope='this' → updates is_collaborative only on the occurrence itself (p_event_id).
--   p_scope='all' → updates the parent + all children, same as before.
--
-- Change from v2.0: Collaborator sync behavior
--   p_collaborator_ids: null        = don't touch existing collaborators
--   p_collaborator_ids: []          = remove ALL collaborators (soft delete)
--   p_collaborator_ids: [id1,id2]   = SYNC — keep id1/id2, remove anyone not in list, add new ones
--
-- p_scope: 'all' (default) = update parent + all occurrences
--          'this'          = per-occurrence scalar/platform/collaborator overrides
-- p_platforms:        null = don't touch | [] = clear all | [...] = replace
-- p_recurring_days:   null = no rule change | [] = REMOVE recurring ('all' scope only) | [...] = update + regen ('all' scope only)
-- p_is_collaborative: always parent-level (applied to parent + all children when set)
-- p_collaborator_ids: 'all' scope = series-level (parent) | 'this' scope = occurrence-level
--                     (see collaborators_overridden on event_mst)

CREATE OR REPLACE FUNCTION update_event_v2_4(
    p_event_id             uuid,
    p_user_id              uuid,
    p_scope                text     DEFAULT 'all',
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_event_end_time       time     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_is_collaborative     boolean  DEFAULT NULL,
    p_collaborator_ids     uuid[]   DEFAULT NULL,
    p_platforms            jsonb    DEFAULT NULL,
    -- Recurring fields
    p_recurring_days       text[]   DEFAULT NULL,
    p_recurring_type       text     DEFAULT NULL,
    p_recurring_interval   int      DEFAULT NULL,
    p_recurring_start_date date     DEFAULT NULL,
    p_recurring_end_date   date     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Intent flags
    v_scope             text;
    v_update_recurring  boolean;
    v_remove_recurring  boolean;
    v_currently_recurring boolean;
    v_sync_collabs      boolean;   -- true when p_collaborator_ids IS NOT NULL (including [])
    v_has_scalar        boolean;
    v_has_platforms     boolean;
    v_occurrence_change boolean;

    v_platform          jsonb;

    -- Parent resolution
    v_parent_event_id    uuid;
    v_target_parent_id   uuid;

    -- First-time recurring conversion (v2.3)
    v_was_recurring       boolean;
    v_is_first_conversion boolean;
    v_new_parent_id       uuid;
    v_first_occ_date      date;

    -- End-time validation
    v_existing_event_time     time;
    v_existing_event_end_time time;
    v_final_event_time        time;
    v_final_event_end_time    time;

    -- Recurring rule build-up
    v_rec_days      text[];
    v_rec_type      text;
    v_rec_interval  int;
    v_rec_start     date;
    v_rec_end       date;
    v_safe_end      date;

    -- Child generation
    v_profile_id         uuid;
    v_title              text;
    v_description        text;
    v_event_time         time;
    v_event_end_time     time;
    v_event_tz           text;
    v_livestream         boolean;
    v_video              boolean;
    v_is_collaborative   boolean;
    v_day_name           text;
    v_dow_target         int;
    v_dow_start          int;
    v_days_ahead         int;
    v_first_occ          date;
    v_occ_date           date;
    v_month_start        date;
    v_month_end          date;
    v_dow_month_end      int;

    -- Collaborator sync
    v_owner_profile_id   uuid;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;
    v_existing_collab_id uuid;
    v_existing_deleted   boolean;
    v_effective_is_collab boolean;
    v_collab_target_id   uuid;   -- event_id collaborator rows are keyed to (occurrence when scope='this', parent when scope='all')

    v_success_message    text;
BEGIN

    -- ── 1. Required params ────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── 2. Normalise scope ────────────────────────────────────────────────────
    v_scope := COALESCE(NULLIF(trim(p_scope), ''), 'all');
    IF v_scope NOT IN ('all', 'this') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be ''all'' or ''this''');
    END IF;

    -- ── 3. Intent flags ───────────────────────────────────────────────────────
    v_update_recurring := p_recurring_days IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) > 0;

    -- v2.4: p_recurring_days = [] (empty, non-null) is the explicit "remove recurring"
    -- signal — null still means "don't touch", matching p_platforms/p_collaborator_ids.
    v_remove_recurring := p_recurring_days IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) = 0;

    -- v2 change: sync triggers on ANY non-null value, including empty array
    v_sync_collabs := p_collaborator_ids IS NOT NULL;

    -- v2.1: 'this' scope syncs the occurrence's OWN collaborator rows (event_id = p_event_id);
    -- 'all' scope syncs the series' collaborator rows (event_id = v_target_parent_id), same as v2.0.
    -- Resolved after v_scope is demoted below (step 6), so recompute isn't needed until then.

    v_has_scalar := p_title          IS NOT NULL OR p_description   IS NOT NULL
                 OR p_event_date     IS NOT NULL OR p_event_time    IS NOT NULL
                 OR p_event_end_time IS NOT NULL OR p_timezone      IS NOT NULL
                 OR p_livestream     IS NOT NULL OR p_video         IS NOT NULL;
    v_has_platforms     := p_platforms IS NOT NULL;
    v_occurrence_change := v_has_scalar OR v_has_platforms;

    -- ── 4. Ownership check ───────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── 5. Resolve parent event ──────────────────────────────────────────────
    SELECT parent_event_id, is_recurring INTO v_parent_event_id, v_was_recurring
    FROM event_mst WHERE event_id = p_event_id;

    v_target_parent_id := COALESCE(v_parent_event_id, p_event_id);

    -- v2.3: true only when p_event_id is not, and was never, part of any recurring
    -- series — i.e. this call is the one converting it into one for the first time.
    v_is_first_conversion := v_parent_event_id IS NULL AND COALESCE(v_was_recurring, false) = false;

    -- v2.4: true when p_event_id is currently part of a recurring series in any way
    -- (a child occurrence, or the hidden template/parent itself).
    v_currently_recurring := v_parent_event_id IS NOT NULL OR COALESCE(v_was_recurring, false);

    -- ── 6. Demote 'this' to 'all' for non-recurring events ───────────────────
    IF v_scope = 'this' AND v_parent_event_id IS NULL THEN
        v_scope := 'all';
    END IF;

    -- ── 6b. Resolve collaborator sync target ─────────────────────────────────
    v_collab_target_id := CASE WHEN v_scope = 'this' THEN p_event_id ELSE v_target_parent_id END;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule REMOVAL (v2.4) — p_recurring_days: [] (empty, non-null)
    -- is the explicit "make non-recurring" signal, matching the null/[] convention
    -- already used by p_platforms and p_collaborator_ids. null keeps meaning "leave
    -- recurrence untouched" (no code path here fires for it).
    --
    -- A no-op if the event isn't currently part of a recurring series.
    --
    -- Runs BEFORE Branch A/B on purpose: once this collapses p_event_id's identity
    -- and deletes the old hidden template, v_target_parent_id/v_collab_target_id
    -- must already point at the surviving row (p_event_id) so the scalar/platform/
    -- collaborator writes below land on it instead of on a row that's about to be
    -- deleted. Doing this after Branch A/B (as first drafted) silently discarded
    -- whatever Branch A/B had just written to the old template — e.g. a p_platforms
    -- payload sent in the same call ended up inserted onto the template's event_id,
    -- which was then deleted here, leaving the surviving event with no platforms.
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_remove_recurring AND v_currently_recurring THEN

        -- Drop every sibling occurrence except the one being edited.
        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id AND event_id != p_event_id;

        -- Drop the recurrence rule itself.
        DELETE FROM event_recurring WHERE event_id = v_target_parent_id;

        IF v_parent_event_id IS NOT NULL THEN
            -- p_event_id was a visible child occurrence relying on
            -- COALESCE(parent_event_id, event_id) fallback to the template's own
            -- platforms/collaborators (when not individually overridden). That
            -- fallback breaks the instant parent_event_id is cleared below, so copy
            -- the template's rows onto p_event_id first — but only if p_event_id
            -- doesn't already have its own (an existing per-occurrence override
            -- must win, not be duplicated alongside a copy of the template's).
            INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
            SELECT gen_random_uuid(), p_event_id, platform_id, stream_url, now()
            FROM event_platforms
            WHERE event_id = v_target_parent_id
              AND NOT EXISTS (SELECT 1 FROM event_platforms WHERE event_id = p_event_id);

            INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, responded_at, updated_at)
            SELECT gen_random_uuid(), p_event_id, profile_id, invited_by, status, invited_at, responded_at, now()
            FROM event_collaborators
            WHERE event_id = v_target_parent_id AND is_deleted = false
              AND NOT EXISTS (SELECT 1 FROM event_collaborators WHERE event_id = p_event_id AND is_deleted = false);

            -- p_event_id was a visible child occurrence — absorb the series identity
            -- into it (mirrors the v2.3 first-conversion logic above, in reverse) and
            -- drop the now-empty hidden template row that used to own the rule.
            UPDATE event_mst
            SET parent_event_id = NULL,
                is_recurring     = false,
                updated_at       = now()
            WHERE event_id = p_event_id;

            DELETE FROM event_mst WHERE event_id = v_target_parent_id;

            -- Every write below (Branch A/B scalar+platform update, is_collaborative,
            -- collaborator sync) must now target the row that actually survives.
            v_collab_target_id := p_event_id;
        ELSE
            -- p_event_id WAS the hidden template/parent itself — its own row
            -- survives (and already owns its platforms/collaborators directly),
            -- just flip the flag.
            UPDATE event_mst
            SET is_recurring = false,
                updated_at   = now()
            WHERE event_id = p_event_id;
        END IF;

        v_target_parent_id := p_event_id;

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH A: scope = 'this'
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'this' THEN

        IF v_update_recurring OR v_remove_recurring THEN
            RETURN json_build_object('status', false, 'message',
                'Recurring schedule cannot be changed for a single occurrence — use scope ''all''');
        END IF;

        IF v_has_scalar THEN
            SELECT event_time, event_end_time
            INTO v_existing_event_time, v_existing_event_end_time
            FROM event_mst WHERE event_id = p_event_id;

            v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
            v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

            IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
                RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
            END IF;
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_occurrence_change THEN
            UPDATE event_mst
            SET title          = COALESCE(p_title,          title),
                description    = COALESCE(p_description,    description),
                event_date     = COALESCE(p_event_date,     event_date),
                event_time     = COALESCE(p_event_time,     event_time),
                event_end_time = COALESCE(p_event_end_time, event_end_time),
                event_timezone = COALESCE(p_timezone,       event_timezone),
                livestream     = COALESCE(p_livestream,     livestream),
                video          = COALESCE(p_video,          video),
                is_overridden  = true,
                updated_at     = now()
            WHERE event_id = p_event_id;
        END IF;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = p_event_id;
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), p_event_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event occurrence updated successfully';

    ELSE
    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH B: scope = 'all'
    -- ══════════════════════════════════════════════════════════════════════════

        SELECT event_time, event_end_time
        INTO v_existing_event_time, v_existing_event_end_time
        FROM event_mst WHERE event_id = v_target_parent_id;

        v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
        v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

        IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
            RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_update_recurring THEN

            IF EXISTS (
                SELECT 1 FROM unnest(p_recurring_days) AS d(day)
                WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
            END IF;

            SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
            INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
            FROM event_recurring WHERE event_id = v_target_parent_id;

            v_rec_days     := p_recurring_days;
            v_rec_type     := COALESCE(p_recurring_type,       v_rec_type);
            v_rec_start    := COALESCE(p_recurring_start_date, v_rec_start);
            v_rec_end      := COALESCE(p_recurring_end_date,   v_rec_end);

            IF v_rec_type IS NULL OR v_rec_type NOT IN ('weekly', 'first', 'last') THEN
                RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
            END IF;

            IF v_rec_type IN ('first', 'last') THEN
                v_rec_interval := NULL;
            ELSE
                v_rec_interval := COALESCE(p_recurring_interval, v_rec_interval);
                IF v_rec_interval IS NULL THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
                END IF;
                IF v_rec_interval < 1 OR v_rec_interval > 12 THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
                END IF;
            END IF;

            IF v_rec_start IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
            END IF;

            IF v_rec_end IS NOT NULL AND v_rec_end <= v_rec_start THEN
                RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
            END IF;

        END IF;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_date     = COALESCE(p_event_date,     event_date),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            updated_at     = now()
        WHERE event_id = v_target_parent_id;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            is_overridden  = false,
            updated_at     = now()
        WHERE parent_event_id = v_target_parent_id;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = v_target_parent_id;
            DELETE FROM event_platforms
            WHERE event_id IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id);
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), v_target_parent_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event updated successfully';

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: is_collaborative (v2.2 — now scope-aware, was always parent-level in v2.1)
    --
    -- scope='this' → applies only to the occurrence itself (p_event_id); every row already
    --                stores its own is_collaborative value and read SPs already read it
    --                directly (no fallback/COALESCE), so no schema or read-path change needed.
    -- scope='all'  → applies to the parent + all children, same as before.
    -- ══════════════════════════════════════════════════════════════════════════
    IF p_is_collaborative IS NOT NULL THEN
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET is_collaborative = p_is_collaborative,
                updated_at       = now()
            WHERE event_id = p_event_id;
        ELSE
            UPDATE event_mst
            SET is_collaborative = p_is_collaborative,
                updated_at       = now()
            WHERE event_id = v_target_parent_id
               OR parent_event_id = v_target_parent_id;
        END IF;
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule + regen (v2.3 — first-conversion reuses p_event_id
    -- as the series' first occurrence instead of duplicating it; event_recurring
    -- is upserted instead of only updated)
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_update_recurring THEN

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '3 months');
        v_rec_end  := v_safe_end;

        IF v_is_first_conversion THEN

            -- Create a new hidden template row to own the recurrence rule, so
            -- p_event_id can become a real (visible) occurrence instead of the
            -- series' excluded parent/template row.
            SELECT profile_id, title, description, event_time, event_end_time,
                   event_timezone, livestream, video, is_collaborative
            INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
                 v_event_tz, v_livestream, v_video, v_is_collaborative
            FROM event_mst WHERE event_id = v_target_parent_id;

            INSERT INTO event_mst (
                event_id, profile_id, parent_event_id, title, description,
                event_date, event_time, event_end_time, event_timezone,
                livestream, video, is_collaborative, is_recurring, created_at, updated_at
            )
            VALUES (
                gen_random_uuid(), v_profile_id, NULL, v_title, v_description,
                v_rec_start, v_event_time, v_event_end_time, v_event_tz,
                v_livestream, v_video, v_is_collaborative, true, now(), now()
            )
            RETURNING event_id INTO v_new_parent_id;

            -- Seed the template's platforms/collaborators from p_event_id (copy, not
            -- move) so siblings generated below — which fall back to
            -- COALESCE(parent_event_id, event_id) when not individually overridden —
            -- see what the user had already set, instead of it vanishing.
            INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
            SELECT gen_random_uuid(), v_new_parent_id, platform_id, stream_url, now()
            FROM event_platforms WHERE event_id = p_event_id;

            INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, responded_at, updated_at)
            SELECT gen_random_uuid(), v_new_parent_id, profile_id, invited_by, status, invited_at, responded_at, now()
            FROM event_collaborators WHERE event_id = p_event_id AND is_deleted = false;

            -- Re-point p_event_id at the new template — it becomes the first,
            -- already-visible occurrence of the series instead of being replaced.
            UPDATE event_mst
            SET parent_event_id = v_new_parent_id,
                is_recurring     = true,
                updated_at       = now()
            WHERE event_id = p_event_id;

            v_target_parent_id := v_new_parent_id;

            -- v_collab_target_id was resolved at step 6b against the OLD
            -- v_target_parent_id (p_event_id); re-point it so the collaborator
            -- sync section below (scope='all' only, since first conversion always
            -- runs as scope='all') writes to the new template like every other
            -- series-level field, instead of stranding invites on p_event_id where
            -- collaborators_overridden = false would never surface them.
            v_collab_target_id := v_new_parent_id;

        END IF;

        -- Upsert the recurrence rule — a plain UPDATE here silently no-ops on first
        -- conversion (no event_recurring row exists yet), leaving every occurrence's
        -- `recurring` field null.
        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end,
            renewal_notified_at  = NULL
        WHERE event_id = v_target_parent_id;

        IF NOT FOUND THEN
            INSERT INTO event_recurring (
                id, event_id, recurring_days, recurring_type,
                recurring_interval, recurring_start_date, recurring_end_date, created_at
            )
            VALUES (
                gen_random_uuid(), v_target_parent_id, v_rec_days, v_rec_type,
                v_rec_interval, v_rec_start, v_rec_end, now()
            );
        END IF;

        -- v2.4: p_event_id ALWAYS survives this regen, not just on first conversion —
        -- it's re-pointed at v_target_parent_id above on first conversion, or was
        -- already a child of an established series otherwise. Either way it must
        -- keep its own event_id so any per-occurrence platform/collaborator override
        -- on it (is_overridden/collaborators_overridden = true) isn't lost to a
        -- freshly generated replacement row for the same date. Prior versions
        -- (v2.2/v2.3) deleted every child unconditionally when editing an
        -- already-established series' rule, including p_event_id itself if it
        -- happened to be a child — silently wiping that occurrence's own platforms/
        -- collaborators (and giving it a brand-new event_id) on every such edit.
        -- Every OTHER sibling is still deleted and regenerated fresh, same as before.
        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id AND event_id != p_event_id;

        SELECT profile_id, title, description, event_time, event_end_time,
               event_timezone, livestream, video, is_collaborative
        INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
             v_event_tz, v_livestream, v_video, v_is_collaborative
        FROM event_mst WHERE event_id = v_target_parent_id;

        -- The exact date p_event_id itself now occupies — never generate a
        -- duplicate occurrence for it, regardless of first-conversion status (v2.4).
        SELECT event_date INTO v_first_occ_date FROM event_mst WHERE event_id = p_event_id;

        IF v_rec_type = 'weekly' THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM v_rec_start)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := v_rec_start + v_days_ahead;
                v_occ_date   := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    IF v_first_occ_date IS NULL OR v_occ_date != v_first_occ_date THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_occ_date := v_occ_date + (7 * v_rec_interval);
                END LOOP;
            END LOOP;

        ELSIF v_rec_type IN ('first', 'last') THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_month_start := DATE_TRUNC('month', v_rec_start)::date;
                WHILE v_month_start <= v_safe_end LOOP
                    IF v_rec_type = 'first' THEN
                        v_days_ahead := (7 + v_dow_target - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date   := v_month_start + v_days_ahead;
                    ELSE
                        v_month_end     := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;
                    IF v_occ_date >= v_rec_start AND v_occ_date <= v_safe_end
                       AND (v_first_occ_date IS NULL OR v_occ_date != v_first_occ_date) THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;
            END LOOP;

        END IF;

    END IF;
    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: collaborator SYNC (v2.1 — scope-aware; v2.0 always synced the parent)
    --
    -- null            → skip entirely, don't touch collaborators
    -- []              → soft-delete ALL existing collaborators (at the resolved target)
    -- [id1, id2, ...] → soft-delete anyone NOT in list, invite anyone new (at the resolved target)
    --
    -- scope='this' → target is the occurrence itself (v_collab_target_id = p_event_id).
    --                event_collaborators rows are written against the CHILD's own event_id
    --                and event_mst.collaborators_overridden is flipped true on that child so
    --                read SPs know to use its own rows instead of the parent's.
    -- scope='all'  → target is the series parent (v_collab_target_id = v_target_parent_id,
    --                which v2.3 may have re-pointed at a freshly-created template on first
    --                conversion — see above), same as v2.0/v2.1/v2.2. Any prior
    --                per-occurrence overrides are discarded first so children go back to
    --                inheriting the series list.
    -- ══════════════════════════════════════════════════════════════════════════
    v_skipped_ids := ARRAY[]::uuid[];

    IF v_sync_collabs THEN

        -- Check is_collaborative before doing anything — read from whichever row collaborators
        -- are being synced against (the occurrence for scope='this', the parent for scope='all'),
        -- since is_collaborative is now scope-aware too (v2.2).
        v_effective_is_collab := COALESCE(
            p_is_collaborative,
            (SELECT is_collaborative FROM event_mst WHERE event_id = v_collab_target_id)
        );

        -- If turning off collaboration and passing ids, reject
        IF v_effective_is_collab = false
           AND COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN
            RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
        END IF;

        -- scope='all' → discard any per-occurrence collaborator overrides so children
        -- revert to inheriting the series list before the parent-level sync below.
        -- Soft-delete (is_deleted/deleted_at), matching every other collaborator removal
        -- in this function — event_collaborators has no hard-delete precedent anywhere.
        IF v_scope = 'all' THEN
            UPDATE event_collaborators
            SET is_deleted = true,
                deleted_at = now(),
                updated_at = now()
            WHERE event_id   IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id)
              AND is_deleted = false;

            UPDATE event_mst
            SET collaborators_overridden = false
            WHERE parent_event_id = v_target_parent_id;
        END IF;

        -- ── Step 1: Soft-delete collaborators NOT in the new list ─────────────
        -- Empty array = remove all; non-empty = remove only those absent from list
        UPDATE event_collaborators
        SET is_deleted = true,
            deleted_at = now(),
            updated_at = now()
        WHERE event_id   = v_collab_target_id
          AND is_deleted = false
          AND (
              COALESCE(array_length(p_collaborator_ids, 1), 0) = 0   -- [] → remove all
              OR profile_id != ALL(p_collaborator_ids)                 -- not in new list
          );

        -- ── Step 2: Invite/re-invite collaborators in the new list ────────────
        IF COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN

            SELECT cp.id
            INTO v_owner_profile_id
            FROM event_mst e
            JOIN creator_profiles cp ON cp.id = e.profile_id
            WHERE e.event_id = v_collab_target_id;

            -- Count accepted collaborators AFTER the removals above
            SELECT COUNT(*) INTO v_collab_count
            FROM event_collaborators
            WHERE event_id   = v_collab_target_id
              AND status     = 'accepted'
              AND is_deleted = false;

            FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

                IF v_collab_id IS NULL THEN CONTINUE; END IF;

                -- Skip the event owner
                IF v_collab_id = v_owner_profile_id THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Find existing row (active or previously soft-deleted). A profile can
                -- have BOTH an old soft-deleted row and a current active row for the
                -- same (event_id, profile_id) over time (that's how re-inviting after
                -- removal works) — ORDER BY is_deleted ASC guarantees the active row
                -- (is_deleted = false) is picked when one exists, instead of an
                -- arbitrary one. Without this, an unlucky pick of the soft-deleted row
                -- fell through to the re-invite branch below and tried to flip it back
                -- to active while a genuinely active row for that profile still
                -- existed — violating uq_event_collaborators_active.
                SELECT id, is_deleted
                INTO v_existing_collab_id, v_existing_deleted
                FROM event_collaborators
                WHERE event_id   = v_collab_target_id
                  AND profile_id = v_collab_id
                ORDER BY is_deleted ASC
                LIMIT 1;

                -- Already active → no change needed, skip
                IF v_existing_collab_id IS NOT NULL AND v_existing_deleted = false THEN
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Max 5 accepted collaborators
                IF v_collab_count >= 5 THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Validate the profile exists and is active
                SELECT user_id INTO v_invitee_user_id
                FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

                IF v_invitee_user_id IS NULL THEN
                    v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Re-invite (previously soft-deleted row exists)
                IF v_existing_collab_id IS NOT NULL THEN
                    UPDATE event_collaborators
                    SET status       = 'pending',
                        invited_by   = v_owner_profile_id,
                        invited_at   = now(),
                        responded_at = NULL,
                        updated_at   = now(),
                        is_deleted   = false,
                        deleted_at   = NULL
                    WHERE id = v_existing_collab_id;
                ELSE
                    -- New collaborator
                    INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, updated_at)
                    VALUES (gen_random_uuid(), v_collab_target_id, v_collab_id, v_owner_profile_id, 'pending', now(), now());
                END IF;

                -- v2.4: notification intentionally NOT sent on invite/re-invite —
                -- caller does not want a "Collaboration Invite" notification fired
                -- as a side effect of syncing the collaborator list via update_event.

                v_invitee_user_id    := NULL;
                v_existing_collab_id := NULL;

            END LOOP;

        END IF;

        -- scope='this' → mark this occurrence as having its own collaborator list
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET collaborators_overridden = true,
                updated_at               = now()
            WHERE event_id = p_event_id;
        END IF;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_success_message,
        'data', json_build_object(
            'skipped_collaborator_ids', v_skipped_ids
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```

---

## V2.3 Function (Previous)

```sql
-- Function: update_event_v2_3
-- Group: Events
-- Endpoint: POST /rpc/update_event_v2_3
-- Tables:   event_mst (UPDATE/INSERT), event_platforms (DELETE+INSERT), event_recurring (UPDATE or INSERT)
--           event_collaborators (INSERT/UPDATE/soft-delete), notifications (INSERT if collaborative)
-- Doc: docs/api/events/update_event.md
-- Version: 2.3 (2026-08-11)
--
-- Change from v2.2: Fixes converting a non-recurring event into a recurring one.
--
--   Bug 1 — duplicate instead of reuse: when p_event_id had parent_event_id IS NULL
--   and was_recurring = false (i.e. a plain single event being made recurring for
--   the first time), v2.2 treated p_event_id itself as the series' parent/template
--   row and regenerated occurrences from scratch — including a brand-new row for
--   the same date as p_event_id. Since get_profile_events excludes
--   (is_recurring = true AND parent_event_id IS NULL) rows, p_event_id effectively
--   vanished from listings and was replaced by the freshly generated duplicate.
--   Fix: on first conversion, create a new hidden template row (parent_event_id = NULL)
--   to own the recurrence rule, re-point p_event_id at it (parent_event_id = new
--   template id, is_recurring = true) so p_event_id stays visible as the series'
--   first occurrence, and skip generating a duplicate for that same date.
--
--   Bug 2 — recurring always null: event_recurring was only ever UPDATEd, never
--   INSERTed, so first-time conversions left zero event_recurring rows for the
--   series — every occurrence read back "recurring": null. Fix: UPDATE, then
--   INSERT if no row was found (upsert).
--
--   The new hidden template also inherits p_event_id's platforms and already-active
--   collaborators (copied, not moved) since sibling occurrences with
--   is_overridden/collaborators_overridden = false fall back to
--   COALESCE(parent_event_id, event_id) for both.
--
--   Editing an already-established recurring series (parent_event_id already set,
--   or is_recurring already true) is unchanged from v2.2.
--
-- Change from v2.1: p_is_collaborative is now scope-aware
--   p_scope='this' → updates is_collaborative only on the occurrence itself (p_event_id).
--   p_scope='all' → updates the parent + all children, same as before.
--
-- Change from v2.0: Collaborator sync behavior
--   p_collaborator_ids: null        = don't touch existing collaborators
--   p_collaborator_ids: []          = remove ALL collaborators (soft delete)
--   p_collaborator_ids: [id1,id2]   = SYNC — keep id1/id2, remove anyone not in list, add new ones
--
-- p_scope: 'all' (default) = update parent + all occurrences
--          'this'          = per-occurrence scalar/platform/collaborator overrides
-- p_platforms:        null = don't touch | [] = clear all | [...] = replace
-- p_recurring_days:   null or [] = no rule change | [...] = update + regen ('all' scope only)
-- p_is_collaborative: always parent-level (applied to parent + all children when set)
-- p_collaborator_ids: 'all' scope = series-level (parent) | 'this' scope = occurrence-level
--                     (see collaborators_overridden on event_mst)
--
-- DEPLOYMENT — this is a NEW function name (update_event_v2_3), no overload to drop.
-- Old callers on update_event_v2_2 keep working unchanged (see "V2.2 Function (Previous)" below).
-- Point the client at /rpc/update_event_v2_3 once deployed, then:
--   NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION update_event_v2_3(
    p_event_id             uuid,
    p_user_id              uuid,
    p_scope                text     DEFAULT 'all',
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_event_end_time       time     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_is_collaborative     boolean  DEFAULT NULL,
    p_collaborator_ids     uuid[]   DEFAULT NULL,
    p_platforms            jsonb    DEFAULT NULL,
    -- Recurring fields
    p_recurring_days       text[]   DEFAULT NULL,
    p_recurring_type       text     DEFAULT NULL,
    p_recurring_interval   int      DEFAULT NULL,
    p_recurring_start_date date     DEFAULT NULL,
    p_recurring_end_date   date     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Intent flags
    v_scope             text;
    v_update_recurring  boolean;
    v_sync_collabs      boolean;   -- true when p_collaborator_ids IS NOT NULL (including [])
    v_has_scalar        boolean;
    v_has_platforms     boolean;
    v_occurrence_change boolean;

    v_platform          jsonb;

    -- Parent resolution
    v_parent_event_id    uuid;
    v_target_parent_id   uuid;

    -- First-time recurring conversion (v2.3)
    v_was_recurring       boolean;
    v_is_first_conversion boolean;
    v_new_parent_id       uuid;
    v_first_occ_date      date;

    -- End-time validation
    v_existing_event_time     time;
    v_existing_event_end_time time;
    v_final_event_time        time;
    v_final_event_end_time    time;

    -- Recurring rule build-up
    v_rec_days      text[];
    v_rec_type      text;
    v_rec_interval  int;
    v_rec_start     date;
    v_rec_end       date;
    v_safe_end      date;

    -- Child generation
    v_profile_id         uuid;
    v_title              text;
    v_description        text;
    v_event_time         time;
    v_event_end_time     time;
    v_event_tz           text;
    v_livestream         boolean;
    v_video              boolean;
    v_is_collaborative   boolean;
    v_day_name           text;
    v_dow_target         int;
    v_dow_start          int;
    v_days_ahead         int;
    v_first_occ          date;
    v_occ_date           date;
    v_month_start        date;
    v_month_end          date;
    v_dow_month_end      int;

    -- Collaborator sync
    v_owner_profile_id   uuid;
    v_owner_name         text;
    v_event_title        text;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;
    v_existing_collab_id uuid;
    v_existing_deleted   boolean;
    v_effective_is_collab boolean;
    v_collab_target_id   uuid;   -- event_id collaborator rows are keyed to (occurrence when scope='this', parent when scope='all')

    v_success_message    text;
BEGIN

    -- ── 1. Required params ────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── 2. Normalise scope ────────────────────────────────────────────────────
    v_scope := COALESCE(NULLIF(trim(p_scope), ''), 'all');
    IF v_scope NOT IN ('all', 'this') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be ''all'' or ''this''');
    END IF;

    -- ── 3. Intent flags ───────────────────────────────────────────────────────
    v_update_recurring := p_recurring_days IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) > 0;

    -- v2 change: sync triggers on ANY non-null value, including empty array
    v_sync_collabs := p_collaborator_ids IS NOT NULL;

    -- v2.1: 'this' scope syncs the occurrence's OWN collaborator rows (event_id = p_event_id);
    -- 'all' scope syncs the series' collaborator rows (event_id = v_target_parent_id), same as v2.0.
    -- Resolved after v_scope is demoted below (step 6), so recompute isn't needed until then.

    v_has_scalar := p_title          IS NOT NULL OR p_description   IS NOT NULL
                 OR p_event_date     IS NOT NULL OR p_event_time    IS NOT NULL
                 OR p_event_end_time IS NOT NULL OR p_timezone      IS NOT NULL
                 OR p_livestream     IS NOT NULL OR p_video         IS NOT NULL;
    v_has_platforms     := p_platforms IS NOT NULL;
    v_occurrence_change := v_has_scalar OR v_has_platforms;

    -- ── 4. Ownership check ───────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── 5. Resolve parent event ──────────────────────────────────────────────
    SELECT parent_event_id, is_recurring INTO v_parent_event_id, v_was_recurring
    FROM event_mst WHERE event_id = p_event_id;

    v_target_parent_id := COALESCE(v_parent_event_id, p_event_id);

    -- v2.3: true only when p_event_id is not, and was never, part of any recurring
    -- series — i.e. this call is the one converting it into one for the first time.
    v_is_first_conversion := v_parent_event_id IS NULL AND COALESCE(v_was_recurring, false) = false;

    -- ── 6. Demote 'this' to 'all' for non-recurring events ───────────────────
    IF v_scope = 'this' AND v_parent_event_id IS NULL THEN
        v_scope := 'all';
    END IF;

    -- ── 6b. Resolve collaborator sync target ─────────────────────────────────
    v_collab_target_id := CASE WHEN v_scope = 'this' THEN p_event_id ELSE v_target_parent_id END;

    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH A: scope = 'this'
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'this' THEN

        IF v_update_recurring THEN
            RETURN json_build_object('status', false, 'message',
                'Recurring schedule cannot be changed for a single occurrence — use scope ''all''');
        END IF;

        IF v_has_scalar THEN
            SELECT event_time, event_end_time
            INTO v_existing_event_time, v_existing_event_end_time
            FROM event_mst WHERE event_id = p_event_id;

            v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
            v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

            IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
                RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
            END IF;
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_occurrence_change THEN
            UPDATE event_mst
            SET title          = COALESCE(p_title,          title),
                description    = COALESCE(p_description,    description),
                event_date     = COALESCE(p_event_date,     event_date),
                event_time     = COALESCE(p_event_time,     event_time),
                event_end_time = COALESCE(p_event_end_time, event_end_time),
                event_timezone = COALESCE(p_timezone,       event_timezone),
                livestream     = COALESCE(p_livestream,     livestream),
                video          = COALESCE(p_video,          video),
                is_overridden  = true,
                updated_at     = now()
            WHERE event_id = p_event_id;
        END IF;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = p_event_id;
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), p_event_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event occurrence updated successfully';

    ELSE
    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH B: scope = 'all'
    -- ══════════════════════════════════════════════════════════════════════════

        SELECT event_time, event_end_time
        INTO v_existing_event_time, v_existing_event_end_time
        FROM event_mst WHERE event_id = v_target_parent_id;

        v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
        v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

        IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
            RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_update_recurring THEN

            IF EXISTS (
                SELECT 1 FROM unnest(p_recurring_days) AS d(day)
                WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
            END IF;

            SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
            INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
            FROM event_recurring WHERE event_id = v_target_parent_id;

            v_rec_days     := p_recurring_days;
            v_rec_type     := COALESCE(p_recurring_type,       v_rec_type);
            v_rec_start    := COALESCE(p_recurring_start_date, v_rec_start);
            v_rec_end      := COALESCE(p_recurring_end_date,   v_rec_end);

            IF v_rec_type IS NULL OR v_rec_type NOT IN ('weekly', 'first', 'last') THEN
                RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
            END IF;

            IF v_rec_type IN ('first', 'last') THEN
                v_rec_interval := NULL;
            ELSE
                v_rec_interval := COALESCE(p_recurring_interval, v_rec_interval);
                IF v_rec_interval IS NULL THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
                END IF;
                IF v_rec_interval < 1 OR v_rec_interval > 12 THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
                END IF;
            END IF;

            IF v_rec_start IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
            END IF;

            IF v_rec_end IS NOT NULL AND v_rec_end <= v_rec_start THEN
                RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
            END IF;

        END IF;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_date     = COALESCE(p_event_date,     event_date),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            updated_at     = now()
        WHERE event_id = v_target_parent_id;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            is_overridden  = false,
            updated_at     = now()
        WHERE parent_event_id = v_target_parent_id;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = v_target_parent_id;
            DELETE FROM event_platforms
            WHERE event_id IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id);
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), v_target_parent_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event updated successfully';

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: is_collaborative (v2.2 — now scope-aware, was always parent-level in v2.1)
    --
    -- scope='this' → applies only to the occurrence itself (p_event_id); every row already
    --                stores its own is_collaborative value and read SPs already read it
    --                directly (no fallback/COALESCE), so no schema or read-path change needed.
    -- scope='all'  → applies to the parent + all children, same as before.
    -- ══════════════════════════════════════════════════════════════════════════
    IF p_is_collaborative IS NOT NULL THEN
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET is_collaborative = p_is_collaborative,
                updated_at       = now()
            WHERE event_id = p_event_id;
        ELSE
            UPDATE event_mst
            SET is_collaborative = p_is_collaborative,
                updated_at       = now()
            WHERE event_id = v_target_parent_id
               OR parent_event_id = v_target_parent_id;
        END IF;
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule + regen (v2.3 — first-conversion reuses p_event_id
    -- as the series' first occurrence instead of duplicating it; event_recurring
    -- is upserted instead of only updated)
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_update_recurring THEN

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '3 months');
        v_rec_end  := v_safe_end;

        IF v_is_first_conversion THEN

            -- Create a new hidden template row to own the recurrence rule, so
            -- p_event_id can become a real (visible) occurrence instead of the
            -- series' excluded parent/template row.
            SELECT profile_id, title, description, event_time, event_end_time,
                   event_timezone, livestream, video, is_collaborative
            INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
                 v_event_tz, v_livestream, v_video, v_is_collaborative
            FROM event_mst WHERE event_id = v_target_parent_id;

            INSERT INTO event_mst (
                event_id, profile_id, parent_event_id, title, description,
                event_date, event_time, event_end_time, event_timezone,
                livestream, video, is_collaborative, is_recurring, created_at, updated_at
            )
            VALUES (
                gen_random_uuid(), v_profile_id, NULL, v_title, v_description,
                v_rec_start, v_event_time, v_event_end_time, v_event_tz,
                v_livestream, v_video, v_is_collaborative, true, now(), now()
            )
            RETURNING event_id INTO v_new_parent_id;

            -- Seed the template's platforms/collaborators from p_event_id (copy, not
            -- move) so siblings generated below — which fall back to
            -- COALESCE(parent_event_id, event_id) when not individually overridden —
            -- see what the user had already set, instead of it vanishing.
            INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
            SELECT gen_random_uuid(), v_new_parent_id, platform_id, stream_url, now()
            FROM event_platforms WHERE event_id = p_event_id;

            INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, responded_at, updated_at)
            SELECT gen_random_uuid(), v_new_parent_id, profile_id, invited_by, status, invited_at, responded_at, now()
            FROM event_collaborators WHERE event_id = p_event_id AND is_deleted = false;

            -- Re-point p_event_id at the new template — it becomes the first,
            -- already-visible occurrence of the series instead of being replaced.
            UPDATE event_mst
            SET parent_event_id = v_new_parent_id,
                is_recurring     = true,
                updated_at       = now()
            WHERE event_id = p_event_id;

            v_target_parent_id := v_new_parent_id;

            -- v_collab_target_id was resolved at step 6b against the OLD
            -- v_target_parent_id (p_event_id); re-point it so the collaborator
            -- sync section below (scope='all' only, since first conversion always
            -- runs as scope='all') writes to the new template like every other
            -- series-level field, instead of stranding invites on p_event_id where
            -- collaborators_overridden = false would never surface them.
            v_collab_target_id := v_new_parent_id;

        END IF;

        -- Upsert the recurrence rule — a plain UPDATE here silently no-ops on first
        -- conversion (no event_recurring row exists yet), leaving every occurrence's
        -- `recurring` field null.
        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end,
            renewal_notified_at  = NULL
        WHERE event_id = v_target_parent_id;

        IF NOT FOUND THEN
            INSERT INTO event_recurring (
                id, event_id, recurring_days, recurring_type,
                recurring_interval, recurring_start_date, recurring_end_date, created_at
            )
            VALUES (
                gen_random_uuid(), v_target_parent_id, v_rec_days, v_rec_type,
                v_rec_interval, v_rec_start, v_rec_end, now()
            );
        END IF;

        -- On first conversion, p_event_id was just re-pointed at v_target_parent_id
        -- above and must survive this regen (that's the whole fix) — everything else
        -- under the template gets deleted and regenerated. For an already-established
        -- series this is unchanged from v2.2: every child (including one referenced by
        -- p_event_id, if it happened to be a child) is deleted and regenerated fresh.
        IF v_is_first_conversion THEN
            DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id AND event_id != p_event_id;
        ELSE
            DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id;
        END IF;

        SELECT profile_id, title, description, event_time, event_end_time,
               event_timezone, livestream, video, is_collaborative
        INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
             v_event_tz, v_livestream, v_video, v_is_collaborative
        FROM event_mst WHERE event_id = v_target_parent_id;

        -- The exact date p_event_id itself now occupies — skip generating a
        -- duplicate occurrence for it on first conversion.
        v_first_occ_date := NULL;
        IF v_is_first_conversion THEN
            SELECT event_date INTO v_first_occ_date FROM event_mst WHERE event_id = p_event_id;
        END IF;

        IF v_rec_type = 'weekly' THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM v_rec_start)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := v_rec_start + v_days_ahead;
                v_occ_date   := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    IF v_first_occ_date IS NULL OR v_occ_date != v_first_occ_date THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_occ_date := v_occ_date + (7 * v_rec_interval);
                END LOOP;
            END LOOP;

        ELSIF v_rec_type IN ('first', 'last') THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_month_start := DATE_TRUNC('month', v_rec_start)::date;
                WHILE v_month_start <= v_safe_end LOOP
                    IF v_rec_type = 'first' THEN
                        v_days_ahead := (7 + v_dow_target - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date   := v_month_start + v_days_ahead;
                    ELSE
                        v_month_end     := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;
                    IF v_occ_date >= v_rec_start AND v_occ_date <= v_safe_end
                       AND (v_first_occ_date IS NULL OR v_occ_date != v_first_occ_date) THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;
            END LOOP;

        END IF;

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: collaborator SYNC (v2.1 — scope-aware; v2.0 always synced the parent)
    --
    -- null            → skip entirely, don't touch collaborators
    -- []              → soft-delete ALL existing collaborators (at the resolved target)
    -- [id1, id2, ...] → soft-delete anyone NOT in list, invite anyone new (at the resolved target)
    --
    -- scope='this' → target is the occurrence itself (v_collab_target_id = p_event_id).
    --                event_collaborators rows are written against the CHILD's own event_id
    --                and event_mst.collaborators_overridden is flipped true on that child so
    --                read SPs know to use its own rows instead of the parent's.
    -- scope='all'  → target is the series parent (v_collab_target_id = v_target_parent_id,
    --                which v2.3 may have re-pointed at a freshly-created template on first
    --                conversion — see above), same as v2.0/v2.1/v2.2. Any prior
    --                per-occurrence overrides are discarded first so children go back to
    --                inheriting the series list.
    -- ══════════════════════════════════════════════════════════════════════════
    v_skipped_ids := ARRAY[]::uuid[];

    IF v_sync_collabs THEN

        -- Check is_collaborative before doing anything — read from whichever row collaborators
        -- are being synced against (the occurrence for scope='this', the parent for scope='all'),
        -- since is_collaborative is now scope-aware too (v2.2).
        v_effective_is_collab := COALESCE(
            p_is_collaborative,
            (SELECT is_collaborative FROM event_mst WHERE event_id = v_collab_target_id)
        );

        -- If turning off collaboration and passing ids, reject
        IF v_effective_is_collab = false
           AND COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN
            RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
        END IF;

        -- scope='all' → discard any per-occurrence collaborator overrides so children
        -- revert to inheriting the series list before the parent-level sync below.
        -- Soft-delete (is_deleted/deleted_at), matching every other collaborator removal
        -- in this function — event_collaborators has no hard-delete precedent anywhere.
        IF v_scope = 'all' THEN
            UPDATE event_collaborators
            SET is_deleted = true,
                deleted_at = now(),
                updated_at = now()
            WHERE event_id   IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id)
              AND is_deleted = false;

            UPDATE event_mst
            SET collaborators_overridden = false
            WHERE parent_event_id = v_target_parent_id;
        END IF;

        -- ── Step 1: Soft-delete collaborators NOT in the new list ─────────────
        -- Empty array = remove all; non-empty = remove only those absent from list
        UPDATE event_collaborators
        SET is_deleted = true,
            deleted_at = now(),
            updated_at = now()
        WHERE event_id   = v_collab_target_id
          AND is_deleted = false
          AND (
              COALESCE(array_length(p_collaborator_ids, 1), 0) = 0   -- [] → remove all
              OR profile_id != ALL(p_collaborator_ids)                 -- not in new list
          );

        -- ── Step 2: Invite/re-invite collaborators in the new list ────────────
        IF COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN

            SELECT cp.id, cp.profile_name, e.title
            INTO v_owner_profile_id, v_owner_name, v_event_title
            FROM event_mst e
            JOIN creator_profiles cp ON cp.id = e.profile_id
            WHERE e.event_id = v_collab_target_id;

            -- Count accepted collaborators AFTER the removals above
            SELECT COUNT(*) INTO v_collab_count
            FROM event_collaborators
            WHERE event_id   = v_collab_target_id
              AND status     = 'accepted'
              AND is_deleted = false;

            FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

                IF v_collab_id IS NULL THEN CONTINUE; END IF;

                -- Skip the event owner
                IF v_collab_id = v_owner_profile_id THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Find existing row (active or previously soft-deleted)
                SELECT id, is_deleted
                INTO v_existing_collab_id, v_existing_deleted
                FROM event_collaborators
                WHERE event_id   = v_collab_target_id
                  AND profile_id = v_collab_id
                LIMIT 1;

                -- Already active → no change needed, skip
                IF v_existing_collab_id IS NOT NULL AND v_existing_deleted = false THEN
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Max 5 accepted collaborators
                IF v_collab_count >= 5 THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Validate the profile exists and is active
                SELECT user_id INTO v_invitee_user_id
                FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

                IF v_invitee_user_id IS NULL THEN
                    v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Re-invite (previously soft-deleted row exists)
                IF v_existing_collab_id IS NOT NULL THEN
                    UPDATE event_collaborators
                    SET status       = 'pending',
                        invited_by   = v_owner_profile_id,
                        invited_at   = now(),
                        responded_at = NULL,
                        updated_at   = now(),
                        is_deleted   = false,
                        deleted_at   = NULL
                    WHERE id = v_existing_collab_id;
                ELSE
                    -- New collaborator
                    INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, updated_at)
                    VALUES (gen_random_uuid(), v_collab_target_id, v_collab_id, v_owner_profile_id, 'pending', now(), now());
                END IF;

                -- Send notification
                INSERT INTO notifications (user_id, title, body, data)
                VALUES (
                    v_invitee_user_id,
                    'Collaboration Invite',
                    v_owner_name || ' invited you to collaborate on "' || v_event_title || '"',
                    json_build_object(
                        'type',                  'collaborator_invite',
                        'event_id',              v_collab_target_id,
                        'invited_profile_id',    v_collab_id,
                        'invited_by_profile_id', v_owner_profile_id
                    )
                );

                v_invitee_user_id    := NULL;
                v_existing_collab_id := NULL;

            END LOOP;

        END IF;

        -- scope='this' → mark this occurrence as having its own collaborator list
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET collaborators_overridden = true,
                updated_at               = now()
            WHERE event_id = p_event_id;
        END IF;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_success_message,
        'data', json_build_object(
            'skipped_collaborator_ids', v_skipped_ids
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```

---

## V2.2 Function (Previous)

```sql
-- Function: update_event_v2_2
-- Group: Events
-- Endpoint: POST /rpc/update_event_v2_2
-- Tables:   event_mst (UPDATE), event_platforms (DELETE+INSERT), event_recurring (UPDATE if recurring)
--           event_collaborators (INSERT/UPDATE/soft-delete), notifications (INSERT if collaborative)
-- Doc: docs/api/events/update_event.md
-- Version: 2.2 (2026-08-10)
--
-- Change from v1: Collaborator sync behavior
--   p_collaborator_ids: null        = don't touch existing collaborators
--   p_collaborator_ids: []          = remove ALL collaborators (soft delete)
--   p_collaborator_ids: [id1,id2]   = SYNC — keep id1/id2, remove anyone not in list, add new ones
--
-- Change from v2.0: Collaborator sync is scope-aware — p_scope='this' now syncs the
--   occurrence's own collaborators (event_id = p_event_id, collaborators_overridden = true)
--   instead of always writing to the series parent. p_scope='all' still syncs the parent,
--   but first clears any per-occurrence overrides so children revert to the series list.
--
-- Example (current collaborators: 1,2,3):
--   Pass (1,2,3) → no change
--   Pass (1,2)   → remove 3
--   Pass []      → remove 1,2,3
--   Pass (1,2,4) → remove 3, add 4
--
-- p_scope: 'all' (default) = update parent + all occurrences
--          'this'          = per-occurrence scalar/platform/collaborator overrides
-- p_platforms:        null = don't touch | [] = clear all | [...] = replace
-- p_recurring_days:   null or [] = no rule change | [...] = update + regen ('all' scope only)
-- p_is_collaborative: always parent-level (applied to parent + all children when set)
-- p_collaborator_ids: 'all' scope = series-level (parent) | 'this' scope = occurrence-level
--                     (see collaborators_overridden on event_mst)
--
-- DEPLOYMENT — this is a NEW function name (update_event_v2_2), no overload to drop.
-- Old callers on update_event_v2_1 keep working unchanged (see "V2.1 Function (Previous)" below).
-- Point the client at /rpc/update_event_v2_2 once deployed, then:
--   NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION update_event_v2_2(
    p_event_id             uuid,
    p_user_id              uuid,
    p_scope                text     DEFAULT 'all',
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_event_end_time       time     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_is_collaborative     boolean  DEFAULT NULL,
    p_collaborator_ids     uuid[]   DEFAULT NULL,
    p_platforms            jsonb    DEFAULT NULL,
    -- Recurring fields
    p_recurring_days       text[]   DEFAULT NULL,
    p_recurring_type       text     DEFAULT NULL,
    p_recurring_interval   int      DEFAULT NULL,
    p_recurring_start_date date     DEFAULT NULL,
    p_recurring_end_date   date     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Intent flags
    v_scope             text;
    v_update_recurring  boolean;
    v_sync_collabs      boolean;   -- true when p_collaborator_ids IS NOT NULL (including [])
    v_has_scalar        boolean;
    v_has_platforms     boolean;
    v_occurrence_change boolean;

    v_platform          jsonb;

    -- Parent resolution
    v_parent_event_id    uuid;
    v_target_parent_id   uuid;

    -- End-time validation
    v_existing_event_time     time;
    v_existing_event_end_time time;
    v_final_event_time        time;
    v_final_event_end_time    time;

    -- Recurring rule build-up
    v_rec_days      text[];
    v_rec_type      text;
    v_rec_interval  int;
    v_rec_start     date;
    v_rec_end       date;
    v_safe_end      date;

    -- Child generation
    v_profile_id         uuid;
    v_title              text;
    v_description        text;
    v_event_time         time;
    v_event_end_time     time;
    v_event_tz           text;
    v_livestream         boolean;
    v_video              boolean;
    v_is_collaborative   boolean;
    v_day_name           text;
    v_dow_target         int;
    v_dow_start          int;
    v_days_ahead         int;
    v_first_occ          date;
    v_occ_date           date;
    v_month_start        date;
    v_month_end          date;
    v_dow_month_end      int;

    -- Collaborator sync
    v_owner_profile_id   uuid;
    v_owner_name         text;
    v_event_title        text;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;
    v_existing_collab_id uuid;
    v_existing_deleted   boolean;
    v_effective_is_collab boolean;
    v_collab_target_id   uuid;   -- event_id collaborator rows are keyed to (occurrence when scope='this', parent when scope='all')

    v_success_message    text;
BEGIN

    -- ── 1. Required params ────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── 2. Normalise scope ────────────────────────────────────────────────────
    v_scope := COALESCE(NULLIF(trim(p_scope), ''), 'all');
    IF v_scope NOT IN ('all', 'this') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be ''all'' or ''this''');
    END IF;

    -- ── 3. Intent flags ───────────────────────────────────────────────────────
    v_update_recurring := p_recurring_days IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) > 0;

    -- v2 change: sync triggers on ANY non-null value, including empty array
    v_sync_collabs := p_collaborator_ids IS NOT NULL;

    -- v2.1: 'this' scope syncs the occurrence's OWN collaborator rows (event_id = p_event_id);
    -- 'all' scope syncs the series' collaborator rows (event_id = v_target_parent_id), same as v2.0.
    -- Resolved after v_scope is demoted below (step 6), so recompute isn't needed until then.

    v_has_scalar := p_title          IS NOT NULL OR p_description   IS NOT NULL
                 OR p_event_date     IS NOT NULL OR p_event_time    IS NOT NULL
                 OR p_event_end_time IS NOT NULL OR p_timezone      IS NOT NULL
                 OR p_livestream     IS NOT NULL OR p_video         IS NOT NULL;
    v_has_platforms     := p_platforms IS NOT NULL;
    v_occurrence_change := v_has_scalar OR v_has_platforms;

    -- ── 4. Ownership check ───────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── 5. Resolve parent event ──────────────────────────────────────────────
    SELECT parent_event_id INTO v_parent_event_id
    FROM event_mst WHERE event_id = p_event_id;

    v_target_parent_id := COALESCE(v_parent_event_id, p_event_id);

    -- ── 6. Demote 'this' to 'all' for non-recurring events ───────────────────
    IF v_scope = 'this' AND v_parent_event_id IS NULL THEN
        v_scope := 'all';
    END IF;

    -- ── 6b. Resolve collaborator sync target ─────────────────────────────────
    v_collab_target_id := CASE WHEN v_scope = 'this' THEN p_event_id ELSE v_target_parent_id END;

    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH A: scope = 'this'
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'this' THEN

        IF v_update_recurring THEN
            RETURN json_build_object('status', false, 'message',
                'Recurring schedule cannot be changed for a single occurrence — use scope ''all''');
        END IF;

        IF v_has_scalar THEN
            SELECT event_time, event_end_time
            INTO v_existing_event_time, v_existing_event_end_time
            FROM event_mst WHERE event_id = p_event_id;

            v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
            v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

            IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
                RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
            END IF;
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_occurrence_change THEN
            UPDATE event_mst
            SET title          = COALESCE(p_title,          title),
                description    = COALESCE(p_description,    description),
                event_date     = COALESCE(p_event_date,     event_date),
                event_time     = COALESCE(p_event_time,     event_time),
                event_end_time = COALESCE(p_event_end_time, event_end_time),
                event_timezone = COALESCE(p_timezone,       event_timezone),
                livestream     = COALESCE(p_livestream,     livestream),
                video          = COALESCE(p_video,          video),
                is_overridden  = true,
                updated_at     = now()
            WHERE event_id = p_event_id;
        END IF;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = p_event_id;
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), p_event_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event occurrence updated successfully';

    ELSE
    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH B: scope = 'all'
    -- ══════════════════════════════════════════════════════════════════════════

        SELECT event_time, event_end_time
        INTO v_existing_event_time, v_existing_event_end_time
        FROM event_mst WHERE event_id = v_target_parent_id;

        v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
        v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

        IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
            RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_update_recurring THEN

            IF EXISTS (
                SELECT 1 FROM unnest(p_recurring_days) AS d(day)
                WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
            END IF;

            SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
            INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
            FROM event_recurring WHERE event_id = v_target_parent_id;

            v_rec_days     := p_recurring_days;
            v_rec_type     := COALESCE(p_recurring_type,       v_rec_type);
            v_rec_start    := COALESCE(p_recurring_start_date, v_rec_start);
            v_rec_end      := COALESCE(p_recurring_end_date,   v_rec_end);

            IF v_rec_type IS NULL OR v_rec_type NOT IN ('weekly', 'first', 'last') THEN
                RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
            END IF;

            IF v_rec_type IN ('first', 'last') THEN
                v_rec_interval := NULL;
            ELSE
                v_rec_interval := COALESCE(p_recurring_interval, v_rec_interval);
                IF v_rec_interval IS NULL THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
                END IF;
                IF v_rec_interval < 1 OR v_rec_interval > 12 THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
                END IF;
            END IF;

            IF v_rec_start IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
            END IF;

            IF v_rec_end IS NOT NULL AND v_rec_end <= v_rec_start THEN
                RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
            END IF;

        END IF;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_date     = COALESCE(p_event_date,     event_date),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            updated_at     = now()
        WHERE event_id = v_target_parent_id;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            is_overridden  = false,
            updated_at     = now()
        WHERE parent_event_id = v_target_parent_id;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = v_target_parent_id;
            DELETE FROM event_platforms
            WHERE event_id IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id);
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), v_target_parent_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event updated successfully';

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: is_collaborative (v2.2 — now scope-aware, was always parent-level in v2.1)
    --
    -- scope='this' → applies only to the occurrence itself (p_event_id); every row already
    --                stores its own is_collaborative value and read SPs already read it
    --                directly (no fallback/COALESCE), so no schema or read-path change needed.
    -- scope='all'  → applies to the parent + all children, same as before.
    -- ══════════════════════════════════════════════════════════════════════════
    IF p_is_collaborative IS NOT NULL THEN
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET is_collaborative = p_is_collaborative,
                updated_at       = now()
            WHERE event_id = p_event_id;
        ELSE
            UPDATE event_mst
            SET is_collaborative = p_is_collaborative,
                updated_at       = now()
            WHERE event_id = v_target_parent_id
               OR parent_event_id = v_target_parent_id;
        END IF;
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule + regen
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_update_recurring THEN

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '3 months');
        v_rec_end  := v_safe_end;

        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end,
            renewal_notified_at  = NULL
        WHERE event_id = v_target_parent_id;

        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id;

        SELECT profile_id, title, description, event_time, event_end_time,
               event_timezone, livestream, video, is_collaborative
        INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
             v_event_tz, v_livestream, v_video, v_is_collaborative
        FROM event_mst WHERE event_id = v_target_parent_id;

        IF v_rec_type = 'weekly' THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM v_rec_start)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := v_rec_start + v_days_ahead;
                v_occ_date   := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                        event_date, event_time, event_end_time, event_timezone,
                        livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                    VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                        v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                        v_livestream, v_video, v_is_collaborative, true, now(), now());
                    v_occ_date := v_occ_date + (7 * v_rec_interval);
                END LOOP;
            END LOOP;

        ELSIF v_rec_type IN ('first', 'last') THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_month_start := DATE_TRUNC('month', v_rec_start)::date;
                WHILE v_month_start <= v_safe_end LOOP
                    IF v_rec_type = 'first' THEN
                        v_days_ahead := (7 + v_dow_target - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date   := v_month_start + v_days_ahead;
                    ELSE
                        v_month_end     := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;
                    IF v_occ_date >= v_rec_start AND v_occ_date <= v_safe_end THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;
            END LOOP;

        END IF;

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: collaborator SYNC (v2.1 — scope-aware; v2.0 always synced the parent)
    --
    -- null            → skip entirely, don't touch collaborators
    -- []              → soft-delete ALL existing collaborators (at the resolved target)
    -- [id1, id2, ...] → soft-delete anyone NOT in list, invite anyone new (at the resolved target)
    --
    -- scope='this' → target is the occurrence itself (v_collab_target_id = p_event_id).
    --                event_collaborators rows are written against the CHILD's own event_id
    --                and event_mst.collaborators_overridden is flipped true on that child so
    --                read SPs know to use its own rows instead of the parent's.
    -- scope='all'  → target is the series parent (v_collab_target_id = v_target_parent_id),
    --                same as v2.0. Any prior per-occurrence overrides are discarded first so
    --                children go back to inheriting the series list.
    -- ══════════════════════════════════════════════════════════════════════════
    v_skipped_ids := ARRAY[]::uuid[];

    IF v_sync_collabs THEN

        -- Check is_collaborative before doing anything — read from whichever row collaborators
        -- are being synced against (the occurrence for scope='this', the parent for scope='all'),
        -- since is_collaborative is now scope-aware too (v2.2).
        v_effective_is_collab := COALESCE(
            p_is_collaborative,
            (SELECT is_collaborative FROM event_mst WHERE event_id = v_collab_target_id)
        );

        -- If turning off collaboration and passing ids, reject
        IF v_effective_is_collab = false
           AND COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN
            RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
        END IF;

        -- scope='all' → discard any per-occurrence collaborator overrides so children
        -- revert to inheriting the series list before the parent-level sync below.
        -- Soft-delete (is_deleted/deleted_at), matching every other collaborator removal
        -- in this function — event_collaborators has no hard-delete precedent anywhere.
        IF v_scope = 'all' THEN
            UPDATE event_collaborators
            SET is_deleted = true,
                deleted_at = now(),
                updated_at = now()
            WHERE event_id   IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id)
              AND is_deleted = false;

            UPDATE event_mst
            SET collaborators_overridden = false
            WHERE parent_event_id = v_target_parent_id;
        END IF;

        -- ── Step 1: Soft-delete collaborators NOT in the new list ─────────────
        -- Empty array = remove all; non-empty = remove only those absent from list
        UPDATE event_collaborators
        SET is_deleted = true,
            deleted_at = now(),
            updated_at = now()
        WHERE event_id   = v_collab_target_id
          AND is_deleted = false
          AND (
              COALESCE(array_length(p_collaborator_ids, 1), 0) = 0   -- [] → remove all
              OR profile_id != ALL(p_collaborator_ids)                 -- not in new list
          );

        -- ── Step 2: Invite/re-invite collaborators in the new list ────────────
        IF COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN

            SELECT cp.id, cp.profile_name, e.title
            INTO v_owner_profile_id, v_owner_name, v_event_title
            FROM event_mst e
            JOIN creator_profiles cp ON cp.id = e.profile_id
            WHERE e.event_id = v_collab_target_id;

            -- Count accepted collaborators AFTER the removals above
            SELECT COUNT(*) INTO v_collab_count
            FROM event_collaborators
            WHERE event_id   = v_collab_target_id
              AND status     = 'accepted'
              AND is_deleted = false;

            FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

                IF v_collab_id IS NULL THEN CONTINUE; END IF;

                -- Skip the event owner
                IF v_collab_id = v_owner_profile_id THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Find existing row (active or previously soft-deleted)
                SELECT id, is_deleted
                INTO v_existing_collab_id, v_existing_deleted
                FROM event_collaborators
                WHERE event_id   = v_collab_target_id
                  AND profile_id = v_collab_id
                LIMIT 1;

                -- Already active → no change needed, skip
                IF v_existing_collab_id IS NOT NULL AND v_existing_deleted = false THEN
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Max 5 accepted collaborators
                IF v_collab_count >= 5 THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Validate the profile exists and is active
                SELECT user_id INTO v_invitee_user_id
                FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

                IF v_invitee_user_id IS NULL THEN
                    v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Re-invite (previously soft-deleted row exists)
                IF v_existing_collab_id IS NOT NULL THEN
                    UPDATE event_collaborators
                    SET status       = 'pending',
                        invited_by   = v_owner_profile_id,
                        invited_at   = now(),
                        responded_at = NULL,
                        updated_at   = now(),
                        is_deleted   = false,
                        deleted_at   = NULL
                    WHERE id = v_existing_collab_id;
                ELSE
                    -- New collaborator
                    INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, updated_at)
                    VALUES (gen_random_uuid(), v_collab_target_id, v_collab_id, v_owner_profile_id, 'pending', now(), now());
                END IF;

                -- Send notification
                INSERT INTO notifications (user_id, title, body, data)
                VALUES (
                    v_invitee_user_id,
                    'Collaboration Invite',
                    v_owner_name || ' invited you to collaborate on "' || v_event_title || '"',
                    json_build_object(
                        'type',                  'collaborator_invite',
                        'event_id',              v_collab_target_id,
                        'invited_profile_id',    v_collab_id,
                        'invited_by_profile_id', v_owner_profile_id
                    )
                );

                v_invitee_user_id    := NULL;
                v_existing_collab_id := NULL;

            END LOOP;

        END IF;

        -- scope='this' → mark this occurrence as having its own collaborator list
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET collaborators_overridden = true,
                updated_at               = now()
            WHERE event_id = p_event_id;
        END IF;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_success_message,
        'data', json_build_object(
            'skipped_collaborator_ids', v_skipped_ids
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```

---

## V2.1 Function (Previous)

```sql
-- Function: update_event_v2_1
-- Group: Events
-- Endpoint: POST /rpc/update_event_v2_1
-- Tables:   event_mst (UPDATE), event_platforms (DELETE+INSERT), event_recurring (UPDATE if recurring)
--           event_collaborators (INSERT/UPDATE/soft-delete), notifications (INSERT if collaborative)
-- Doc: docs/api/events/update_event.md
-- Version: 2.1 (2026-08-06)
--
-- Change from v1: Collaborator sync behavior
--   p_collaborator_ids: null        = don't touch existing collaborators
--   p_collaborator_ids: []          = remove ALL collaborators (soft delete)
--   p_collaborator_ids: [id1,id2]   = SYNC — keep id1/id2, remove anyone not in list, add new ones
--
-- Change from v2.0: Collaborator sync is scope-aware — p_scope='this' now syncs the
--   occurrence's own collaborators (event_id = p_event_id, collaborators_overridden = true)
--   instead of always writing to the series parent. p_scope='all' still syncs the parent,
--   but first clears any per-occurrence overrides so children revert to the series list.
--
-- Example (current collaborators: 1,2,3):
--   Pass (1,2,3) → no change
--   Pass (1,2)   → remove 3
--   Pass []      → remove 1,2,3
--   Pass (1,2,4) → remove 3, add 4
--
-- p_scope: 'all' (default) = update parent + all occurrences
--          'this'          = per-occurrence scalar/platform/collaborator overrides
-- p_platforms:        null = don't touch | [] = clear all | [...] = replace
-- p_recurring_days:   null or [] = no rule change | [...] = update + regen ('all' scope only)
-- p_is_collaborative: always parent-level (applied to parent + all children when set)
-- p_collaborator_ids: 'all' scope = series-level (parent) | 'this' scope = occurrence-level
--                     (see collaborators_overridden on event_mst)
--
-- DEPLOYMENT — this is a NEW function name (update_event_v2_1), no overload to drop.
-- Old callers on update_event_v2 keep working unchanged (see "V2.0 Function (Previous)" below).
-- Point the client at /rpc/update_event_v2_1 once deployed, then:
--   NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION update_event_v2_1(
    p_event_id             uuid,
    p_user_id              uuid,
    p_scope                text     DEFAULT 'all',
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_event_end_time       time     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_is_collaborative     boolean  DEFAULT NULL,
    p_collaborator_ids     uuid[]   DEFAULT NULL,
    p_platforms            jsonb    DEFAULT NULL,
    -- Recurring fields
    p_recurring_days       text[]   DEFAULT NULL,
    p_recurring_type       text     DEFAULT NULL,
    p_recurring_interval   int      DEFAULT NULL,
    p_recurring_start_date date     DEFAULT NULL,
    p_recurring_end_date   date     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Intent flags
    v_scope             text;
    v_update_recurring  boolean;
    v_sync_collabs      boolean;   -- true when p_collaborator_ids IS NOT NULL (including [])
    v_has_scalar        boolean;
    v_has_platforms     boolean;
    v_occurrence_change boolean;

    v_platform          jsonb;

    -- Parent resolution
    v_parent_event_id    uuid;
    v_target_parent_id   uuid;

    -- End-time validation
    v_existing_event_time     time;
    v_existing_event_end_time time;
    v_final_event_time        time;
    v_final_event_end_time    time;

    -- Recurring rule build-up
    v_rec_days      text[];
    v_rec_type      text;
    v_rec_interval  int;
    v_rec_start     date;
    v_rec_end       date;
    v_safe_end      date;

    -- Child generation
    v_profile_id         uuid;
    v_title              text;
    v_description        text;
    v_event_time         time;
    v_event_end_time     time;
    v_event_tz           text;
    v_livestream         boolean;
    v_video              boolean;
    v_is_collaborative   boolean;
    v_day_name           text;
    v_dow_target         int;
    v_dow_start          int;
    v_days_ahead         int;
    v_first_occ          date;
    v_occ_date           date;
    v_month_start        date;
    v_month_end          date;
    v_dow_month_end      int;

    -- Collaborator sync
    v_owner_profile_id   uuid;
    v_owner_name         text;
    v_event_title        text;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;
    v_existing_collab_id uuid;
    v_existing_deleted   boolean;
    v_effective_is_collab boolean;
    v_collab_target_id   uuid;   -- event_id collaborator rows are keyed to (occurrence when scope='this', parent when scope='all')

    v_success_message    text;
BEGIN

    -- ── 1. Required params ────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── 2. Normalise scope ────────────────────────────────────────────────────
    v_scope := COALESCE(NULLIF(trim(p_scope), ''), 'all');
    IF v_scope NOT IN ('all', 'this') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be ''all'' or ''this''');
    END IF;

    -- ── 3. Intent flags ───────────────────────────────────────────────────────
    v_update_recurring := p_recurring_days IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) > 0;

    -- v2 change: sync triggers on ANY non-null value, including empty array
    v_sync_collabs := p_collaborator_ids IS NOT NULL;

    -- v2.1: 'this' scope syncs the occurrence's OWN collaborator rows (event_id = p_event_id);
    -- 'all' scope syncs the series' collaborator rows (event_id = v_target_parent_id), same as v2.0.
    -- Resolved after v_scope is demoted below (step 6), so recompute isn't needed until then.

    v_has_scalar := p_title          IS NOT NULL OR p_description   IS NOT NULL
                 OR p_event_date     IS NOT NULL OR p_event_time    IS NOT NULL
                 OR p_event_end_time IS NOT NULL OR p_timezone      IS NOT NULL
                 OR p_livestream     IS NOT NULL OR p_video         IS NOT NULL;
    v_has_platforms     := p_platforms IS NOT NULL;
    v_occurrence_change := v_has_scalar OR v_has_platforms;

    -- ── 4. Ownership check ───────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── 5. Resolve parent event ──────────────────────────────────────────────
    SELECT parent_event_id INTO v_parent_event_id
    FROM event_mst WHERE event_id = p_event_id;

    v_target_parent_id := COALESCE(v_parent_event_id, p_event_id);

    -- ── 6. Demote 'this' to 'all' for non-recurring events ───────────────────
    IF v_scope = 'this' AND v_parent_event_id IS NULL THEN
        v_scope := 'all';
    END IF;

    -- ── 6b. Resolve collaborator sync target ─────────────────────────────────
    v_collab_target_id := CASE WHEN v_scope = 'this' THEN p_event_id ELSE v_target_parent_id END;

    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH A: scope = 'this'
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'this' THEN

        IF v_update_recurring THEN
            RETURN json_build_object('status', false, 'message',
                'Recurring schedule cannot be changed for a single occurrence — use scope ''all''');
        END IF;

        IF v_has_scalar THEN
            SELECT event_time, event_end_time
            INTO v_existing_event_time, v_existing_event_end_time
            FROM event_mst WHERE event_id = p_event_id;

            v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
            v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

            IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
                RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
            END IF;
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_occurrence_change THEN
            UPDATE event_mst
            SET title          = COALESCE(p_title,          title),
                description    = COALESCE(p_description,    description),
                event_date     = COALESCE(p_event_date,     event_date),
                event_time     = COALESCE(p_event_time,     event_time),
                event_end_time = COALESCE(p_event_end_time, event_end_time),
                event_timezone = COALESCE(p_timezone,       event_timezone),
                livestream     = COALESCE(p_livestream,     livestream),
                video          = COALESCE(p_video,          video),
                is_overridden  = true,
                updated_at     = now()
            WHERE event_id = p_event_id;
        END IF;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = p_event_id;
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), p_event_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event occurrence updated successfully';

    ELSE
    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH B: scope = 'all'
    -- ══════════════════════════════════════════════════════════════════════════

        SELECT event_time, event_end_time
        INTO v_existing_event_time, v_existing_event_end_time
        FROM event_mst WHERE event_id = v_target_parent_id;

        v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
        v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

        IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
            RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_update_recurring THEN

            IF EXISTS (
                SELECT 1 FROM unnest(p_recurring_days) AS d(day)
                WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
            END IF;

            SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
            INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
            FROM event_recurring WHERE event_id = v_target_parent_id;

            v_rec_days     := p_recurring_days;
            v_rec_type     := COALESCE(p_recurring_type,       v_rec_type);
            v_rec_start    := COALESCE(p_recurring_start_date, v_rec_start);
            v_rec_end      := COALESCE(p_recurring_end_date,   v_rec_end);

            IF v_rec_type IS NULL OR v_rec_type NOT IN ('weekly', 'first', 'last') THEN
                RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
            END IF;

            IF v_rec_type IN ('first', 'last') THEN
                v_rec_interval := NULL;
            ELSE
                v_rec_interval := COALESCE(p_recurring_interval, v_rec_interval);
                IF v_rec_interval IS NULL THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
                END IF;
                IF v_rec_interval < 1 OR v_rec_interval > 12 THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
                END IF;
            END IF;

            IF v_rec_start IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
            END IF;

            IF v_rec_end IS NOT NULL AND v_rec_end <= v_rec_start THEN
                RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
            END IF;

        END IF;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_date     = COALESCE(p_event_date,     event_date),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            updated_at     = now()
        WHERE event_id = v_target_parent_id;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            is_overridden  = false,
            updated_at     = now()
        WHERE parent_event_id = v_target_parent_id;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = v_target_parent_id;
            DELETE FROM event_platforms
            WHERE event_id IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id);
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), v_target_parent_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event updated successfully';

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: is_collaborative
    -- ══════════════════════════════════════════════════════════════════════════
    IF p_is_collaborative IS NOT NULL THEN
        UPDATE event_mst
        SET is_collaborative = p_is_collaborative,
            updated_at       = now()
        WHERE event_id = v_target_parent_id
           OR parent_event_id = v_target_parent_id;
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule + regen
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_update_recurring THEN

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '3 months');
        v_rec_end  := v_safe_end;

        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end,
            renewal_notified_at  = NULL
        WHERE event_id = v_target_parent_id;

        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id;

        SELECT profile_id, title, description, event_time, event_end_time,
               event_timezone, livestream, video, is_collaborative
        INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
             v_event_tz, v_livestream, v_video, v_is_collaborative
        FROM event_mst WHERE event_id = v_target_parent_id;

        IF v_rec_type = 'weekly' THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM v_rec_start)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := v_rec_start + v_days_ahead;
                v_occ_date   := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                        event_date, event_time, event_end_time, event_timezone,
                        livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                    VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                        v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                        v_livestream, v_video, v_is_collaborative, true, now(), now());
                    v_occ_date := v_occ_date + (7 * v_rec_interval);
                END LOOP;
            END LOOP;

        ELSIF v_rec_type IN ('first', 'last') THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_month_start := DATE_TRUNC('month', v_rec_start)::date;
                WHILE v_month_start <= v_safe_end LOOP
                    IF v_rec_type = 'first' THEN
                        v_days_ahead := (7 + v_dow_target - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date   := v_month_start + v_days_ahead;
                    ELSE
                        v_month_end     := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;
                    IF v_occ_date >= v_rec_start AND v_occ_date <= v_safe_end THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;
            END LOOP;

        END IF;

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: collaborator SYNC (v2.1 — scope-aware; v2.0 always synced the parent)
    --
    -- null            → skip entirely, don't touch collaborators
    -- []              → soft-delete ALL existing collaborators (at the resolved target)
    -- [id1, id2, ...] → soft-delete anyone NOT in list, invite anyone new (at the resolved target)
    --
    -- scope='this' → target is the occurrence itself (v_collab_target_id = p_event_id).
    --                event_collaborators rows are written against the CHILD's own event_id
    --                and event_mst.collaborators_overridden is flipped true on that child so
    --                read SPs know to use its own rows instead of the parent's.
    -- scope='all'  → target is the series parent (v_collab_target_id = v_target_parent_id),
    --                same as v2.0. Any prior per-occurrence overrides are discarded first so
    --                children go back to inheriting the series list.
    -- ══════════════════════════════════════════════════════════════════════════
    v_skipped_ids := ARRAY[]::uuid[];

    IF v_sync_collabs THEN

        -- Check is_collaborative before doing anything (always parent-level)
        v_effective_is_collab := COALESCE(
            p_is_collaborative,
            (SELECT is_collaborative FROM event_mst WHERE event_id = v_target_parent_id)
        );

        -- If turning off collaboration and passing ids, reject
        IF v_effective_is_collab = false
           AND COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN
            RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
        END IF;

        -- scope='all' → discard any per-occurrence collaborator overrides so children
        -- revert to inheriting the series list before the parent-level sync below.
        -- Soft-delete (is_deleted/deleted_at), matching every other collaborator removal
        -- in this function — event_collaborators has no hard-delete precedent anywhere.
        IF v_scope = 'all' THEN
            UPDATE event_collaborators
            SET is_deleted = true,
                deleted_at = now(),
                updated_at = now()
            WHERE event_id   IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id)
              AND is_deleted = false;

            UPDATE event_mst
            SET collaborators_overridden = false
            WHERE parent_event_id = v_target_parent_id;
        END IF;

        -- ── Step 1: Soft-delete collaborators NOT in the new list ─────────────
        -- Empty array = remove all; non-empty = remove only those absent from list
        UPDATE event_collaborators
        SET is_deleted = true,
            deleted_at = now(),
            updated_at = now()
        WHERE event_id   = v_collab_target_id
          AND is_deleted = false
          AND (
              COALESCE(array_length(p_collaborator_ids, 1), 0) = 0   -- [] → remove all
              OR profile_id != ALL(p_collaborator_ids)                 -- not in new list
          );

        -- ── Step 2: Invite/re-invite collaborators in the new list ────────────
        IF COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN

            SELECT cp.id, cp.profile_name, e.title
            INTO v_owner_profile_id, v_owner_name, v_event_title
            FROM event_mst e
            JOIN creator_profiles cp ON cp.id = e.profile_id
            WHERE e.event_id = v_collab_target_id;

            -- Count accepted collaborators AFTER the removals above
            SELECT COUNT(*) INTO v_collab_count
            FROM event_collaborators
            WHERE event_id   = v_collab_target_id
              AND status     = 'accepted'
              AND is_deleted = false;

            FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

                IF v_collab_id IS NULL THEN CONTINUE; END IF;

                -- Skip the event owner
                IF v_collab_id = v_owner_profile_id THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Find existing row (active or previously soft-deleted)
                SELECT id, is_deleted
                INTO v_existing_collab_id, v_existing_deleted
                FROM event_collaborators
                WHERE event_id   = v_collab_target_id
                  AND profile_id = v_collab_id
                LIMIT 1;

                -- Already active → no change needed, skip
                IF v_existing_collab_id IS NOT NULL AND v_existing_deleted = false THEN
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Max 5 accepted collaborators
                IF v_collab_count >= 5 THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Validate the profile exists and is active
                SELECT user_id INTO v_invitee_user_id
                FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

                IF v_invitee_user_id IS NULL THEN
                    v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Re-invite (previously soft-deleted row exists)
                IF v_existing_collab_id IS NOT NULL THEN
                    UPDATE event_collaborators
                    SET status       = 'pending',
                        invited_by   = v_owner_profile_id,
                        invited_at   = now(),
                        responded_at = NULL,
                        updated_at   = now(),
                        is_deleted   = false,
                        deleted_at   = NULL
                    WHERE id = v_existing_collab_id;
                ELSE
                    -- New collaborator
                    INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, updated_at)
                    VALUES (gen_random_uuid(), v_collab_target_id, v_collab_id, v_owner_profile_id, 'pending', now(), now());
                END IF;

                -- Send notification
                INSERT INTO notifications (user_id, title, body, data)
                VALUES (
                    v_invitee_user_id,
                    'Collaboration Invite',
                    v_owner_name || ' invited you to collaborate on "' || v_event_title || '"',
                    json_build_object(
                        'type',                  'collaborator_invite',
                        'event_id',              v_collab_target_id,
                        'invited_profile_id',    v_collab_id,
                        'invited_by_profile_id', v_owner_profile_id
                    )
                );

                v_invitee_user_id    := NULL;
                v_existing_collab_id := NULL;

            END LOOP;

        END IF;

        -- scope='this' → mark this occurrence as having its own collaborator list
        IF v_scope = 'this' THEN
            UPDATE event_mst
            SET collaborators_overridden = true,
                updated_at               = now()
            WHERE event_id = p_event_id;
        END IF;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_success_message,
        'data', json_build_object(
            'skipped_collaborator_ids', v_skipped_ids
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```

---

## V2.0 Function (Previous)

```sql
-- Function: update_event_v2
-- Group: Events
-- Endpoint: POST /rpc/update_event_v2
-- Tables:   event_mst (UPDATE), event_platforms (DELETE+INSERT), event_recurring (UPDATE if recurring)
--           event_collaborators (INSERT/UPDATE/soft-delete), notifications (INSERT if collaborative)
-- Doc: docs/api/events/update_event.md
-- Version: 2.0 (2026-06-15)
--
-- Superseded by update_event_v2_1 (2026-08-06) — collaborator sync in this version always
-- targets the series parent regardless of p_scope, which means p_scope='this' with
-- p_collaborator_ids changes collaborators for the WHOLE recurring series, not just the
-- selected occurrence. Kept here only for existing callers still on /rpc/update_event_v2.
--
-- Change from v1: Collaborator sync behavior
--   p_collaborator_ids: null        = don't touch existing collaborators
--   p_collaborator_ids: []          = remove ALL collaborators (soft delete)
--   p_collaborator_ids: [id1,id2]   = SYNC — keep id1/id2, remove anyone not in list, add new ones
--
-- Example (current collaborators: 1,2,3):
--   Pass (1,2,3) → no change
--   Pass (1,2)   → remove 3
--   Pass []      → remove 1,2,3
--   Pass (1,2,4) → remove 3, add 4
--
-- p_scope: 'all' (default) = update parent + all occurrences
--          'this'          = per-occurrence scalar/platform overrides
-- p_platforms:        null = don't touch | [] = clear all | [...] = replace
-- p_recurring_days:   null or [] = no rule change | [...] = update + regen ('all' scope only)
-- p_is_collaborative: always parent-level (applied to parent + all children when set)
--
-- DEPLOYMENT — drop old overloads first:
--   DO $$
--   DECLARE r record;
--   BEGIN
--     FOR r IN
--       SELECT p.oid::regprocedure AS sig
--       FROM pg_proc p
--       JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE p.proname = 'update_event_v2' AND n.nspname = 'public'
--     LOOP
--       EXECUTE 'DROP FUNCTION ' || r.sig || ' CASCADE';
--     END LOOP;
--   END $$;
--   NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION update_event_v2(
    p_event_id             uuid,
    p_user_id              uuid,
    p_scope                text     DEFAULT 'all',
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_event_end_time       time     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_is_collaborative     boolean  DEFAULT NULL,
    p_collaborator_ids     uuid[]   DEFAULT NULL,
    p_platforms            jsonb    DEFAULT NULL,
    -- Recurring fields
    p_recurring_days       text[]   DEFAULT NULL,
    p_recurring_type       text     DEFAULT NULL,
    p_recurring_interval   int      DEFAULT NULL,
    p_recurring_start_date date     DEFAULT NULL,
    p_recurring_end_date   date     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Intent flags
    v_scope             text;
    v_update_recurring  boolean;
    v_sync_collabs      boolean;   -- true when p_collaborator_ids IS NOT NULL (including [])
    v_has_scalar        boolean;
    v_has_platforms     boolean;
    v_occurrence_change boolean;

    v_platform          jsonb;

    -- Parent resolution
    v_parent_event_id    uuid;
    v_target_parent_id   uuid;

    -- End-time validation
    v_existing_event_time     time;
    v_existing_event_end_time time;
    v_final_event_time        time;
    v_final_event_end_time    time;

    -- Recurring rule build-up
    v_rec_days      text[];
    v_rec_type      text;
    v_rec_interval  int;
    v_rec_start     date;
    v_rec_end       date;
    v_safe_end      date;

    -- Child generation
    v_profile_id         uuid;
    v_title              text;
    v_description        text;
    v_event_time         time;
    v_event_end_time     time;
    v_event_tz           text;
    v_livestream         boolean;
    v_video              boolean;
    v_is_collaborative   boolean;
    v_day_name           text;
    v_dow_target         int;
    v_dow_start          int;
    v_days_ahead         int;
    v_first_occ          date;
    v_occ_date           date;
    v_month_start        date;
    v_month_end          date;
    v_dow_month_end      int;

    -- Collaborator sync
    v_owner_profile_id   uuid;
    v_owner_name         text;
    v_event_title        text;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;
    v_existing_collab_id uuid;
    v_existing_deleted   boolean;
    v_effective_is_collab boolean;

    v_success_message    text;
BEGIN

    -- ── 1. Required params ────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── 2. Normalise scope ────────────────────────────────────────────────────
    v_scope := COALESCE(NULLIF(trim(p_scope), ''), 'all');
    IF v_scope NOT IN ('all', 'this') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be ''all'' or ''this''');
    END IF;

    -- ── 3. Intent flags ───────────────────────────────────────────────────────
    v_update_recurring := p_recurring_days IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) > 0;

    -- v2 change: sync triggers on ANY non-null value, including empty array
    v_sync_collabs := p_collaborator_ids IS NOT NULL;

    v_has_scalar := p_title          IS NOT NULL OR p_description   IS NOT NULL
                 OR p_event_date     IS NOT NULL OR p_event_time    IS NOT NULL
                 OR p_event_end_time IS NOT NULL OR p_timezone      IS NOT NULL
                 OR p_livestream     IS NOT NULL OR p_video         IS NOT NULL;
    v_has_platforms     := p_platforms IS NOT NULL;
    v_occurrence_change := v_has_scalar OR v_has_platforms;

    -- ── 4. Ownership check ───────────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── 5. Resolve parent event ──────────────────────────────────────────────
    SELECT parent_event_id INTO v_parent_event_id
    FROM event_mst WHERE event_id = p_event_id;

    v_target_parent_id := COALESCE(v_parent_event_id, p_event_id);

    -- ── 6. Demote 'this' to 'all' for non-recurring events ───────────────────
    IF v_scope = 'this' AND v_parent_event_id IS NULL THEN
        v_scope := 'all';
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH A: scope = 'this'
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'this' THEN

        IF v_update_recurring THEN
            RETURN json_build_object('status', false, 'message',
                'Recurring schedule cannot be changed for a single occurrence — use scope ''all''');
        END IF;

        IF v_has_scalar THEN
            SELECT event_time, event_end_time
            INTO v_existing_event_time, v_existing_event_end_time
            FROM event_mst WHERE event_id = p_event_id;

            v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
            v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

            IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
                RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
            END IF;
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_occurrence_change THEN
            UPDATE event_mst
            SET title          = COALESCE(p_title,          title),
                description    = COALESCE(p_description,    description),
                event_date     = COALESCE(p_event_date,     event_date),
                event_time     = COALESCE(p_event_time,     event_time),
                event_end_time = COALESCE(p_event_end_time, event_end_time),
                event_timezone = COALESCE(p_timezone,       event_timezone),
                livestream     = COALESCE(p_livestream,     livestream),
                video          = COALESCE(p_video,          video),
                is_overridden  = true,
                updated_at     = now()
            WHERE event_id = p_event_id;
        END IF;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = p_event_id;
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), p_event_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event occurrence updated successfully';

    ELSE
    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH B: scope = 'all'
    -- ══════════════════════════════════════════════════════════════════════════

        SELECT event_time, event_end_time
        INTO v_existing_event_time, v_existing_event_end_time
        FROM event_mst WHERE event_id = v_target_parent_id;

        v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
        v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

        IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
            RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
        END IF;

        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint)
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        IF v_update_recurring THEN

            IF EXISTS (
                SELECT 1 FROM unnest(p_recurring_days) AS d(day)
                WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
            END IF;

            SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
            INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
            FROM event_recurring WHERE event_id = v_target_parent_id;

            v_rec_days     := p_recurring_days;
            v_rec_type     := COALESCE(p_recurring_type,       v_rec_type);
            v_rec_start    := COALESCE(p_recurring_start_date, v_rec_start);
            v_rec_end      := COALESCE(p_recurring_end_date,   v_rec_end);

            IF v_rec_type IS NULL OR v_rec_type NOT IN ('weekly', 'first', 'last') THEN
                RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
            END IF;

            IF v_rec_type IN ('first', 'last') THEN
                v_rec_interval := NULL;
            ELSE
                v_rec_interval := COALESCE(p_recurring_interval, v_rec_interval);
                IF v_rec_interval IS NULL THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
                END IF;
                IF v_rec_interval < 1 OR v_rec_interval > 12 THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
                END IF;
            END IF;

            IF v_rec_start IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
            END IF;

            IF v_rec_end IS NOT NULL AND v_rec_end <= v_rec_start THEN
                RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
            END IF;

        END IF;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_date     = COALESCE(p_event_date,     event_date),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            updated_at     = now()
        WHERE event_id = v_target_parent_id;

        UPDATE event_mst
        SET title          = COALESCE(p_title,          title),
            description    = COALESCE(p_description,    description),
            event_time     = COALESCE(p_event_time,     event_time),
            event_end_time = COALESCE(p_event_end_time, event_end_time),
            event_timezone = COALESCE(p_timezone,       event_timezone),
            livestream     = COALESCE(p_livestream,     livestream),
            video          = COALESCE(p_video,          video),
            is_overridden  = false,
            updated_at     = now()
        WHERE parent_event_id = v_target_parent_id;

        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = v_target_parent_id;
            DELETE FROM event_platforms
            WHERE event_id IN (SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id);
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (gen_random_uuid(), v_target_parent_id, (v_platform->>'platform_id')::int4, v_platform->>'stream_url', now());
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event updated successfully';

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: is_collaborative
    -- ══════════════════════════════════════════════════════════════════════════
    IF p_is_collaborative IS NOT NULL THEN
        UPDATE event_mst
        SET is_collaborative = p_is_collaborative,
            updated_at       = now()
        WHERE event_id = v_target_parent_id
           OR parent_event_id = v_target_parent_id;
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule + regen
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_update_recurring THEN

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '3 months');
        v_rec_end  := v_safe_end;

        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end,
            renewal_notified_at  = NULL
        WHERE event_id = v_target_parent_id;

        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id;

        SELECT profile_id, title, description, event_time, event_end_time,
               event_timezone, livestream, video, is_collaborative
        INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
             v_event_tz, v_livestream, v_video, v_is_collaborative
        FROM event_mst WHERE event_id = v_target_parent_id;

        IF v_rec_type = 'weekly' THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM v_rec_start)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := v_rec_start + v_days_ahead;
                v_occ_date   := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                        event_date, event_time, event_end_time, event_timezone,
                        livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                    VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                        v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                        v_livestream, v_video, v_is_collaborative, true, now(), now());
                    v_occ_date := v_occ_date + (7 * v_rec_interval);
                END LOOP;
            END LOOP;

        ELSIF v_rec_type IN ('first', 'last') THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP
                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_month_start := DATE_TRUNC('month', v_rec_start)::date;
                WHILE v_month_start <= v_safe_end LOOP
                    IF v_rec_type = 'first' THEN
                        v_days_ahead := (7 + v_dow_target - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date   := v_month_start + v_days_ahead;
                    ELSE
                        v_month_end     := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;
                    IF v_occ_date >= v_rec_start AND v_occ_date <= v_safe_end THEN
                        INSERT INTO event_mst (event_id, profile_id, parent_event_id, title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring, created_at, updated_at)
                        VALUES (gen_random_uuid(), v_profile_id, v_target_parent_id, v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true, now(), now());
                    END IF;
                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;
            END LOOP;

        END IF;

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: collaborator SYNC (v2 — replaces append-only logic in v1)
    --
    -- null            → skip entirely, don't touch collaborators
    -- []              → soft-delete ALL existing collaborators
    -- [id1, id2, ...] → soft-delete anyone NOT in list, invite anyone new
    -- ══════════════════════════════════════════════════════════════════════════
    v_skipped_ids := ARRAY[]::uuid[];

    IF v_sync_collabs THEN

        -- Check is_collaborative before doing anything
        v_effective_is_collab := COALESCE(
            p_is_collaborative,
            (SELECT is_collaborative FROM event_mst WHERE event_id = v_target_parent_id)
        );

        -- If turning off collaboration and passing ids, reject
        IF v_effective_is_collab = false
           AND COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN
            RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
        END IF;

        -- ── Step 1: Soft-delete collaborators NOT in the new list ─────────────
        -- Empty array = remove all; non-empty = remove only those absent from list
        UPDATE event_collaborators
        SET is_deleted = true,
            deleted_at = now(),
            updated_at = now()
        WHERE event_id   = v_target_parent_id
          AND is_deleted = false
          AND (
              COALESCE(array_length(p_collaborator_ids, 1), 0) = 0   -- [] → remove all
              OR profile_id != ALL(p_collaborator_ids)                 -- not in new list
          );

        -- ── Step 2: Invite/re-invite collaborators in the new list ────────────
        IF COALESCE(array_length(p_collaborator_ids, 1), 0) > 0 THEN

            SELECT cp.id, cp.profile_name, e.title
            INTO v_owner_profile_id, v_owner_name, v_event_title
            FROM event_mst e
            JOIN creator_profiles cp ON cp.id = e.profile_id
            WHERE e.event_id = v_target_parent_id;

            -- Count accepted collaborators AFTER the removals above
            SELECT COUNT(*) INTO v_collab_count
            FROM event_collaborators
            WHERE event_id   = v_target_parent_id
              AND status     = 'accepted'
              AND is_deleted = false;

            FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

                IF v_collab_id IS NULL THEN CONTINUE; END IF;

                -- Skip the event owner
                IF v_collab_id = v_owner_profile_id THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Find existing row (active or previously soft-deleted)
                SELECT id, is_deleted
                INTO v_existing_collab_id, v_existing_deleted
                FROM event_collaborators
                WHERE event_id   = v_target_parent_id
                  AND profile_id = v_collab_id
                LIMIT 1;

                -- Already active → no change needed, skip
                IF v_existing_collab_id IS NOT NULL AND v_existing_deleted = false THEN
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Max 5 accepted collaborators
                IF v_collab_count >= 5 THEN
                    v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                    CONTINUE;
                END IF;

                -- Validate the profile exists and is active
                SELECT user_id INTO v_invitee_user_id
                FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

                IF v_invitee_user_id IS NULL THEN
                    v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                    v_existing_collab_id := NULL;
                    CONTINUE;
                END IF;

                -- Re-invite (previously soft-deleted row exists)
                IF v_existing_collab_id IS NOT NULL THEN
                    UPDATE event_collaborators
                    SET status       = 'pending',
                        invited_by   = v_owner_profile_id,
                        invited_at   = now(),
                        responded_at = NULL,
                        updated_at   = now(),
                        is_deleted   = false,
                        deleted_at   = NULL
                    WHERE id = v_existing_collab_id;
                ELSE
                    -- New collaborator
                    INSERT INTO event_collaborators (id, event_id, profile_id, invited_by, status, invited_at, updated_at)
                    VALUES (gen_random_uuid(), v_target_parent_id, v_collab_id, v_owner_profile_id, 'pending', now(), now());
                END IF;

                -- Send notification
                INSERT INTO notifications (user_id, title, body, data)
                VALUES (
                    v_invitee_user_id,
                    'Collaboration Invite',
                    v_owner_name || ' invited you to collaborate on "' || v_event_title || '"',
                    json_build_object(
                        'type',                  'collaborator_invite',
                        'event_id',              v_target_parent_id,
                        'invited_profile_id',    v_collab_id,
                        'invited_by_profile_id', v_owner_profile_id
                    )
                );

                v_invitee_user_id    := NULL;
                v_existing_collab_id := NULL;

            END LOOP;

        END IF;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_success_message,
        'data', json_build_object(
            'skipped_collaborator_ids', v_skipped_ids
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```

---

## V1.0 Function (Deprecated)

```sql
-- Function: update_event
-- Group: Events
-- Endpoint: POST /rpc/update_event
-- Tables:   event_mst (UPDATE), event_platforms (DELETE+INSERT), event_recurring (UPDATE if recurring)
--           event_collaborators (INSERT/UPDATE if collaborative), notifications (INSERT if collaborative)
-- Doc: docs/api/events/update_event.md
--
-- COALESCE pattern — only fields that are passed (non-null) are updated.
-- p_scope: 'all' (default) = update parent + all occurrences
--          'this'          = per-occurrence scalar/platform overrides; series-level fields
--                            (is_collaborative, collaborator_ids) auto-route to the parent
-- p_platforms:        null = don't touch | [] = clear all | [...] = replace
-- p_recurring_days:   null or [] = no rule change | [...] = update + regen ('all' scope only)
-- p_collaborator_ids: null or [] = no invites    | [...] = append invites (parent-level)
-- p_is_collaborative: always parent-level (applied to parent + all children when set)
--
-- 'this' scope behaviour:
--   • Scalar / platform changes apply ONLY to this child occurrence
--   • is_overridden = true is set only if at least one scalar or platform change was passed
--   • Series-level fields (is_collaborative, collaborator_ids) are routed to the parent
--   • Recurring rule changes (p_recurring_days non-empty) are rejected — regen would
--     delete this child row, defeating the per-occurrence intent
--
-- IMPORTANT — DEPLOYMENT
-- PostgreSQL identifies functions by name + argument-type signature.
-- CREATE OR REPLACE only replaces a function with the exact same signature;
-- if the parameter list ever changes, the old version stays around as a parallel
-- overload and PostgREST may keep routing requests to it. Drop everything first:
--
--   DO $$
--   DECLARE r record;
--   BEGIN
--     FOR r IN
--       SELECT p.oid::regprocedure AS sig
--       FROM pg_proc p
--       JOIN pg_namespace n ON n.oid = p.pronamespace
--       WHERE p.proname = 'update_event' AND n.nspname = 'public'
--     LOOP
--       EXECUTE 'DROP FUNCTION ' || r.sig || ' CASCADE';
--     END LOOP;
--   END $$;
--
-- After deploying, reload PostgREST's schema cache:
--
--   NOTIFY pgrst, 'reload schema';

CREATE OR REPLACE FUNCTION update_event(
    p_event_id             uuid,
    p_user_id              uuid,
    p_scope                text     DEFAULT 'all',
    -- Core event fields
    p_title                text     DEFAULT NULL,
    p_description          text     DEFAULT NULL,
    p_event_date           date     DEFAULT NULL,
    p_event_time           time     DEFAULT NULL,
    p_event_end_time       time     DEFAULT NULL,
    p_timezone             text     DEFAULT NULL,
    p_livestream           boolean  DEFAULT NULL,
    p_video                boolean  DEFAULT NULL,
    p_is_collaborative     boolean  DEFAULT NULL,
    p_collaborator_ids     uuid[]   DEFAULT NULL,
    p_platforms            jsonb    DEFAULT NULL,
    -- Recurring fields (pass p_recurring_days non-empty to trigger rule update + regen)
    p_recurring_days       text[]   DEFAULT NULL,
    p_recurring_type       text     DEFAULT NULL,
    p_recurring_interval   int      DEFAULT NULL,
    p_recurring_start_date date     DEFAULT NULL,
    p_recurring_end_date   date     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    -- Intent flags
    v_scope             text;
    v_update_recurring  boolean;
    v_update_collabs    boolean;
    v_has_scalar        boolean;
    v_has_platforms     boolean;
    v_occurrence_change boolean;

    v_platform          jsonb;

    -- Parent resolution
    v_parent_event_id    uuid;
    v_target_parent_id   uuid;

    -- End-time validation
    v_existing_event_time     time;
    v_existing_event_end_time time;
    v_final_event_time        time;
    v_final_event_end_time    time;

    -- Recurring rule build-up
    v_rec_days      text[];
    v_rec_type      text;
    v_rec_interval  int;
    v_rec_start     date;
    v_rec_end       date;
    v_safe_end      date;

    -- Child generation
    v_profile_id         uuid;
    v_title              text;
    v_description        text;
    v_event_time         time;
    v_event_end_time     time;
    v_event_tz           text;
    v_livestream         boolean;
    v_video              boolean;
    v_is_collaborative   boolean;
    v_day_name           text;
    v_dow_target         int;
    v_dow_start          int;
    v_days_ahead         int;
    v_first_occ          date;
    v_occ_date           date;
    v_month_start        date;
    v_month_end          date;
    v_dow_month_end      int;

    -- Collaborator invites
    v_owner_profile_id   uuid;
    v_owner_name         text;
    v_event_title        text;
    v_collab_id          uuid;
    v_invitee_user_id    uuid;
    v_skipped_ids        uuid[];
    v_collab_count       int;
    v_existing_collab_id uuid;
    v_existing_deleted   boolean;
    v_effective_is_collab boolean;

    -- Success message (chosen by branch)
    v_success_message    text;
BEGIN

    -- ── 1. Required params ────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── 2. Normalise scope ────────────────────────────────────────────────────
    v_scope := COALESCE(NULLIF(trim(p_scope), ''), 'all');
    IF v_scope NOT IN ('all', 'this') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be ''all'' or ''this''');
    END IF;

    -- ── 3. Intent flags ───────────────────────────────────────────────────────
    -- Empty arrays are equivalent to NULL (no intent to change).
    v_update_recurring := p_recurring_days   IS NOT NULL
                          AND COALESCE(array_length(p_recurring_days, 1), 0) > 0;
    v_update_collabs   := p_collaborator_ids IS NOT NULL
                          AND COALESCE(array_length(p_collaborator_ids, 1), 0) > 0;

    -- Scope='this' only sets is_overridden when there's a real per-occurrence change
    v_has_scalar   := p_title          IS NOT NULL OR p_description   IS NOT NULL
                   OR p_event_date     IS NOT NULL OR p_event_time    IS NOT NULL
                   OR p_event_end_time IS NOT NULL OR p_timezone      IS NOT NULL
                   OR p_livestream     IS NOT NULL OR p_video         IS NOT NULL;
    v_has_platforms     := p_platforms IS NOT NULL;
    v_occurrence_change := v_has_scalar OR v_has_platforms;

    -- ── 4. Ownership check (owner only) ──────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = p_event_id
          AND cp.user_id = p_user_id
          AND cp.status  = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── 5. Resolve parent event ──────────────────────────────────────────────
    -- v_parent_event_id = NULL  → p_event_id is a parent or non-recurring event
    -- v_parent_event_id = uuid  → p_event_id is a child occurrence
    SELECT parent_event_id INTO v_parent_event_id
    FROM event_mst WHERE event_id = p_event_id;

    v_target_parent_id := COALESCE(v_parent_event_id, p_event_id);

    -- ── 6. Effective scope: demote 'this' to 'all' when there's nothing to scope ─
    -- 'this' is only meaningful for a child occurrence row of a recurring series.
    -- If the caller passes 'this' with a non-recurring event or the series parent,
    -- silently treat it as 'all' rather than erroring — there are no other rows to
    -- distinguish from. This makes the SP forgiving when the client doesn't know
    -- (or doesn't care) whether the event is recurring.
    IF v_scope = 'this' AND v_parent_event_id IS NULL THEN
        v_scope := 'all';
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH A: p_scope = 'this' — per-occurrence scalar/platform overrides
    -- Reached only when v_parent_event_id IS NOT NULL (true child occurrence).
    -- Series-level fields (is_collaborative, collaborator_ids) are handled by
    -- the shared section after this branch.
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'this' THEN

        -- Recurring rule changes regenerate all children — would delete this row
        IF v_update_recurring THEN
            RETURN json_build_object('status', false, 'message',
                'Recurring schedule cannot be changed for a single occurrence — use scope ''all''');
        END IF;

        -- End-time validation (against this child's current values)
        IF v_has_scalar THEN
            SELECT event_time, event_end_time
            INTO v_existing_event_time, v_existing_event_end_time
            FROM event_mst WHERE event_id = p_event_id;

            v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
            v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

            IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
                RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
            END IF;
        END IF;

        -- Platform validation (only when non-empty; [] means "clear")
        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (
                    SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint
                )
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        -- Update this child's scalar fields — is_overridden only flips true when
        -- there is an actual per-occurrence change to protect from later 'all' wipes.
        IF v_occurrence_change THEN
            UPDATE event_mst
            SET title          = COALESCE(p_title,          title),
                description    = COALESCE(p_description,    description),
                event_date     = COALESCE(p_event_date,     event_date),
                event_time     = COALESCE(p_event_time,     event_time),
                event_end_time = COALESCE(p_event_end_time, event_end_time),
                event_timezone = COALESCE(p_timezone,       event_timezone),
                livestream     = COALESCE(p_livestream,     livestream),
                video          = COALESCE(p_video,          video),
                is_overridden  = true,
                updated_at     = now()
            WHERE event_id = p_event_id;
        END IF;

        -- Platforms override on this child
        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = p_event_id;
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (
                        gen_random_uuid(),
                        p_event_id,
                        (v_platform->>'platform_id')::int4,
                        v_platform->>'stream_url',
                        now()
                    );
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event occurrence updated successfully';

    ELSE
    -- ══════════════════════════════════════════════════════════════════════════
    -- BRANCH B: p_scope = 'all' — update parent + propagate to all occurrences
    -- ══════════════════════════════════════════════════════════════════════════

        -- End-time validation (against parent's current values)
        SELECT event_time, event_end_time
        INTO v_existing_event_time, v_existing_event_end_time
        FROM event_mst
        WHERE event_id = v_target_parent_id;

        v_final_event_time     := COALESCE(p_event_time,     v_existing_event_time);
        v_final_event_end_time := COALESCE(p_event_end_time, v_existing_event_end_time);

        IF v_final_event_end_time IS NOT NULL AND v_final_event_end_time = v_final_event_time THEN
            RETURN json_build_object('status', false, 'message', 'Event end time cannot be the same as event start time');
        END IF;

        -- Platform validation
        IF p_platforms IS NOT NULL AND jsonb_array_length(p_platforms) > 0 THEN
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE NOT EXISTS (
                    SELECT 1 FROM platforms p WHERE p.plat_id = (pl->>'platform_id')::bigint
                )
            ) THEN
                RETURN json_build_object('status', false, 'message', 'One or more platform IDs are invalid');
            END IF;
            IF EXISTS (
                SELECT 1 FROM jsonb_array_elements(p_platforms) AS pl
                WHERE pl->>'stream_url' IS NULL OR trim(pl->>'stream_url') = ''
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Stream URL is required for each platform');
            END IF;
        END IF;

        -- Recurring validation (only when v_update_recurring)
        IF v_update_recurring THEN

            IF EXISTS (
                SELECT 1 FROM unnest(p_recurring_days) AS d(day)
                WHERE d.day NOT IN ('Mon','Tue','Wed','Thu','Fri','Sat','Sun')
            ) THEN
                RETURN json_build_object('status', false, 'message', 'Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun');
            END IF;

            SELECT recurring_type, recurring_interval, recurring_start_date, recurring_end_date
            INTO v_rec_type, v_rec_interval, v_rec_start, v_rec_end
            FROM event_recurring WHERE event_id = v_target_parent_id;

            v_rec_days     := p_recurring_days;
            v_rec_type     := COALESCE(p_recurring_type,       v_rec_type);
            v_rec_start    := COALESCE(p_recurring_start_date, v_rec_start);
            v_rec_end      := COALESCE(p_recurring_end_date,   v_rec_end);

            IF v_rec_type IS NULL OR v_rec_type NOT IN ('weekly', 'first', 'last') THEN
                RETURN json_build_object('status', false, 'message', 'recurring_type must be weekly, first, or last');
            END IF;

            -- recurring_interval is only meaningful for 'weekly'. For first/last we force
            -- NULL so a stored interval from a previous 'weekly' rule doesn't leak across
            -- the type change. For weekly, fall back to the existing stored interval if
            -- the caller didn't provide one.
            IF v_rec_type IN ('first', 'last') THEN
                v_rec_interval := NULL;
            ELSE
                v_rec_interval := COALESCE(p_recurring_interval, v_rec_interval);

                IF v_rec_interval IS NULL THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval is required for weekly type');
                END IF;
                IF v_rec_interval < 1 OR v_rec_interval > 12 THEN
                    RETURN json_build_object('status', false, 'message', 'recurring_interval must be between 1 and 12');
                END IF;
            END IF;

            IF v_rec_start IS NULL THEN
                RETURN json_build_object('status', false, 'message', 'Recurring start date is required');
            END IF;

            IF v_rec_end IS NOT NULL AND v_rec_end <= v_rec_start THEN
                RETURN json_build_object('status', false, 'message', 'Recurring end date must be after start date');
            END IF;

        END IF;

        -- Update parent event_mst (is_collaborative handled by shared section below)
        UPDATE event_mst
        SET title             = COALESCE(p_title,            title),
            description       = COALESCE(p_description,      description),
            event_date        = COALESCE(p_event_date,       event_date),
            event_time        = COALESCE(p_event_time,       event_time),
            event_end_time    = COALESCE(p_event_end_time,   event_end_time),
            event_timezone    = COALESCE(p_timezone,         event_timezone),
            livestream        = COALESCE(p_livestream,       livestream),
            video             = COALESCE(p_video,            video),
            updated_at        = now()
        WHERE event_id = v_target_parent_id;

        -- Propagate scalar changes to child rows; reset is_overridden so they inherit again
        UPDATE event_mst
        SET title            = COALESCE(p_title,            title),
            description      = COALESCE(p_description,      description),
            event_time       = COALESCE(p_event_time,       event_time),
            event_end_time   = COALESCE(p_event_end_time,   event_end_time),
            event_timezone   = COALESCE(p_timezone,         event_timezone),
            livestream       = COALESCE(p_livestream,       livestream),
            video            = COALESCE(p_video,            video),
            is_overridden    = false,
            updated_at       = now()
        WHERE parent_event_id = v_target_parent_id;

        -- Platforms (parent + clear per-child overrides)
        IF p_platforms IS NOT NULL THEN
            DELETE FROM event_platforms WHERE event_id = v_target_parent_id;
            DELETE FROM event_platforms
            WHERE event_id IN (
                SELECT event_id FROM event_mst WHERE parent_event_id = v_target_parent_id
            );
            IF jsonb_array_length(p_platforms) > 0 THEN
                FOR v_platform IN SELECT * FROM jsonb_array_elements(p_platforms)
                LOOP
                    INSERT INTO event_platforms (id, event_id, platform_id, stream_url, created_at)
                    VALUES (
                        gen_random_uuid(),
                        v_target_parent_id,
                        (v_platform->>'platform_id')::int4,
                        v_platform->>'stream_url',
                        now()
                    );
                END LOOP;
            END IF;
        END IF;

        v_success_message := 'Event updated successfully';

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: is_collaborative (always parent-level, applies to both scopes)
    -- ══════════════════════════════════════════════════════════════════════════
    IF p_is_collaborative IS NOT NULL THEN
        UPDATE event_mst
        SET is_collaborative = p_is_collaborative,
            updated_at       = now()
        WHERE event_id = v_target_parent_id
           OR parent_event_id = v_target_parent_id;
    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: recurring rule + regen (Branch B only)
    -- Done AFTER is_collaborative so newly-regenerated children inherit the new flag.
    -- ══════════════════════════════════════════════════════════════════════════
    IF v_scope = 'all' AND v_update_recurring THEN

        v_safe_end := COALESCE(v_rec_end, v_rec_start + INTERVAL '3 months');
        v_rec_end  := v_safe_end;

        UPDATE event_recurring
        SET recurring_days       = v_rec_days,
            recurring_type       = v_rec_type,
            recurring_interval   = v_rec_interval,
            recurring_start_date = v_rec_start,
            recurring_end_date   = v_rec_end,
            renewal_notified_at  = NULL
        WHERE event_id = v_target_parent_id;

        -- Delete all existing child rows (ON DELETE CASCADE clears per-child platforms)
        DELETE FROM event_mst WHERE parent_event_id = v_target_parent_id;

        -- Fetch parent values for regen
        SELECT profile_id, title, description, event_time, event_end_time,
               event_timezone, livestream, video, is_collaborative
        INTO v_profile_id, v_title, v_description, v_event_time, v_event_end_time,
             v_event_tz, v_livestream, v_video, v_is_collaborative
        FROM event_mst WHERE event_id = v_target_parent_id;

        IF v_rec_type = 'weekly' THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP

                v_dow_target := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;
                v_dow_start  := EXTRACT(DOW FROM v_rec_start)::int;
                v_days_ahead := (7 + v_dow_target - v_dow_start) % 7;
                v_first_occ  := v_rec_start + v_days_ahead;

                v_occ_date := v_first_occ;
                WHILE v_occ_date <= v_safe_end LOOP
                    INSERT INTO event_mst (
                        event_id, profile_id, parent_event_id,
                        title, description,
                        event_date, event_time, event_end_time, event_timezone,
                        livestream, video, is_collaborative, is_recurring,
                        created_at, updated_at
                    )
                    VALUES (
                        gen_random_uuid(), v_profile_id, v_target_parent_id,
                        v_title, v_description,
                        v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                        v_livestream, v_video, v_is_collaborative, true,
                        now(), now()
                    );
                    v_occ_date := v_occ_date + (7 * v_rec_interval);
                END LOOP;

            END LOOP;

        ELSIF v_rec_type IN ('first', 'last') THEN

            FOREACH v_day_name IN ARRAY v_rec_days LOOP

                v_dow_target  := CASE v_day_name
                    WHEN 'Sun' THEN 0 WHEN 'Mon' THEN 1 WHEN 'Tue' THEN 2
                    WHEN 'Wed' THEN 3 WHEN 'Thu' THEN 4 WHEN 'Fri' THEN 5
                    WHEN 'Sat' THEN 6
                END;

                v_month_start := DATE_TRUNC('month', v_rec_start)::date;

                WHILE v_month_start <= v_safe_end LOOP

                    IF v_rec_type = 'first' THEN
                        v_days_ahead := (7 + v_dow_target - EXTRACT(DOW FROM v_month_start)::int) % 7;
                        v_occ_date   := v_month_start + v_days_ahead;
                    ELSE
                        v_month_end     := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date - 1;
                        v_dow_month_end := EXTRACT(DOW FROM v_month_end)::int;
                        v_occ_date      := v_month_end - ((7 + v_dow_month_end - v_dow_target) % 7);
                    END IF;

                    IF v_occ_date >= v_rec_start AND v_occ_date <= v_safe_end THEN
                        INSERT INTO event_mst (
                            event_id, profile_id, parent_event_id,
                            title, description,
                            event_date, event_time, event_end_time, event_timezone,
                            livestream, video, is_collaborative, is_recurring,
                            created_at, updated_at
                        )
                        VALUES (
                            gen_random_uuid(), v_profile_id, v_target_parent_id,
                            v_title, v_description,
                            v_occ_date, v_event_time, v_event_end_time, v_event_tz,
                            v_livestream, v_video, v_is_collaborative, true,
                            now(), now()
                        );
                    END IF;

                    v_month_start := (DATE_TRUNC('month', v_month_start) + INTERVAL '1 month')::date;
                END LOOP;

            END LOOP;

        END IF;

    END IF;

    -- ══════════════════════════════════════════════════════════════════════════
    -- SHARED: collaborator invites (always parent-level, PATCH append only)
    -- Works the same for scope='this' and scope='all' — the collab row lives
    -- on the parent regardless of which scope the caller used.
    -- ══════════════════════════════════════════════════════════════════════════
    v_skipped_ids := ARRAY[]::uuid[];

    IF v_update_collabs THEN

        -- Effective is_collaborative — read from parent AFTER any earlier UPDATE
        v_effective_is_collab := COALESCE(
            p_is_collaborative,
            (SELECT is_collaborative FROM event_mst WHERE event_id = v_target_parent_id)
        );

        IF v_effective_is_collab = false THEN
            RETURN json_build_object('status', false, 'message', 'Cannot add collaborators when is_collaborative is false');
        END IF;

        SELECT cp.id, cp.profile_name, e.title
        INTO v_owner_profile_id, v_owner_name, v_event_title
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id = v_target_parent_id;

        SELECT COUNT(*) INTO v_collab_count
        FROM event_collaborators
        WHERE event_id   = v_target_parent_id
          AND status     = 'accepted'
          AND is_deleted = false;

        FOREACH v_collab_id IN ARRAY p_collaborator_ids LOOP

            IF v_collab_id IS NULL THEN
                CONTINUE;
            END IF;

            IF v_collab_id = v_owner_profile_id THEN
                v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                CONTINUE;
            END IF;

            IF v_collab_count >= 5 THEN
                v_skipped_ids := array_append(v_skipped_ids, v_collab_id);
                CONTINUE;
            END IF;

            SELECT id, is_deleted
            INTO v_existing_collab_id, v_existing_deleted
            FROM event_collaborators
            WHERE event_id   = v_target_parent_id
              AND profile_id = v_collab_id
            LIMIT 1;

            IF v_existing_collab_id IS NOT NULL AND v_existing_deleted = false THEN
                v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                v_existing_collab_id := NULL;
                CONTINUE;
            END IF;

            SELECT user_id INTO v_invitee_user_id
            FROM creator_profiles WHERE id = v_collab_id AND status = 'active';

            IF v_invitee_user_id IS NULL THEN
                v_skipped_ids        := array_append(v_skipped_ids, v_collab_id);
                v_existing_collab_id := NULL;
                CONTINUE;
            END IF;

            IF v_existing_collab_id IS NOT NULL THEN
                UPDATE event_collaborators
                SET status       = 'pending',
                    invited_by   = v_owner_profile_id,
                    invited_at   = now(),
                    responded_at = NULL,
                    updated_at   = now(),
                    is_deleted   = false,
                    deleted_at   = NULL
                WHERE id = v_existing_collab_id;
            ELSE
                INSERT INTO event_collaborators (
                    id, event_id, profile_id, invited_by, status, invited_at, updated_at
                )
                VALUES (
                    gen_random_uuid(), v_target_parent_id, v_collab_id,
                    v_owner_profile_id, 'pending', now(), now()
                );
            END IF;

            INSERT INTO notifications (user_id, title, body, data)
            VALUES (
                v_invitee_user_id,
                'Collaboration Invite',
                v_owner_name || ' invited you to collaborate on "' || v_event_title || '"',
                json_build_object(
                    'type',                  'collaborator_invite',
                    'event_id',              v_target_parent_id,
                    'invited_profile_id',    v_collab_id,
                    'invited_by_profile_id', v_owner_profile_id
                )
            );

            v_invitee_user_id    := NULL;
            v_existing_collab_id := NULL;

        END LOOP;

    END IF;

    RETURN json_build_object(
        'status',  true,
        'message', v_success_message,
        'data', json_build_object(
            'skipped_collaborator_ids', v_skipped_ids
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```
