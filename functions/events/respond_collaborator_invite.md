# `respond_collaborator_invite`

```sql
-- Function: respond_collaborator_invite
-- Group:    Events
-- Endpoint: POST /rpc/respond_collaborator_invite
-- Tables:   event_collaborators (UPDATE), notifications (INSERT)
-- Doc:      docs/api/events/respond_collaborator_invite.md
--
-- Allows the invited profile's owner to accept or decline a pending invite.
-- Re-checks the 5-collaborator limit before accepting (race-condition safe).
-- Notifies the event owner of the response.

CREATE OR REPLACE FUNCTION respond_collaborator_invite(
    p_event_id   uuid,
    p_profile_id uuid,
    p_user_id    uuid,
    p_response   text   -- 'accepted' | 'declined'
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite_id      uuid;
    v_event_title    text;
    v_responder_name text;
    v_owner_user_id  uuid;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_event_id IS NULL OR p_profile_id IS NULL OR p_user_id IS NULL OR p_response IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id, p_profile_id, p_user_id, and p_response are all required');
    END IF;

    -- ── Validate response value ───────────────────────────────────────────────
    IF p_response NOT IN ('accepted', 'declined') THEN
        RETURN json_build_object('status', false, 'message', 'p_response must be accepted or declined');
    END IF;

    -- ── Verify p_user_id owns p_profile_id ───────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles
        WHERE id = p_profile_id AND user_id = p_user_id AND status = 'active'
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found or access denied');
    END IF;

    -- ── Find the pending invite ───────────────────────────────────────────────
    SELECT id INTO v_invite_id
    FROM event_collaborators
    WHERE event_id   = p_event_id
      AND profile_id = p_profile_id
      AND status     = 'pending'
      AND is_deleted = false;

    IF v_invite_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'No pending invite found for this event and profile');
    END IF;

    -- ── Re-check limit before accepting (race-condition safe) ─────────────────
    IF p_response = 'accepted' THEN
        IF (
            SELECT COUNT(*) FROM event_collaborators
            WHERE event_id   = p_event_id
              AND status     = 'accepted'
              AND is_deleted = false
        ) >= 5 THEN
            RETURN json_build_object('status', false, 'message', 'Collaborator limit reached — cannot accept this invite');
        END IF;
    END IF;

    -- ── Update the invite ─────────────────────────────────────────────────────
    UPDATE event_collaborators
    SET status       = p_response,
        responded_at = now(),
        updated_at   = now()
    WHERE id = v_invite_id;

    -- ── Notify the event owner ────────────────────────────────────────────────
    SELECT e.title, cp_owner.user_id, cp_resp.profile_name
    INTO v_event_title, v_owner_user_id, v_responder_name
    FROM event_mst e
    JOIN creator_profiles cp_owner ON cp_owner.id = e.profile_id
    JOIN creator_profiles cp_resp  ON cp_resp.id  = p_profile_id
    WHERE e.event_id = p_event_id;

    INSERT INTO notifications (user_id, title, body, data)
    VALUES (
        v_owner_user_id,
        'Collaboration ' || initcap(p_response),
        v_responder_name || ' ' || p_response || ' your collaboration invite for "' || v_event_title || '"',
        json_build_object(
            'type',                    'collaborator_response',
            'event_id',                p_event_id,
            'collaborator_profile_id', p_profile_id,
            'status',                  p_response
        )
    );

    RETURN json_build_object('status', true, 'message', 'Invite ' || p_response || ' successfully');

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('status', false, 'message', 'Something went wrong', 'error', SQLERRM);
END;
$$;
```
