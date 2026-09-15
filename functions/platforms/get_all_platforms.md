# `get_all_platforms` (v1 & v2)

## Version History

### v2 (Current — 2026-05-28)
- **Change:** Platforms ordered by ID (1→2→3→4)
- **Reason:** Consistent platform display order
- **Endpoint:** `GET /rpc/get_all_platforms_v2`

### v1 (Deprecated, still in use by the app)
- **Change:** Platforms ordered alphabetically by `plat_name ASC`
- **Reason:** This is the endpoint the app actually calls; the "Additional Links" icons were showing in raw insertion order instead of A→Z
- **Endpoint:** `GET /rpc/get_all_platforms`

---

## V2 Function (Current)

```sql
-- Function: get_all_platforms_v2
-- Group: Platform
-- Endpoint: GET /rpc/get_all_platforms_v2
-- Doc: docs/api/platforms/get_all_platforms.md
-- Version: 2.0 (2026-05-28)
-- Changes: Platforms ordered by plat_id ASC

create or replace function get_all_platforms_v2()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result json;
begin
    -- Fetch all active platforms ordered by plat_id
    select json_agg(
        json_build_object(
            'plat_id', p.plat_id,
            'plat_name', p.plat_name,
            'logo_url', p.logo_url,
            'is_active', p.is_active,
            'created_at', p.created_at
        )
        order by p.plat_id asc
    )
    into v_result
    from platforms p
    where p.is_active = 1;
    -- If no data found
    if v_result is null then
        return json_build_object(
            'status', false,
            'message', 'No platforms found',
            'data', '[]'::json
        );
    end if;
    -- Success response
    return json_build_object(
        'status', true,
        'message', 'Platforms fetched successfully',
        'data', v_result
    );
exception
    when others then
        return json_build_object(
            'status', false,
            'message', 'Something went wrong while fetching platforms',
            'error', sqlerrm
        );
end;
$$;
```

---

## V1 Function (Deprecated)

```sql
-- Function: get_all_platforms (V1 - Deprecated, but still the endpoint the app calls)
-- Returns platforms ordered alphabetically by plat_name
-- Use get_all_platforms_v2 once the app is migrated to it

create or replace function get_all_platforms()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result json;
begin
    -- Fetch all active platforms, ordered alphabetically
    select json_agg(
        json_build_object(
            'plat_id', p.plat_id,
            'plat_name', p.plat_name,
            'logo_url', p.logo_url,
            'is_active', p.is_active,
            'created_at', p.created_at
        )
        order by p.plat_name asc
    )
    into v_result
    from platforms p
    where p.is_active = 1;
    -- If no data found
    if v_result is null then
        return json_build_object(
            'status', false,
            'message', 'No platforms found',
            'data', '[]'::json
        );
    end if;
    -- Success response
    return json_build_object(
        'status', true,
        'message', 'Platforms fetched successfully',
        'data', v_result
    );
exception
    when others then
        return json_build_object(
            'status', false,
            'message', 'Something went wrong while fetching platforms',
            'error', sqlerrm
        );
end;
$$;
```
