# `login`

```sql
-- Function: login
-- Group: Auth
-- Endpoint: POST /rpc/login
-- Doc: docs/api/auth/login.md

create or replace function login(
    email text,
    password text
)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user record;
begin
    -- 🔹 Validate input
    if email is null or trim(email) = '' then
        return json_build_object(
            'status', false,
            'message', 'Email is required'
        );
    end if;
    if password is null or trim(password) = '' then
        return json_build_object(
            'status', false,
            'message', 'Password is required'
        );
    end if;
    -- 🔹 Fetch user
    select u.id, u.email, u.password
    into v_user
    from users u
    where u.email = login.email
    limit 1;
    -- 🔹 User not found
    if v_user is null then
        return json_build_object(
            'status', false,
            'message', 'Invalid email or password'
        );
    end if;
    -- 🔹 Password mismatch
    if v_user.password <> login.password then
        return json_build_object(
            'status', false,
            'message', 'Invalid email or password'
        );
    end if;
    -- 🔹 Success
    return json_build_object(
        'status', true,
        'user_id', v_user.id,
        'email', v_user.email,
        'message', 'Login successful'
    );
end;
$$;
```
