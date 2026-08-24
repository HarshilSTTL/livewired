# `20_device_tokens`

```sql
-- Table: device_tokens
-- Purpose: FCM registration tokens per user device, used by the `push` Edge Function
--          (triggered by the `push_notification` AFTER INSERT trigger on `notifications`)
--          to know where to send push notifications.
-- Doc: docs/database/tables/20_device_tokens.md
--
-- NOTE: This table already exists in production (created directly in Supabase,
-- not via a migration tracked in this repo). Columns below reflect the live
-- schema as of 2026-08-24 — verify against Table Editor before altering.

CREATE TABLE IF NOT EXISTS public.device_tokens (
    id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    fcm_token   text        NOT NULL,
    platform    text        NULL,       -- 'android' | 'ios' | 'web', etc.
    created_at  timestamptz NOT NULL DEFAULT now(),
    is_active   boolean     NOT NULL DEFAULT true  -- false = stale/dead token; soft-delete pattern, consistent with users.is_deleted / follows.is_active
);

-- Migration: already applied in production (2026-08-24)
--   ALTER TABLE public.device_tokens
--     ADD CONSTRAINT device_tokens_user_id_fcm_token_key UNIQUE (user_id, fcm_token);
--
-- Migration: run once in Supabase SQL editor (new — 2026-08-24)
--   ALTER TABLE public.device_tokens ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true;
```

---

## Columns

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | ❌ | `gen_random_uuid()` | Primary key |
| `user_id` | uuid | ❌ | — | Owning user. Cascade on delete. |
| `fcm_token` | text | ❌ | — | Firebase Cloud Messaging registration token for one device/app install |
| `platform` | text | ✅ | NULL | Device platform (`android`, `ios`, `web`) |
| `created_at` | timestamptz | ❌ | `now()` | When the token was first registered |
| `is_active` | boolean | ❌ | `true` | `false` = stale/dead token (device switched account, or FCM reported it as unregistered). Inactive rows are never sent to and never selected as `p_user_id`'s current tokens. |

---

## Notes

- A user can have multiple active rows (one per device they're logged into).
- The same physical device reinstalling the app / logging out and back in generates a **new** FCM token — old rows are soft-deleted (`is_active = false`), never hard-deleted, matching this schema's soft-delete convention elsewhere (`users.is_deleted`, `follows.is_active`). The `push` Edge Function also flips `is_active = false` on any token FCM reports as `UNREGISTERED`/`INVALID_ARGUMENT`.
- Registered via [`register_device_token`](../../functions/notifications/register_device_token.md).
- Whether a push actually goes out to these tokens also depends on `users.is_push_enabled` — see [`update_push_preference`](../../functions/notifications/update_push_preference.md).

---

## Related

- [`register_device_token`](../../functions/notifications/register_device_token.md) — upsert a device's FCM token
- [`update_push_preference`](../../functions/notifications/update_push_preference.md) — enable/disable push for a user
- [`push` Edge Function](../../supabase/functions/push/index.ts) — reads this table to send FCM messages
- [`19_notifications`](19_notifications.md) — the table whose INSERT trigger fires the `push` function
