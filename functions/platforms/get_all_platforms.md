# `get_all_platforms`

```sql
-- Function: get_all_platforms
-- Group: Platform
-- Endpoint: GET /rpc/get_all_platforms
-- Doc: docs/api/platforms/get_all_platforms.md

create or replace function get_all_platforms()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_result json;
begin
    -- Fetch all active platforms
    select json_agg(
        json_build_object(
            'plat_id', p.plat_id,
            'plat_name', p.plat_name,
            'logo_url', p.logo_url,
            'is_active', p.is_active,
            'created_at', p.created_at
        )
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
