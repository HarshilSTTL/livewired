# `delete_event`

```sql
-- Function: delete_event
-- Group: Events
-- Endpoint: POST /rpc/delete_event
-- Tables:   event_mst (UPDATE), event_reminders (UPDATE), event_collaborators (UPDATE)
-- Doc: docs/api/events/delete_event.md
--
-- Soft-deletes an event with scope control for recurring series.
-- Uses same scope logic as update_event.
--
-- Scope behavior:
--   'this'  — delete only a single occurrence (child row) or single non-recurring event
--           — if parent_event_id IS NULL (parent or non-recurring), error
--   'all'   — delete entire recurring series (parent + all children) OR single event
--           — routes intelligently based on event structure
--
-- ⚠️ DEPLOYMENT: After deploying this function, run in Supabase SQL editor:
--    NOTIFY pgrst, 'reload schema';
--    This reloads PostgREST schema cache and activates the new function.

CREATE OR REPLACE FUNCTION delete_event(
    p_event_id uuid,
    p_user_id  uuid,
    p_scope    text DEFAULT 'all'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_parent_id      uuid;
    v_profile_id     uuid;
    v_owner_id       uuid;
    v_is_recurring   boolean;
    v_event_title    text;
    v_event_count    int;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- ── Validate scope ───────────────────────────────────────────────────────
    IF p_scope NOT IN ('this', 'all') THEN
        RETURN json_build_object('status', false, 'message', 'p_scope must be either "this" or "all"');
    END IF;

    -- ── Locate the event ─────────────────────────────────────────────────────
    SELECT parent_event_id, profile_id, is_recurring, title
    INTO v_parent_id, v_profile_id, v_is_recurring, v_event_title
    FROM event_mst
    WHERE event_id = p_event_id
    LIMIT 1;

    IF v_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event not found');
    END IF;

    -- ── Authorization: verify event owner ──────────────────────────────────
    SELECT user_id INTO v_owner_id FROM creator_profiles WHERE id = v_profile_id;
    IF v_owner_id <> p_user_id THEN
        RETURN json_build_object('status', false, 'message', 'You do not have permission to delete this event');
    END IF;

    -- ──────────────────────────────────────────────────────────────────────────
    -- SCOPE='THIS' — Delete single occurrence only
    -- ──────────────────────────────────────────────────────────────────────────
    IF p_scope = 'this' THEN

        -- Can only delete 'this' on a child occurrence (parent_event_id IS NOT NULL)
        IF v_parent_id IS NULL THEN
            RETURN json_build_object(
                'status',  false,
                'message', 'Cannot delete "this" on a parent or non-recurring event. Use scope="all" to delete the entire series.'
            );
        END IF;

        -- Soft delete this child occurrence only
        UPDATE event_mst
        SET is_deleted = true, deleted_at = now()
        WHERE event_id = p_event_id;

        -- Soft delete associated reminders and collaborators
        UPDATE event_reminders
        SET is_deleted = true, deleted_at = now()
        WHERE event_id = p_event_id;

        UPDATE event_collaborators
        SET is_deleted = true, deleted_at = now()
        WHERE event_id = p_event_id;

        RETURN json_build_object(
            'status',  true,
            'message', 'Occurrence deleted',
            'data', json_build_object(
                'event_id',    p_event_id,
                'scope',       'this',
                'title',       v_event_title,
                'deleted_at',  now()
            )
        );

    -- ──────────────────────────────────────────────────────────────────────────
    -- SCOPE='ALL' — Delete entire series or single event
    -- ──────────────────────────────────────────────────────────────────────────
    ELSIF p_scope = 'all' THEN

        -- Determine what to delete: parent + all children, or just this event
        DECLARE
            v_target_id uuid;
        BEGIN
            -- If this is a child, delete the parent (which cascades logic)
            -- If this is a parent or non-recurring, delete this event
            v_target_id := COALESCE(v_parent_id, p_event_id);

            -- Soft delete the target event (parent if child, self if parent/non-recurring)
            UPDATE event_mst
            SET is_deleted = true, deleted_at = now()
            WHERE event_id = v_target_id;

            -- Soft delete all child occurrences if this is a parent
            UPDATE event_mst
            SET is_deleted = true, deleted_at = now()
            WHERE parent_event_id = v_target_id;

            -- Soft delete all associated reminders
            UPDATE event_reminders
            SET is_deleted = true, deleted_at = now()
            WHERE event_id IN (
                SELECT event_id FROM event_mst
                WHERE event_id = v_target_id OR parent_event_id = v_target_id
            );

            -- Soft delete all associated collaborators
            UPDATE event_collaborators
            SET is_deleted = true, deleted_at = now()
            WHERE event_id IN (
                SELECT event_id FROM event_mst
                WHERE event_id = v_target_id OR parent_event_id = v_target_id
            );

            -- Count deleted occurrences
            SELECT count(*)
            INTO v_event_count
            FROM event_mst
            WHERE (event_id = v_target_id OR parent_event_id = v_target_id)
              AND is_deleted = true;

            RETURN json_build_object(
                'status',  true,
                'message', CASE
                               WHEN v_is_recurring THEN 'Recurring series deleted (' || v_event_count || ' occurrences)'
                               ELSE 'Event deleted'
                           END,
                'data', json_build_object(
                    'event_id',        p_event_id,
                    'parent_event_id', v_parent_id,
                    'scope',           'all',
                    'title',           v_event_title,
                    'occurrences_deleted', v_event_count,
                    'deleted_at',      now()
                )
            );
        END;

    END IF;

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
