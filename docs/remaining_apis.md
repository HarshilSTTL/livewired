# LiveWired — Remaining APIs & Pending Changes

> Reference file. Updated as items are completed.
> Last updated: 2026-04-02

---

## ✅ Just Completed (this session)

| SP | File |
|----|------|
| `get_event_by_id` | `functions/events/get_event_by_id.md` |
| `update_event` | `functions/events/update_event.md` |
| `delete_event` | `functions/events/delete_event.md` |
| `toggle_event_notification` | `functions/notifications/toggle_event_notification.md` |
| `get_user_notifications` | `functions/notifications/get_user_notifications.md` |
| `init_user` | `functions/auth/init_user.md` |
| `auth_trigger` | `functions/auth/auth_trigger.md` |
| `delete_account` | `functions/auth/delete_account.md` |
| `delete_profile` | `functions/profiles/delete_profile.md` |
| `get_user_settings` | `functions/settings/get_user_settings.md` |
| `update_user_settings` | `functions/settings/update_user_settings.md` |
| New tables | `schema/tables/14_event_notifications.md` · `schema/tables/15_user_settings.md` |

---

## 🔧 Schema Changes Still Needed

These require SQL migrations + file updates. Not done yet.

| Change | Migration SQL | Affects |
|--------|--------------|---------|
| Add `username` to `users` | `ALTER TABLE public.users ADD COLUMN IF NOT EXISTS username text UNIQUE;` | `signup`, `init_user` |
| Add `is_deleted`, `deleted_at` to `users` | `ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_deleted boolean DEFAULT false; ALTER TABLE public.users ADD COLUMN IF NOT EXISTS deleted_at timestamptz NULL;` | `delete_account` |
| Add `timezone` to `event_mst` | `ALTER TABLE public.event_mst ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'UTC';` | `create_event`, `update_event`, `get_event_by_id`, `get_user_notifications` |
| Create `event_notifications` table | See `schema/tables/14_event_notifications.md` | `toggle_event_notification`, `get_user_notifications` |
| Create `user_settings` table | See `schema/tables/15_user_settings.md` | `get_user_settings`, `update_user_settings` |
| Auth trigger on `auth.users` | See `functions/auth/auth_trigger.md` | Supabase Auth signup / Google OAuth |

---

## 🔧 Existing SP Changes Still Needed

| SP | Change needed |
|----|--------------|
| `create_event` | Add `p_timezone text DEFAULT 'UTC'` param + store in `event_mst.timezone` |
| `signup` / `register` | Add `p_username` param — or deprecate in favour of `init_user` + Supabase Auth |
| `google_auth` | Deprecate — replaced by Supabase Auth trigger + `init_user` |
| `login` | Deprecate — replaced by `supabase.auth.signInWithPassword()` on frontend |

---

## 🔮 Future APIs (Build Later)

| SP | Purpose |
|----|---------|
| `change_password` | Frontend-only via `supabase.auth.updateUser(password: newPass)` — no SP needed |
| `forgot_password` | Handled by Supabase Auth `resetPasswordForEmail()` — no SP needed |
| `register_device_token` | Store FCM token for push notifications — needs Firebase setup first |
| `get_trending_events` | Discovery screen — popular upcoming events across all creators |
| `get_trending_creators` | Creators with fastest follower growth |
| `report_profile` | User reports inappropriate creator — needs `reports` table |
| `report_event` | User reports inappropriate event — same `reports` table |
| `block_user` | Block creator from appearing in feed — needs `blocks` table |
| `get_creator_analytics` | Creator dashboard — follower count over time, event views |
| `search_events_by_date` | Find events on a specific date across all followed creators |
| Admin SPs | User management, content moderation — when app scales |

---

## Auth Flow Change Summary (Supabase Auth)

**Old flow:**
```
Flutter → POST /rpc/signup (email, password)   ← custom SP, plaintext password
Flutter → POST /rpc/login  (email, password)   ← custom SP, no JWT issued
Flutter → POST /rpc/google_auth (email)        ← custom SP
```

**New flow:**
```
Flutter → supabase.auth.signUp(email, password)        ← Supabase Auth (encrypted, JWT)
        → Trigger auto-creates public.users row
        → Flutter calls POST /rpc/init_user (username)  ← sets username

Flutter → supabase.auth.signInWithPassword(...)        ← Supabase Auth (JWT issued)

Flutter → supabase.auth.signInWithOAuth(google)        ← Supabase Auth (Google OAuth)
        → Trigger auto-creates public.users row if new user
        → Flutter calls POST /rpc/init_user (username) if first login
```

**Benefits:** encrypted passwords, automatic JWT, Google OAuth built-in, no custom login/signup SPs needed.

---

## Timezone Flow Summary

**How it works:**
- Creator sets their timezone when creating an event (`p_timezone` e.g. `'America/New_York'`)
- Stored in `event_mst.timezone`
- User sets their timezone in settings (`update_user_settings` with `p_timezone` e.g. `'Asia/Kolkata'`)
- Stored in `user_settings.timezone`
- `get_user_notifications` converts event time to user's local time:
  ```sql
  ((event_date + event_time) AT TIME ZONE event.timezone) AT TIME ZONE user_settings.timezone
  ```
- Response includes `event_time_utc` + `event_time_local` + `user_timezone`
