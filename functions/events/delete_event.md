# `delete_event`

```sql
-- Function: delete_event
-- Group: Events
-- Endpoint: POST /rpc/delete_event
-- Doc: docs/api/events/delete_event.md
-- Hard delete. CASCADE on parent_event_id removes all child occurrences.
-- CASCADE also removes event_platforms and event_recurring rows.
-- Ownership check: event must belong to a profile owned by p_user_id.

CREATE OR REPLACE FUNCTION delete_event(
    p_event_id uuid,
    p_user_id  uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    IF p_event_id IS NULL OR p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id and p_user_id are required');
    END IF;

    -- Delete with ownership check in one statement
    -- ON DELETE CASCADE handles:
    --   event_mst.parent_event_id  → deletes all child occurrence rows
    --   event_platforms.event_id   → deletes all platform links
    --   event_recurring.event_id   → deletes the recurrence rule
    DELETE FROM event_mst e
    USING creator_profiles cp
    WHERE e.event_id   = p_event_id
      AND e.profile_id = cp.id
      AND cp.user_id   = p_user_id;

    IF NOT FOUND THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    RETURN json_build_object('status', true, 'message', 'Event deleted successfully');

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
