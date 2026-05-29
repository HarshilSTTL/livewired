# `get_profile_platforms` (v1, v2 & v2.1)

## Version History

### v2.1 (Current — 2026-05-29)
- **Change:** Returns all 3 link groups (platforms, additional, custom) ordered by user preferences
- **Uses:** `profile_link_preferences` table for custom ordering
- **Groups:** Platforms (1-4) → Additional Links (5+) → Custom Links
- **Endpoint:** `POST /rpc/get_profile_platforms_v2_1`

### v2 (Previous — 2026-05-29)
- **Change:** Returns all 3 link groups with each in separate response field
- **Adds:** `type` field to identify link group (platform, additional_link, custom_link)
- **Endpoint:** `POST /rpc/get_profile_platforms_v2`

### v1 (Deprecated)
- Returns only platform accounts ordered by platform_id
- **Endpoint:** `POST /rpc/get_profile_platforms` (kept for backwards compatibility)

---

## V2.1 Function (Current)

```sql
-- Function: get_profile_platforms_v2_1
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_platforms_v2_1
-- Tables:   creator_profiles, creator_platform_accounts, platforms, profile_custom_links, profile_link_preferences
-- Doc:      docs/api/profiles/get_profile_platforms.md
-- Version:  2.1 (2026-05-29)
-- Changes:  Returns all 3 link groups with preference-based ordering
--           Each group in separate response field: platforms, additional_links, custom_links
--
-- Purpose:  Returns all profile links (platforms, additional, custom) ordered by user preferences.
--           Supports drag-drop reordering via profile_link_preferences table.

CREATE OR REPLACE FUNCTION get_profile_platforms_v2_1(
    p_profile_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile_id uuid;
BEGIN

    -- ── Null guard ───────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    -- ── Profile existence check ──────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles WHERE id = p_profile_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    -- ── Return all 3 link groups in separate fields, ordered by preferences ──
    RETURN json_build_object(
        'status', true,
        'message', 'Platform links fetched successfully',
        'data', json_build_object(
            'platforms', COALESCE((
                SELECT json_agg(
                    json_build_object(
                        'id',             cpa.id,
                        'platform_id',    cpa.platform_id,
                        'type',           'platform',
                        'platform_name',  p.plat_name,
                        'logo_url',       p.logo_url,
                        'channel_url',    cpa.channel_url,
                        'is_default',     cpa.is_default
                    )
                    ORDER BY sort_order ASC
                )
                FROM (
                    SELECT
                        cpa.id,
                        cpa.platform_id,
                        p.plat_name,
                        p.logo_url,
                        cpa.channel_url,
                        cpa.is_default,
                        COALESCE(
                            (SELECT array_position(plp.platform_ids_order, cpa.platform_id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = p_profile_id),
                            cpa.platform_id + 100
                        ) as sort_order
                    FROM creator_platform_accounts cpa
                    LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
                    WHERE cpa.profile_id = p_profile_id
                      AND cpa.is_deleted = false
                      AND cpa.platform_id IN (1, 2, 3, 4)
                ) platform_list
            ), '[]'::json),
            'additional_links', COALESCE((
                SELECT json_agg(
                    json_build_object(
                        'id',             cpa.id,
                        'platform_id',    cpa.platform_id,
                        'type',           'additional_link',
                        'platform_name',  p.plat_name,
                        'logo_url',       p.logo_url,
                        'channel_url',    cpa.channel_url,
                        'is_default',     cpa.is_default
                    )
                    ORDER BY sort_order ASC
                )
                FROM (
                    SELECT
                        cpa.id,
                        cpa.platform_id,
                        p.plat_name,
                        p.logo_url,
                        cpa.channel_url,
                        cpa.is_default,
                        COALESCE(
                            (SELECT array_position(plp.additional_ids_order, cpa.platform_id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = p_profile_id),
                            cpa.platform_id + 100
                        ) as sort_order
                    FROM creator_platform_accounts cpa
                    LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
                    WHERE cpa.profile_id = p_profile_id
                      AND cpa.is_deleted = false
                      AND cpa.platform_id >= 5
                ) additional_list
            ), '[]'::json),
            'custom_links', COALESCE((
                SELECT json_agg(
                    json_build_object(
                        'id',             pcl.id,
                        'platform_id',    NULL,
                        'type',           'custom_link',
                        'platform_name',  pcl.platform_name,
                        'logo_url',       NULL,
                        'channel_url',    pcl.platform_url,
                        'is_default',     false
                    )
                    ORDER BY sort_order ASC
                )
                FROM (
                    SELECT
                        pcl.id,
                        pcl.platform_name,
                        pcl.platform_url,
                        COALESCE(
                            (SELECT array_position(plp.custom_ids_order, pcl.id)
                             FROM profile_link_preferences plp
                             WHERE plp.profile_id = p_profile_id),
                            9999
                        ) as sort_order
                    FROM profile_custom_links pcl
                    WHERE pcl.profile_id = p_profile_id
                      AND pcl.is_deleted = false
                ) custom_list
            ), '[]'::json)
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

---

## V2 Function (Previous)

```sql
-- Function: get_profile_platforms_v2
-- Group:    profiles
-- Endpoint: POST /rpc/get_profile_platforms_v2
-- Tables:   creator_profiles, creator_platform_accounts, platforms, profile_custom_links
-- Doc:      docs/api/profiles/get_profile_platforms.md
-- Version:  2.0 (2026-05-29)
-- Changes:  Returns all 3 link groups (platforms, additional, custom) in separate fields
--           Fixed order: platform_id ASC for each group
--
-- Purpose:  Returns all profile links organized by type (platforms, additional, custom).
--           Each group returned in separate field with type identifier.

CREATE OR REPLACE FUNCTION get_profile_platforms_v2(
    p_profile_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_profile_id uuid;
BEGIN

    -- ── Null guard ───────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    -- ── Profile existence check ──────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles WHERE id = p_profile_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    -- ── Return all 3 link groups in separate fields ──────────────────────────
    RETURN json_build_object(
        'status', true,
        'message', 'Platform links fetched successfully',
        'data', json_build_object(
            'platforms', COALESCE((
                SELECT json_agg(
                    json_build_object(
                        'id',             cpa.id,
                        'platform_id',    cpa.platform_id,
                        'type',           'platform',
                        'platform_name',  p.plat_name,
                        'logo_url',       p.logo_url,
                        'channel_url',    cpa.channel_url,
                        'is_default',     cpa.is_default
                    )
                    ORDER BY cpa.platform_id ASC
                )
                FROM creator_platform_accounts cpa
                LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
                WHERE cpa.profile_id = p_profile_id
                  AND cpa.is_deleted = false
                  AND cpa.platform_id IN (1, 2, 3, 4)
            ), '[]'::json),
            'additional_links', COALESCE((
                SELECT json_agg(
                    json_build_object(
                        'id',             cpa.id,
                        'platform_id',    cpa.platform_id,
                        'type',           'additional_link',
                        'platform_name',  p.plat_name,
                        'logo_url',       p.logo_url,
                        'channel_url',    cpa.channel_url,
                        'is_default',     cpa.is_default
                    )
                    ORDER BY cpa.platform_id ASC
                )
                FROM creator_platform_accounts cpa
                LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
                WHERE cpa.profile_id = p_profile_id
                  AND cpa.is_deleted = false
                  AND cpa.platform_id >= 5
            ), '[]'::json),
            'custom_links', COALESCE((
                SELECT json_agg(
                    json_build_object(
                        'id',             pcl.id,
                        'platform_id',    NULL,
                        'type',           'custom_link',
                        'platform_name',  pcl.platform_name,
                        'logo_url',       NULL,
                        'channel_url',    pcl.platform_url,
                        'is_default',     false
                    )
                    ORDER BY pcl.created_at ASC
                )
                FROM profile_custom_links pcl
                WHERE pcl.profile_id = p_profile_id
                  AND pcl.is_deleted = false
            ), '[]'::json)
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

---

## V1 Function (Deprecated — Kept for Backwards Compatibility)

```sql
-- Function: get_profile_platforms (V1 - Deprecated)
-- Returns only platform accounts ordered by platform_id
-- Use get_profile_platforms_v2_1 for new implementations with all 3 link groups

CREATE OR REPLACE FUNCTION get_profile_platforms(
    p_profile_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_result json;
BEGIN

    -- ── Null guard ───────────────────────────────────────────────────────────
    IF p_profile_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'Profile ID is required');
    END IF;

    -- ── Profile existence check ──────────────────────────────────────────────
    IF NOT EXISTS (
        SELECT 1 FROM creator_profiles WHERE id = p_profile_id
    ) THEN
        RETURN json_build_object('status', false, 'message', 'Profile not found');
    END IF;

    -- ── Fetch active platform links ──────────────────────────────────────────
    SELECT json_agg(
        json_build_object(
            'id',            cpa.id,
            'platform_id',   cpa.platform_id,
            'platform_name', p.plat_name,
            'logo_url',      p.logo_url,
            'channel_url',   cpa.channel_url,
            'is_default',    cpa.is_default
        )
        ORDER BY cpa.platform_id ASC
    )
    INTO v_result
    FROM creator_platform_accounts cpa
    LEFT JOIN platforms p ON p.plat_id = cpa.platform_id
    WHERE cpa.profile_id = p_profile_id
      AND cpa.is_deleted = false;

    RETURN json_build_object(
        'status',  true,
        'message', 'Platform links fetched successfully',
        'data',    COALESCE(v_result, '[]'::json)
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
