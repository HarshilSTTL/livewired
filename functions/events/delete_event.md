# `delete_event`

```sql
-- Function: delete_event
-- Group: Events
-- Endpoint: POST /rpc/delete_event
-- Doc: docs/api/events/delete_event.md
-- Soft delete. Sets is_deleted = true on the event and all child occurrences.
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

    -- Ownership + existence check (owner only)
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id   = p_event_id
          AND cp.user_id   = p_user_id
          AND e.is_deleted = false
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- Soft delete the event (parent or standalone)
    UPDATE event_mst
    SET    is_deleted = true,
           deleted_at = now()
    WHERE  event_id   = p_event_id;

    -- Soft delete all recurring child occurrences
    UPDATE event_mst
    SET    is_deleted = true,
           deleted_at = now()
    WHERE  parent_event_id = p_event_id
      AND  is_deleted      = false;

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
