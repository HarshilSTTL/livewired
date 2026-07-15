# `skip_onboarding`

```sql
-- Function: skip_onboarding
-- Group: Auth
-- Endpoint: POST /rpc/skip_onboarding
-- Tables:   users (UPDATE)
-- Doc: docs/api/auth/skip_onboarding.md
--
-- Marks onboarding as complete WITHOUT saving any platform or tag selections.
-- Called when the user taps "Skip" on the platform-choose / tag-suggestion
-- screens shown right after first signup.
--
-- Without this, a user who skips onboarding would see the same onboarding
-- screens again on every subsequent login, since onboarding_completed is the
-- only signal the app uses to decide whether to show them — it is NOT
-- inferred from the presence of user_preferred_platforms/user_interests rows.

CREATE OR REPLACE FUNCTION skip_onboarding(
    p_user_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

    IF p_user_id IS NULL THEN
        RETURN json_build_object('status', false, 'message', 'p_user_id is required');
    END IF;

    IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id AND is_deleted = false) THEN
        RETURN json_build_object('status', false, 'message', 'User not found');
    END IF;

    UPDATE users
    SET onboarding_completed = true, updated_at = now()
    WHERE id = p_user_id;

    RETURN json_build_object(
        'status',  true,
        'message', 'Onboarding skipped'
    );

EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'status',  false,
            'message', 'Something went wrong',
            'error',   SQLERRM
        );
END;
$$;
```

---

## Function Details

| Field | Value |
|-------|-------|
| **Name** | `skip_onboarding` |
| **Group** | Auth |
| **Endpoint** | `POST /rpc/skip_onboarding` |
| **Tables** | `users` (UPDATE) |
| **Security** | `SECURITY DEFINER` |

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_user_id` | `uuid` | ✅ | The user skipping onboarding |

---

## Response (Success)

```json
{
    "status": true,
    "message": "Onboarding skipped"
}
```

---

## Business Rules

1. Sets `onboarding_completed = true` and does nothing else — no platform/tag rows are written.
2. Idempotent — calling it again on an already-onboarded user just re-sets the same flag, no error.
3. This, `submit_platform`, and `submit_tags` are the only three places that set `onboarding_completed = true`.
