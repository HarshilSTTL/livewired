# `signup`

```sql
-- Function: signup
-- Group: Auth
-- Endpoint: POST /rpc/signup
-- Doc: docs/api/auth/signup.md

create or replace function signup(
    email text,
    password text,
    ip text default '::1'
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid;

begin
    -- ✅ Email validation
    if signup.email is null or trim(signup.email) = '' then
        return json_build_object(
            'status', false,
            'message', 'Email is required'
        );
    end if;
    -- ✅ Password validation
    if signup.password is null or trim(signup.password) = '' then
        return json_build_object(
            'status', false,
            'message', 'Password is required'
        );
    end if;
    -- ✅ Check email already exists
    if exists (
        select 1 from users u where lower(u.email) = lower(signup.email)
    ) then
        return json_build_object(
            'status', false,
            'message', 'Email already exists'
        );
    end if;
    -- ✅ Insert user
    insert into users (
        email,
        password,
        created_device_ip,
        updated_device_ip
    )
    values (
        signup.email,
        signup.password,
        '::1',
        '::1'
    )
    returning id into v_user_id;
    -- ✅ Success response
    return json_build_object(
        'status', true,
        'user_id', v_user_id,
        'message', 'Registration successful'
    );
exception
    when others then
        return json_build_object(
            'status', false,
            'message', 'Something went wrong in signup',
            'error', sqlerrm
        );
end;
$$;
```
