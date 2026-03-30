-- Function: is_creator  (was: creator_enable)
-- Group: Profile
-- Endpoint: POST /rpc/is_creator
-- Doc: docs/api/profiles/creator_enable.md
-- ⚠️ Note: SP was renamed from creator_enable → is_creator in actual DB

create or replace function public.is_creator(
    p_user_id    uuid,
    p_is_creator boolean,
    p_device_ip  text
)
returns json
language plpgsql
security definer
as $$
begin
    if not exists (
        select 1 from users where id = p_user_id
    ) then
        return json_build_object(
            'status', false,
            'message', 'User not found',
            'error',   'No user found with the given id'
        );
    end if;

    update users
    set
        role_id           = case when p_is_creator then 2 else 1 end,
        updated_device_ip = p_device_ip,
        updated_at        = now()
    where id = p_user_id;

    return json_build_object(
        'status', true,
        'message', 'Data updated successfully'
    );
exception
    when others then
        return json_build_object(
            'status', false,
            'message', 'Something went wrong',
            'error',   sqlerrm
        );
end;
$$;
