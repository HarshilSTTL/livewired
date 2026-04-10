# `get_creators`

```sql
-- Function: get_creators
-- Group: Follow
-- Endpoint: GET /rpc/get_creators
-- Doc: docs/api/follow/get_creators.md
-- Note: Returns platform names only (not platform_id or logo_url)
-- Fix: followers count now respects show_followers flag and filters by is_active = true

create or replace function public.get_creators()
returns json
language plpgsql
security definer
as $$
declare
    v_result json;
begin
    select json_build_object(
        'status',  true,
        'message', 'Data fetched successfully',
        'data', json_build_object(
            'creators', coalesce(
                (
                    select json_agg(
                        json_build_object(
                            'id',         cp.id,
                            'name',       cp.profile_name,
                            'username',   cp.username,
                            'profilepic', cp.avatar,
                            'followers',  CASE
                                              WHEN cp.show_followers = true THEN (
                                                  select count(*)
                                                  from follows f
                                                  where f.profile_id = cp.id
                                                  and f.is_active = true
                                              )
                                              ELSE null
                                          END,
                            'platforms',  (
                                select coalesce(json_agg(p.plat_name), '[]'::json)
                                from creator_platform_accounts cpa
                                join platforms p on p.plat_id = cpa.platform_id
                                where cpa.profile_id = cp.id
                                -- Note: returns plat_name strings only, not objects
                            )
                        )
                    )
                    from creator_profiles cp
                    where cp.status = 'active'
                ),
                '[]'::json
            )
        )
    ) into v_result;

    return v_result;
exception
    when others then
        return json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   sqlerrm
        );
end;
$$;
```
