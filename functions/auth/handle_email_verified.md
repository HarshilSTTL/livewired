# `handle_email_verified`

```sql
-- Trigger function: handle_email_verified
-- Group: Auth
-- Fires: AFTER UPDATE ON auth.users
-- Tables: public.users (UPDATE)
-- Doc: docs/api/auth/handle_email_verified.md
--
-- When a user clicks the verification link Supabase sent on signup,
-- Supabase sets auth.users.email_confirmed_at to a timestamp. This trigger
-- watches for that NULL -> timestamp transition and mirrors it into
-- public.users.is_email_verified, which the rest of our schema/API reads
-- instead of querying auth.users directly.

CREATE OR REPLACE FUNCTION public.handle_email_verified()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF OLD.email_confirmed_at IS NULL AND NEW.email_confirmed_at IS NOT NULL THEN
        UPDATE public.users
        SET is_email_verified = true, updated_at = now()
        WHERE id = NEW.id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER on_auth_email_confirmed
    AFTER UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_email_verified();
```

---

## Trigger Details

| Field | Value |
|-------|-------|
| **Name** | `handle_email_verified` |
| **Fires on** | `AFTER UPDATE ON auth.users` |
| **Group** | Auth |
| **Tables** | `public.users` (UPDATE) |
| **Security** | `SECURITY DEFINER` |

---

## Business Rules

1. Only fires the update when `email_confirmed_at` transitions from `NULL` to non-`NULL` — repeated updates to an already-confirmed user are no-ops.
2. This is the only thing that sets `public.users.is_email_verified = true` — there is no manual RPC for it.
3. **Frontend responsibility:** Supabase does NOT block `signInWithPassword()` for an unconfirmed user by default. The mobile app must check verification status after login and sign the user back out if unverified (already implemented in `login_controller.dart`'s `signIn()`, per the mobile team's notes — it calls `signOut()` when the user is unverified).
4. Reads for verification status should use `public.users.is_email_verified` (via `get_user`) rather than expecting `auth.currentUser` on the client to always be fresh immediately after the link is clicked in a separate browser/session.
