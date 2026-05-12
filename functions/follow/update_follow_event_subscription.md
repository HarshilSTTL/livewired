# `update_follow_event_subscription`

```sql
-- Function: update_follow_event_subscription
-- Group:    follow
-- Endpoint: POST /rpc/update_follow_event_subscription
-- Tables:   follows (SELECT, UPDATE), creator_profiles (SELECT)
-- Doc:      docs/api/follow/update_follow_event_subscription.md
--
-- Purpose:  Allows followers to enable/disable and configure profile-level event subscriptions.
--           When enabled, follower receives notifications for ALL events on the profile
--           at the configured time (before event or exactly at start).
--           Manual event reminders suppress profile subscriptions for that event.
--
-- Design:
--   event_notification_enabled = false → subscription disabled
--   event_notification_enabled = true + event_notification_minutes = NULL → notify at event start
--   event_notification_enabled = true + event_notification_minutes = 5/10/15 → notify X min before
--
--   Settings persist across unfollow/re-follow cycles.
--   Applies to: ALL events (recurring + non-recurring) on profile
--   Suppressed by: manual event_reminders rows (manual takes precedence)

CREATE OR REPLACE FUNCTION update_follow_event_subscription(
    p_user_id                    uuid,
    p_profile_id                 uuid,
    p_event_notification_enabled boolean,
    p_event_notification_minutes int DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_follow_id uuid;
    v_profile_name text;
BEGIN

    -- ── Null guards ───────────────────────────────────────────────────────────
    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'User ID is required');
    END IF;

    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    -- ── Profile existence check ───────────────────────────────────────────────
    SELECT profile_name INTO v_profile_name
    FROM creator_profiles
    WHERE id = p_profile_id;

    IF v_profile_name IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    -- ── Follow relationship check ─────────────────────────────────────────────
    SELECT id INTO v_follow_id
    FROM follows
    WHERE user_id = p_user_id
      AND profile_id = p_profile_id
      AND is_active = true;

    IF v_follow_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'You do not follow this profile');
    END IF;

    -- ── Validate minutes if enabling with "before" option ────────────────────
    IF p_event_notification_enabled AND p_event_notification_minutes IS NOT NULL THEN
        IF p_event_notification_minutes NOT IN (5, 10, 15) THEN
            RETURN json_build_object(
                'status', false,
                'message', 'Event notification minutes must be 5, 10, 15, or NULL (at start)'
            );
        END IF;
    END IF;

    -- ── Update follows row ────────────────────────────────────────────────────
    UPDATE follows
    SET
        event_notification_enabled = p_event_notification_enabled,
        event_notification_minutes = CASE
            WHEN p_event_notification_enabled THEN p_event_notification_minutes
            ELSE NULL
        END
    WHERE id = v_follow_id;

    RETURN json_build_object(
        'status', true,
        'message', CASE
            WHEN p_event_notification_enabled THEN 'Profile event subscription enabled'
            ELSE 'Profile event subscription disabled'
        END,
        'data', json_build_object(
            'profile_id', p_profile_id,
            'profile_name', v_profile_name,
            'event_notification_enabled', p_event_notification_enabled,
            'event_notification_minutes', CASE
                WHEN p_event_notification_enabled THEN p_event_notification_minutes
                ELSE NULL
            END,
            'notification_type', CASE
                WHEN NOT p_event_notification_enabled THEN 'disabled'
                WHEN p_event_notification_minutes IS NULL THEN 'at_event_start'
                ELSE p_event_notification_minutes || '_minutes_before'
            END
        )
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status', false,
            'message', 'Something went wrong',
            'error', SQLERRM
        );
END;
$$;
```
