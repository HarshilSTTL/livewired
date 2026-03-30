-- Function: register
-- Group: Auth
-- Endpoint: POST /rpc/register
-- Doc: docs/api/auth/register.md

create or replace function register(
    email text,
    password text,
    created_device_i text default null
)
returns json as $$
declare
    v_user_id bigint;
begin
    if exists (
        select 1 from users u where u.email = email
    ) then
        return json_build_object(
            'status', false,
            'message', 'Email already exists'
        );
    end if;

    insert into users (email, password, created_device_ip, updated_device_ip)
    values (email, password, created_device_i, created_device_i)
    returning id into v_user_id;

    return json_build_object(
        'status', true,
        'message', 'User registered successfully',
        'data', json_build_object(
            'user_id', v_user_id
        )
    );
exception
    when others then
        return json_build_object(
            'status', false,
            'message', sqlerrm
        );
end;
$$ language plpgsql;
