# `invite_collaborator`

```sql
-- Function: invite_collaborator
-- Group:    Events
-- Endpoint: POST /rpc/invite_collaborator
-- Tables:   event_collaborators (INSERT / UPDATE), notifications (INSERT)
-- Doc:      docs/api/events/invite_collaborator.md
--
-- Sends a collaboration invite to any active creator profile.
-- Only the event owner can invite. Event must be is_collaborative = true.
-- Limit: max 5 accepted (non-deleted) collaborators per event.
-- Re-inviting a soft-deleted collaborator reactivates the existing row.

CREATE OR REPLACE FUNCTION invite_collaborator(
    p_event_id                uuid,
    p_inviting_user_id        uuid,
    p_collaborator_profile_id uuid
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_event_title         text;
    v_inviting_profile_id uuid;
    v_inviting_name       text;
    v_invitee_user_id     uuid;
    v_existing_id         uuid;
    v_existing_deleted    boolean;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_event_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event ID is required');
    END IF;
    IF p_inviting_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;
    IF p_collaborator_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Collaborator profile ID is required');
    END IF;

    -- ── Verify inviting user owns this event ──────────────────────────────────
    SELECT e.title, cp.id, cp.profile_name
    INTO v_event_title, v_inviting_profile_id, v_inviting_name
    FROM event_mst e
    JOIN creator_profiles cp ON cp.id = e.profile_id
    WHERE e.event_id   = p_event_id
      AND cp.user_id   = p_inviting_user_id
      AND cp.status    = 'active'
      AND e.is_deleted = false;

    IF v_inviting_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event not found or access denied');
    END IF;

    -- ── Verify event is marked as collaborative ───────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM event_mst
        WHERE event_id = p_event_id AND is_collaborative = true
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Event is not marked as collaborative');
    END IF;

    -- ── Prevent owner from inviting themselves ────────────────────────────────
    IF p_collaborator_profile_id = v_inviting_profile_id THEN
        RETURN json_build_object('status', false, 'message', 'You cannot invite yourself as a collaborator');
    END IF;

    -- ── Verify collaborator profile exists and is active ──────────────────────
    SELECT user_id INTO v_invitee_user_id
    FROM creator_profiles
    WHERE id = p_collaborator_profile_id AND status = 'active';

    IF v_invitee_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Collaborator profile not found or inactive');
    END IF;

    -- ── Check accepted collaborator limit (max 5) ─────────────────────────────
    IF (
        SELECT COUNT(*) FROM event_collaborators
        WHERE event_id   = p_event_id
          AND status     = 'accepted'
          AND is_deleted = false
    ) >= 5 THEN
        RETURN json_build_object('status', false, 'message', 'Collaborator limit reached (maximum 5 collaborators per event)');
    END IF;

    -- ── Check for existing row (active or soft-deleted) ───────────────────────
    SELECT id, is_deleted
    INTO v_existing_id, v_existing_deleted
    FROM event_collaborators
    WHERE event_id   = p_event_id
      AND profile_id = p_collaborator_profile_id
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
        IF v_existing_deleted = false THEN
            -- Active invite already exists (pending or accepted or declined)
            RETURN json_build_object('status', false, 'message', 'This profile has already been invited to collaborate on this event');
        ELSE
            -- Soft-deleted row: reactivate as a fresh pending invite
            UPDATE event_collaborators
            SET status       = 'pending',
                invited_by   = v_inviting_profile_id,
                invited_at   = now(),
                responded_at = NULL,
                updated_at   = now(),
                is_deleted   = false,
                deleted_at   = NULL
            WHERE id = v_existing_id;
        END IF;
    ELSE
        -- No prior row: fresh insert
        INSERT INTO event_collaborators (
            id, event_id, profile_id, invited_by, status, invited_at, updated_at
        )
        VALUES (
            gen_random_uuid(), p_event_id, p_collaborator_profile_id,
            v_inviting_profile_id, 'pending', now(), now()
        );
    END IF;

    -- ── Notify the invitee ────────────────────────────────────────────────────
    INSERT INTO notifications (user_id, title, body, data)
    VALUES (
        v_invitee_user_id,
        'Collaboration Invite',
        v_inviting_name || ' invited you to collaborate on "' || v_event_title || '"',
        json_build_object(
            'type',                  'collaborator_invite',
            'event_id',              p_event_id,
            'invited_by_profile_id', v_inviting_profile_id
        )
    );

    RETURN json_build_object('status', true, 'message', 'Invitation sent successfully');

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```
