# `update_profile_event_notification`

```sql
-- Function: update_profile_event_notification
-- Group: Notifications
-- Endpoint: POST /rpc/update_profile_event_notification
-- Tables:   profile_event_notifications (INSERT / UPDATE)
-- Doc: docs/api/notifications/update_profile_event_notification.md
--
-- Allows a profile owner to configure global event notifications for their profile.
-- Notifications fire for ANY event created on the profile, based on their settings.
--
-- notification_type:
--   'before_event'    — fires p_reminder_minutes before event starts
--   'on_event_start'  — fires when event starts (reminder_minutes ignored)
--   'both'            — fires both before AND at start time

CREATE OR REPLACE FUNCTION update_profile_event_notification(
    p_user_id               uuid,
    p_profile_id            uuid,
    p_notification_enabled  boolean,
    p_notification_type     text     DEFAULT 'before_event',
    p_reminder_minutes      int      DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_final_minutes int;
    v_owner_id      uuid;
BEGIN

    -- ── Required params ──────────────────────────────────────────────────────
    IF p_user_id IS NULL OR p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id and p_profile_id are required');
    END IF;

    IF p_notification_enabled IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_notification_enabled is required');
    END IF;

    -- ── Validate notification_type ───────────────────────────────────────────
    IF p_notification_type NOT IN ('before_event', 'on_event_start', 'both') THEN
        RETURN json_build_object('status', false, 'message', 'p_notification_type must be one of: before_event, on_event_start, both');
    END IF;

    -- ── Range check reminder_minutes (only when type includes 'before_event') ──
    IF p_notification_type IN ('before_event', 'both') THEN
        IF p_reminder_minutes IS NOT NULL THEN
            IF p_reminder_minutes < 1 OR p_reminder_minutes > 1440 THEN
                RETURN json_build_object('status', false, 'message', 'p_reminder_minutes must be between 1 and 1440');
            END IF;
        END IF;
    END IF;

    -- ── Verify profile ownership ─────────────────────────────────────────────
    SELECT user_id INTO v_owner_id FROM creator_profiles WHERE id = p_profile_id;
    IF v_owner_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    IF v_owner_id <> p_user_id THEN
        RETURN json_build_object('status', false, 'message', 'You do not own this profile');
    END IF;

    -- ── Determine final reminder_minutes ─────────────────────────────────────
    v_final_minutes := COALESCE(p_reminder_minutes, 10);

    -- ── Insert or update setting ─────────────────────────────────────────────
    INSERT INTO profile_event_notifications (user_id, profile_id, notification_enabled, notification_type, reminder_minutes)
    VALUES (p_user_id, p_profile_id, p_notification_enabled, p_notification_type, v_final_minutes)
    ON CONFLICT (user_id, profile_id)
    DO UPDATE SET
        notification_enabled = p_notification_enabled,
        notification_type = p_notification_type,
        reminder_minutes = v_final_minutes,
        updated_at = now();

    RETURN json_build_object(
        'status',  true,
        'message', CASE
                       WHEN p_notification_enabled THEN 'Profile event notifications enabled'
                       ELSE 'Profile event notifications disabled'
                   END,
        'data', json_build_object(
            'profile_id',             p_profile_id,
            'notification_enabled',   p_notification_enabled,
            'notification_type',      p_notification_type,
            'reminder_minutes',       v_final_minutes
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
