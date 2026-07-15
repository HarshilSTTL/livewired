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
    -- Bare ON CONFLICT DO NOTHING (no column list) absorbs a violation on
    -- EITHER unique constraint on this table — id (re-fired trigger) or
    -- email (a public.users row with this email already exists under a
    -- different id, e.g. leftover data from the deprecated register/signup/
    -- google_auth RPCs). Without this, an email collision throws an
    -- unhandled exception, rolls back the whole auth.users INSERT, and
    -- signup fails with a 500 even though Supabase Auth itself is fine.
    ON CONFLICT DO NOTHING;

    -- FOUND reflects whether the INSERT above actually inserted a row.
    -- If it's false, ON CONFLICT DO NOTHING absorbed a collision (most likely
    -- the email already exists under a different id) and this auth.users
    -- account now has NO matching public.users row — is_email_verified will
    -- never sync for it via handle_email_verified. Surface this so it gets
    -- reconciled manually instead of failing silently.
    IF NOT FOUND THEN
        RAISE WARNING 'handle_new_auth_user: skipped insert for auth.users.id=% (email=%) — id or email already exists on a different public.users row. Needs manual reconciliation.',
            NEW.id, NEW.email;
    END IF;

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
