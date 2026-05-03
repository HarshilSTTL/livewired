# `remove_collaborator`

```sql
-- Function: remove_collaborator
-- Group:    Events
-- Endpoint: POST /rpc/remove_collaborator
-- Tables:   event_collaborators (UPDATE — soft delete)
-- Doc:      docs/api/events/remove_collaborator.md
--
-- Only the event owner can remove a collaborator.
-- Soft deletes the event_collaborators row (is_deleted = true).
-- The owner can re-invite the same profile afterwards via invite_collaborator.

CREATE OR REPLACE FUNCTION remove_collaborator(
    p_event_id                uuid,
    p_requesting_user_id      uuid,
    p_collaborator_profile_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite_id uuid;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_requesting_user_id IS NULL OR p_collaborator_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id, p_requesting_user_id, and p_collaborator_profile_id are all required');
    END IF;

    -- ── Verify requesting user owns this event ────────────────────────────────
    IF NOT EXISTS (
        SELECT 1
        FROM event_mst e
        JOIN creator_profiles cp ON cp.id = e.profile_id
        WHERE e.event_id   = p_event_id
          AND cp.user_id   = p_requesting_user_id
          AND cp.status    = 'active'
          AND e.is_deleted = false
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── Find the active collaborator row ──────────────────────────────────────
    SELECT id INTO v_invite_id
    FROM event_collaborators
    WHERE event_id   = p_event_id
      AND profile_id = p_collaborator_profile_id
      AND is_deleted = false;

    IF v_invite_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Collaborator not found for this event');
    END IF;

    -- ── Soft delete ───────────────────────────────────────────────────────────
    UPDATE event_collaborators
    SET is_deleted = true,
        deleted_at = now(),
        updated_at = now()
    WHERE id = v_invite_id;

    RETURN json_build_object('status', true, 'message', 'Collaborator removed successfully');

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```
