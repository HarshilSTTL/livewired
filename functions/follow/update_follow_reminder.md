# `update_follow_reminder`

```sql
-- Function: update_follow_reminder
-- Group: Follow
-- Endpoint: POST /rpc/update_follow_reminder
-- Tables:   follows (UPDATE)
-- Doc: docs/api/follow/update_follow_reminder.md
--
-- Lets a follower toggle the YouTube-style bell for a profile they follow and choose
-- how many minutes before each event to be reminded. Applies to all events on the
-- profile, including every occurrence of a recurring series.
--
-- Caller must have an active follow row (is_active = true) for the target profile.
-- Pre-existing reminder_minutes is kept if p_reminder_minutes is NULL.

CREATE OR REPLACE FUNCTION update_follow_reminder(
    p_user_id          uuid,
    p_profile_id       uuid,
    p_reminder_enabled boolean,
    p_reminder_minutes int     DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_id      uuid;
    v_existing_minutes int;
    v_final_minutes    int;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_user_id IS NULL OR p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_profile_id are required');
    END IF;

    IF p_reminder_enabled IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_reminder_enabled is required');
    END IF;

    -- ── Range check (only when caller actually provided a value) ─────────────
    IF p_reminder_minutes IS NOT NULL THEN
        IF p_reminder_minutes < 1 OR p_reminder_minutes > 1440 THEN
            RETURN json_build_object('status', false, 'message', 'p_reminder_minutes must be between 1 and 1440');
        END IF;
    END IF;

    -- ── Locate the follow row ────────────────────────────────────────────────
    SELECT id, reminder_minutes
    INTO v_existing_id, v_existing_minutes
    FROM follows
    WHERE user_id    = p_user_id
      AND profile_id = p_profile_id
      AND is_active  = true
    LIMIT 1;

    IF v_existing_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'You must follow this profile before setting a reminder');
    END IF;

    -- ── Final reminder_minutes: keep existing when caller didn't pass one ────
    v_final_minutes := COALESCE(p_reminder_minutes, v_existing_minutes);

    -- ── Update ───────────────────────────────────────────────────────────────
    UPDATE follows
    SET reminder_enabled = p_reminder_enabled,
        reminder_minutes = v_final_minutes
    WHERE id = v_existing_id;

    RETURN json_build_object(
        'status',  true,
        'message', CASE
                       WHEN p_reminder_enabled THEN 'Reminders enabled for this profile'
                       ELSE 'Reminders disabled for this profile'
                   END,
        'data', json_build_object(
            'reminder_enabled', p_reminder_enabled,
            'reminder_minutes', v_final_minutes
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
