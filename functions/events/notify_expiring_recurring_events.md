# `notify_expiring_recurring_events`

```sql
-- Function: notify_expiring_recurring_events
-- Group:    Events
-- Endpoint: POST /rpc/notify_expiring_recurring_events  (or called via pg_cron)
-- Tables:   event_recurring (SELECT + UPDATE), notifications (INSERT)
-- Doc:      docs/api/events/notify_expiring_recurring_events.md
--
-- Finds all recurring events whose recurring_end_date falls within the next 7 days
-- and whose renewal_notified_at is NULL (notification not yet sent).
-- Sends one notification per event to the event owner, then stamps renewal_notified_at.
--
-- Safe to call multiple times — renewal_notified_at prevents duplicate notifications.
-- When the owner updates the recurring schedule via update_event, renewal_notified_at
-- is reset to NULL so they can be notified again for the new end date.
--
-- Intended usage: scheduled daily via pg_cron
--   SELECT cron.schedule(
--       'notify-expiring-recurring-events',
--       '0 9 * * *',
--       $$SELECT notify_expiring_recurring_events()$$
--   );

CREATE OR REPLACE FUNCTION notify_expiring_recurring_events()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_rec   RECORD;
    v_count int := 0;
BEGIN

    FOR v_rec IN
        SELECT
            er.id                 AS recurring_id,
            er.event_id,
            er.recurring_end_date,
            e.title,
            cp.user_id,
            cp.profile_name
        FROM event_recurring er
        JOIN event_mst         e  ON e.event_id  = er.event_id
        JOIN creator_profiles  cp ON cp.id        = e.profile_id
        WHERE er.recurring_end_date IS NOT NULL
          AND er.recurring_end_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '7 days'
          AND er.renewal_notified_at IS NULL
          AND e.is_deleted  = false
          AND cp.status     = 'active'
    LOOP

        -- ── Send renewal notification to event owner ──────────────────────────
        INSERT INTO notifications (user_id, title, body, data)
        VALUES (
            v_rec.user_id,
            'Recurring Event Ending Soon',
            'Your recurring event "' || v_rec.title || '" ends on '
                || to_char(v_rec.recurring_end_date, 'Mon DD, YYYY')
                || '. Update the schedule to keep it going.',
            json_build_object(
                'type',                 'recurring_renewal',
                'event_id',             v_rec.event_id,
                'recurring_end_date',   v_rec.recurring_end_date
            )
        );

        -- ── Stamp the notification so it is not sent again ────────────────────
        UPDATE event_recurring
        SET renewal_notified_at = now()
        WHERE id = v_rec.recurring_id;

        v_count := v_count + 1;

    END LOOP;

    RETURN json_build_object(
        'status',  true,
        'message', v_count || ' renewal notification(s) sent'
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
