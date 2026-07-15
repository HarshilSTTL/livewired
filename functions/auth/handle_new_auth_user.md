# `handle_new_auth_user`

```sql
-- Trigger function: handle_new_auth_user
-- Group: Auth
-- Fires: AFTER INSERT ON auth.users
-- Tables: public.users (INSERT)
-- Doc: docs/api/auth/handle_new_auth_user.md
--
-- When the frontend calls supabase.auth.signUp(), Supabase creates the
-- auth.users row. This trigger immediately mirrors that into public.users
-- using the SAME uuid, so the rest of the schema (event_mst, follows,
-- creator_profiles, etc. — all FK'd to public.users.id) keeps working
-- unchanged against Supabase-authenticated users.

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.users (id, email, username, auth_provider, created_at, updated_at)
    VALUES (
        NEW.id,
        NEW.email,
        NEW.raw_user_meta_data->>'username',
        COALESCE(NEW.raw_app_meta_data->>'provider', 'email'),
        now(), now()
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();
```

---

## Trigger Details

| Field | Value |
|-------|-------|
| **Name** | `handle_new_auth_user` |
| **Fires on** | `AFTER INSERT ON auth.users` |
| **Group** | Auth |
| **Tables** | `public.users` (INSERT) |
| **Security** | `SECURITY DEFINER` |

---

## Business Rules

1. `username` is read from `raw_user_meta_data->>'username'` — the mobile app passes this via `signUp(..., data: { 'username': username })`.
2. `auth_provider` defaults to `'email'`, or reads `raw_app_meta_data->>'provider'` for Google/OAuth sign-ins.
3. `ON CONFLICT (id) DO NOTHING` makes this idempotent — safe if Supabase ever fires the insert trigger more than once for the same user.
4. `public.users.id` is deliberately the same UUID as `auth.users.id`, keeping every existing FK (event_mst, follows, creator_profiles, etc.) working without changes.
