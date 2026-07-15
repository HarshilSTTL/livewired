# `submit_platform`

```sql
-- Function: submit_platform
-- Group: Platform
-- Endpoint: POST /rpc/submit_platform
-- Doc: docs/api/platforms/submit_platform.md

create or replace function submit_platform(
    p_user_id   uuid,
    p_platformid int[]
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_count         int;
    v_invalid_count int;
begin
    select count(*) into v_count
    from users where id = p_user_id;
    if v_count = 0 then
        return json_build_object(
            'status',  false,
            'message', 'Invalid user_id',
            'error',   'USER_NOT_FOUND'
        );
    end if;
    if p_platformid is null or array_length(p_platformid, 1) is null then
        return json_build_object(
            'status',  false,
            'message', 'platformid is required',
            'error',   'EMPTY_PLATFORM_LIST'
        );
    end if;
    select count(*) into v_invalid_count
    from unnest(p_platformid) pid
    where not exists (
        select 1 from platforms p where p.plat_id = pid
    );
    if v_invalid_count > 0 then
        return json_build_object(
            'status',  false,
            'message', 'One or more platform IDs are invalid',
            'error',   'INVALID_PLATFORM_ID'
        );
    end if;
    delete from user_preferred_platforms where user_id = p_user_id;
    insert into user_preferred_platforms (user_id, platform_id)
    select p_user_id, unnest(p_platformid);

    -- Onboarding is considered complete once the user submits their platforms,
    -- regardless of whether they also submit tags.
    update users set onboarding_completed = true where id = p_user_id;

    return json_build_object(
        'status',  true,
        'message', 'Platforms saved successfully'
    );
exception
    when others then
        return json_build_object(
            'status',  false,
            'message', 'There was a problem in submit_platform',
            'error',   sqlerrm
        );
end;
$$;
```
