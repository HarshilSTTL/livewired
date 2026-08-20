# `get_event_by_id` (v1, v2 & v3)

## Version History

### v3 (Current — 2026-08-20)
- **Change:** Adds `event_end_date` to the response, and computes `event_end_time`
  from the real `event_end_date` column instead of inferring "next day" whenever
  `event_end_time < event_time`.
- **Reason:** `create_event_v4`/`update_event_v2_5` now store an explicit end date
  instead of relying on that implicit convention.
- **Endpoint:** `POST /rpc/get_event_by_id_v3`

### v2 (Previous — 2026-08-06)
- **Change:** Collaborators subquery now respects per-occurrence overrides — when
  `event_mst.collaborators_overridden = true`, returns the occurrence's own
  `event_collaborators` rows instead of always falling back to the series parent.
- **Reason:** `update_event_v2_1` can now set collaborators per single occurrence
  (`p_scope='this'`); this read path needs to reflect that instead of always
  showing the series-level collaborator list.
- **Endpoint:** `POST /rpc/get_event_by_id_v2`

### v1 (Previous)
- Collaborators always resolved via `COALESCE(parent_event_id, event_id)` — series-level only.
- **Endpoint:** `POST /rpc/get_event_by_id` (kept for backwards compatibility)

---

## V3 Function (Current)

```sql
-- Function: get_event_by_id_v3
-- Group: Events
-- Endpoint: POST /rpc/get_event_by_id_v3
-- Doc: docs/api/events/get_event_by_id.md
--
-- Change from v2: Adds event_end_date to the response and derives event_end_time's
-- (and event_end_date's) timestamp from the real event_end_date column instead of
-- inferring "next day" from event_end_time < event_time.

CREATE OR REPLACE FUNCTION get_event_by_id_v3(
    p_event_id uuid,
    p_timezone text DEFAULT 'UTC'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN

    IF p_event_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id is required');
    END IF;

    SELECT json_build_object(
        'event_id',        e.event_id,
        'profile_id',      e.profile_id,
        'parent_event_id', e.parent_event_id,
        'title',           e.title,
        'description',     e.description,
        'event_date',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
        'event_time',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_end_date',  (((COALESCE(e.event_end_date, e.event_date)::text || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
        'event_end_time',  (((COALESCE(e.event_end_date, e.event_date)::text || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_timezone',  e.event_timezone,
        'livestream',      e.livestream,
        'video',           e.video,
        'is_collaborative', e.is_collaborative,
        'is_recurring',    e.is_recurring,
        'created_at',      e.created_at,
        'creator', json_build_object(
            'profile_id',   cp.id,
            'profile_name', cp.profile_name,
            'avatar',       cp.avatar
        ),
        'platforms', (
            SELECT COALESCE(
                json_agg(json_build_object(
                    'platform_id',   p.plat_id,
                    'platform_name', p.plat_name,
                    'logo_url',      p.logo_url,
                    'stream_url',    ep.stream_url
                )),
                '[]'::json
            )
            FROM event_platforms ep
            JOIN platforms p ON p.plat_id = ep.platform_id::bigint
            -- is_overridden = true → child has its own platform data (set via p_scope='this')
            -- is_overridden = false → fall back to parent's platforms
            WHERE ep.event_id = CASE
                WHEN e.is_overridden
                THEN e.event_id
                ELSE COALESCE(e.parent_event_id, e.event_id)
            END
        ),
        'collaborators', (
            SELECT COALESCE(
                json_agg(json_build_object(
                    'profile_id',   cp2.id,
                    'profile_name', cp2.profile_name,
                    'avatar',       cp2.avatar,
                    'status',       ec.status,
                    'invited_at',   ec.invited_at,
                    'responded_at', ec.responded_at
                )),
                '[]'::json
            )
            FROM event_collaborators ec
            JOIN creator_profiles cp2 ON cp2.id = ec.profile_id
            -- collaborators_overridden = true → occurrence has its own collaborator list (set via p_scope='this')
            -- collaborators_overridden = false → fall back to the series parent's collaborators
            WHERE ec.event_id  = CASE
                WHEN e.collaborators_overridden
                THEN e.event_id
                ELSE COALESCE(e.parent_event_id, e.event_id)
            END
              AND ec.is_deleted = false
        ),
        'recurring', (
            SELECT json_build_object(
                'recurring_type',       er.recurring_type,
                'recurring_days',       er.recurring_days,
                'recurring_interval',   er.recurring_interval,
                'recurring_start_date', er.recurring_start_date,
                'recurring_end_date',   er.recurring_end_date
            )
            FROM event_recurring er
            WHERE er.event_id = COALESCE(e.parent_event_id, e.event_id)
        )
    )
    INTO v_result
    FROM event_mst e
    JOIN creator_profiles cp ON cp.id = e.profile_id
    WHERE e.event_id   = p_event_id
      AND e.is_deleted = false;

    IF v_result IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event not found');
    END IF;

    RETURN json_build_object('status', true, 'data', v_result);

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

---

## V2 Function (Previous)

```sql
-- Function: get_event_by_id_v2
-- Group: Events
-- Endpoint: POST /rpc/get_event_by_id_v2
-- Doc: docs/api/events/get_event_by_id.md
--
-- Superseded by get_event_by_id_v3 (2026-08-20) — this version has no event_end_date
-- column and infers cross-midnight events only from event_end_time < event_time. Kept
-- for existing callers.

CREATE OR REPLACE FUNCTION get_event_by_id_v2(
    p_event_id uuid,
    p_timezone text DEFAULT 'UTC'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN

    IF p_event_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id is required');
    END IF;

    SELECT json_build_object(
        'event_id',        e.event_id,
        'profile_id',      e.profile_id,
        'parent_event_id', e.parent_event_id,
        'title',           e.title,
        'description',     e.description,
        'event_date',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
        'event_time',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_end_time',  (((CASE WHEN e.event_end_time IS NOT NULL AND e.event_end_time < e.event_time
                                   THEN (e.event_date + 1)::text
                                   ELSE e.event_date::text
                              END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_timezone',  e.event_timezone,
        'livestream',      e.livestream,
        'video',           e.video,
        'is_collaborative', e.is_collaborative,
        'is_recurring',    e.is_recurring,
        'created_at',      e.created_at,
        'creator', json_build_object(
            'profile_id',   cp.id,
            'profile_name', cp.profile_name,
            'avatar',       cp.avatar
        ),
        'platforms', (
            SELECT COALESCE(
                json_agg(json_build_object(
                    'platform_id',   p.plat_id,
                    'platform_name', p.plat_name,
                    'logo_url',      p.logo_url,
                    'stream_url',    ep.stream_url
                )),
                '[]'::json
            )
            FROM event_platforms ep
            JOIN platforms p ON p.plat_id = ep.platform_id::bigint
            -- is_overridden = true → child has its own platform data (set via p_scope='this')
            -- is_overridden = false → fall back to parent's platforms
            WHERE ep.event_id = CASE
                WHEN e.is_overridden
                THEN e.event_id
                ELSE COALESCE(e.parent_event_id, e.event_id)
            END
        ),
        'collaborators', (
            SELECT COALESCE(
                json_agg(json_build_object(
                    'profile_id',   cp2.id,
                    'profile_name', cp2.profile_name,
                    'avatar',       cp2.avatar,
                    'status',       ec.status,
                    'invited_at',   ec.invited_at,
                    'responded_at', ec.responded_at
                )),
                '[]'::json
            )
            FROM event_collaborators ec
            JOIN creator_profiles cp2 ON cp2.id = ec.profile_id
            -- collaborators_overridden = true → occurrence has its own collaborator list (set via p_scope='this')
            -- collaborators_overridden = false → fall back to the series parent's collaborators
            WHERE ec.event_id  = CASE
                WHEN e.collaborators_overridden
                THEN e.event_id
                ELSE COALESCE(e.parent_event_id, e.event_id)
            END
              AND ec.is_deleted = false
        ),
        'recurring', (
            SELECT json_build_object(
                'recurring_type',       er.recurring_type,
                'recurring_days',       er.recurring_days,
                'recurring_interval',   er.recurring_interval,
                'recurring_start_date', er.recurring_start_date,
                'recurring_end_date',   er.recurring_end_date
            )
            FROM event_recurring er
            WHERE er.event_id = COALESCE(e.parent_event_id, e.event_id)
        )
    )
    INTO v_result
    FROM event_mst e
    JOIN creator_profiles cp ON cp.id = e.profile_id
    WHERE e.event_id   = p_event_id
      AND e.is_deleted = false;

    IF v_result IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event not found');
    END IF;

    RETURN json_build_object('status', true, 'data', v_result);

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

---

## V1 Function (Previous)

```sql
-- Function: get_event_by_id
-- Group: Events
-- Endpoint: POST /rpc/get_event_by_id
-- Doc: docs/api/events/get_event_by_id.md
--
-- Superseded by get_event_by_id_v2 (2026-08-06) — collaborators here always resolve to the
-- series parent, so a per-occurrence collaborator override set via update_event_v2_1
-- (p_scope='this') would not show up correctly. Kept for existing callers.

CREATE OR REPLACE FUNCTION get_event_by_id(
    p_event_id uuid,
    p_timezone text DEFAULT 'UTC'
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN

    IF p_event_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_event_id is required');
    END IF;

    SELECT json_build_object(
        'event_id',        e.event_id,
        'profile_id',      e.profile_id,
        'parent_event_id', e.parent_event_id,
        'title',           e.title,
        'description',     e.description,
        'event_date',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::date,
        'event_time',      (((e.event_date::text || ' ' || e.event_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_end_time',  (((CASE WHEN e.event_end_time IS NOT NULL AND e.event_end_time < e.event_time
                                   THEN (e.event_date + 1)::text
                                   ELSE e.event_date::text
                              END || ' ' || e.event_end_time::text)::timestamp AT TIME ZONE e.event_timezone) AT TIME ZONE p_timezone)::time,
        'event_timezone',  e.event_timezone,
        'livestream',      e.livestream,
        'video',           e.video,
        'is_collaborative', e.is_collaborative,
        'is_recurring',    e.is_recurring,
        'created_at',      e.created_at,
        'creator', json_build_object(
            'profile_id',   cp.id,
            'profile_name', cp.profile_name,
            'avatar',       cp.avatar
        ),
        'platforms', (
            SELECT COALESCE(
                json_agg(json_build_object(
                    'platform_id',   p.plat_id,
                    'platform_name', p.plat_name,
                    'logo_url',      p.logo_url,
                    'stream_url',    ep.stream_url
                )),
                '[]'::json
            )
            FROM event_platforms ep
            JOIN platforms p ON p.plat_id = ep.platform_id::bigint
            -- is_overridden = true → child has its own platform data (set via p_scope='this')
            -- is_overridden = false → fall back to parent's platforms
            WHERE ep.event_id = CASE
                WHEN e.is_overridden
                THEN e.event_id
                ELSE COALESCE(e.parent_event_id, e.event_id)
            END
        ),
        'collaborators', (
            SELECT COALESCE(
                json_agg(json_build_object(
                    'profile_id',   cp2.id,
                    'profile_name', cp2.profile_name,
                    'avatar',       cp2.avatar,
                    'status',       ec.status,
                    'invited_at',   ec.invited_at,
                    'responded_at', ec.responded_at
                )),
                '[]'::json
            )
            FROM event_collaborators ec
            JOIN creator_profiles cp2 ON cp2.id = ec.profile_id
            WHERE ec.event_id  = COALESCE(e.parent_event_id, e.event_id)
              AND ec.is_deleted = false
        ),
        'recurring', (
            SELECT json_build_object(
                'recurring_type',       er.recurring_type,
                'recurring_days',       er.recurring_days,
                'recurring_interval',   er.recurring_interval,
                'recurring_start_date', er.recurring_start_date,
                'recurring_end_date',   er.recurring_end_date
            )
            FROM event_recurring er
            WHERE er.event_id = COALESCE(e.parent_event_id, e.event_id)
        )
    )
    INTO v_result
    FROM event_mst e
    JOIN creator_profiles cp ON cp.id = e.profile_id
    WHERE e.event_id   = p_event_id
      AND e.is_deleted = false;

    IF v_result IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Event not found');
    END IF;

    RETURN json_build_object('status', true, 'data', v_result);

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
