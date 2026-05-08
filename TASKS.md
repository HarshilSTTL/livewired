# LiveWired — Task Tracker

> Status key: ✅ Complete · ⏳ Pending
> Last updated: 2026-05-08

---

## All Tasks

| # | Task | Status |
|---|------|--------|
| 1 | Add `twitch_by_default` and `kick_by_default` flags to creator profile | ✅ Complete |
| 2 | Add `is_read` flag to notifications table | ✅ Complete |
| 3 | API — get count of unread notifications | ✅ Complete |
| 4 | API — mark notification(s) as read | ✅ Complete |
| 5 | Add optional `end_time` to events | ✅ Complete |
| 6 | Live list = events with `end_time`; Today list = everything else | ✅ Complete |
| 7 | `recurring_end_date` optional when creating a recurring event | ✅ Complete |
| 8 | Default recurring duration = 3 months when no end date provided | ✅ Complete |
| 9 | Send renewal notification 7 days before recurring event expires | ✅ Complete |
| 10 | Collaborator functionality (owner + max 5 collaborators) | ✅ Complete |
| 11 | Postpone or remove a single occurrence within a recurring series | ⏳ Pending |
| 12 | Profile-level notification settings (global auto-reminder per profile) | ⏳ Pending |
| 13 | Recurring-event notification options (auto-reminder for every occurrence) | ⏳ Pending |

---

## ✅ Completed Tasks

### 1 — `twitch_by_default` + `kick_by_default` on creator profile
- Added to `creator_profiles` table
- Returned by `get_user_profiles` in the post-login profile picker
- **Files:** [[schema/tables/05_creator_profiles.md]] · [[docs/database/tables/05_creator_profiles.md]]
- **Log:** [[updates/2026-04-29.md]]

---

### 5 — Optional `end_time` on events
- `event_end_time time DEFAULT null` added to `event_mst`
- Cross-midnight support: `end_time < start_time` = ends next day
- Validation: `end_time = start_time` is rejected; anything else is valid
- **Files:** [[functions/events/create_event.md]] · [[functions/events/update_event.md]] · [[schema/tables/08_event_mst.md]]
- **Log:** [[updates/2026-05-03.md]]

---

### 6 — Live list vs Today list based on `end_time`
- **Live:** `event_end_time IS NOT NULL` AND event has started AND has not yet ended
- **Today:** all other events (no end_time, not yet started, or already ended)
- The old `livestream = true` gate was removed from Live placement
- **Files:** [[functions/events/get_event_list.md]]
- **Log:** [[updates/2026-05-03.md]]

---

### 7 + 8 — Optional recurring end date, defaults to 3 months
- `p_recurring_end_date` is optional in `create_event` and `update_event`
- If omitted, `v_safe_end = recurring_start_date + INTERVAL '3 months'`
- Computed end date is always stored in `event_recurring` (never NULL)
- **Files:** [[functions/events/create_event.md]] · [[functions/events/update_event.md]] · [[schema/tables/13_event_recurring.md]]
- **Log:** [[updates/2026-05-04.md]]

---

### 9 — Renewal notification before recurring event expires
- New SP: `notify_expiring_recurring_events` — designed to run daily via pg_cron
- Notifies event owner 7 days before `recurring_end_date`
- Idempotent: `renewal_notified_at` column prevents duplicate sends; resets on schedule change
- **Files:** [[functions/events/notify_expiring_recurring_events.md]] · [[docs/api/events/notify_expiring_recurring_events.md]]
- **Log:** [[updates/2026-05-04.md]]

---

### 2 + 3 + 4 — Notification read state
- `is_read boolean NOT NULL DEFAULT false` added to `notifications` table (migration required)
- New SP: `get_unread_notification_count` — returns `{ "unread_count": N }` for badge display
- New SP: `mark_notifications_read` — marks all or specific notifications as read (owner-scoped)
- `get_notifications` updated to return `is_read` on every notification row
- **Files:** [[functions/notifications/get_notifications.md]] · [[functions/notifications/get_unread_notification_count.md]] · [[functions/notifications/mark_notifications_read.md]] · [[docs/api/notifications/get_notifications.md]] · [[docs/api/notifications/get_unread_notification_count.md]] · [[docs/api/notifications/mark_notifications_read.md]]
- **Log:** [[updates/2026-05-08.md]]

---

### 10 — Collaborator functionality
- New table: `event_collaborators` (pending → accepted | declined, soft delete)
- New column: `event_mst.is_collaborative boolean DEFAULT false`
- New SPs: `invite_collaborator` · `respond_collaborator_invite` · `remove_collaborator`
- `create_event` accepts `p_collaborator_ids uuid[]` to bundle invites at creation
- New SP: `search_collaborator_profiles` — excludes creating profile + already-invited profiles
- Collaborators are **read-only** — no update, delete, or postpone rights
- Invitee receives a notification with accept/decline action data
- **Files:** [[functions/events/invite_collaborator.md]] · [[functions/events/respond_collaborator_invite.md]] · [[functions/events/remove_collaborator.md]] · [[functions/search/search_collaborator_profiles.md]] · [[docs/database/tables/15_event_collaborators.md]]
- **Log:** [[updates/2026-05-03.md]] · [[updates/2026-05-07.md]]

---

## ⏳ Pending Tasks

### 2 + 3 + 4 — Notification read state

**What's needed:**

**Schema change — `notifications` table:**
- Add `is_read boolean NOT NULL DEFAULT false`
- Migration: `ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS is_read boolean NOT NULL DEFAULT false;`

**New SP: `get_unread_notification_count`**
- Input: `p_user_id uuid`
- Returns: `{ "status": true, "data": { "unread_count": N } }`
- Query: `SELECT COUNT(*) FROM notifications WHERE user_id = p_user_id AND is_read = false`

**New SP: `mark_notifications_read`**
- Input: `p_user_id uuid`, `p_notification_ids uuid[] DEFAULT null`
- If `p_notification_ids` is null → mark ALL unread notifications for this user as read
- If `p_notification_ids` is provided → mark only those IDs as read (must belong to this user)
- Returns: `{ "status": true, "message": "N notification(s) marked as read" }`

**Also update `get_notifications`:**
- Include `is_read` field in the SELECT output so clients know which ones are unread

---

### 11 — Postpone / remove a single occurrence in a recurring series

**What's needed:**

Two sub-features:

**A — Skip (remove) a single occurrence:**
- New SP: `skip_recurring_occurrence`
- Input: `p_event_id uuid` (a child occurrence), `p_user_id uuid`
- Soft deletes only that child row (`is_deleted = true`) — parent and other children untouched
- Only the event owner can do this

**B — Postpone a single occurrence:**
- New SP: `postpone_recurring_occurrence`
- Input: `p_event_id uuid`, `p_user_id uuid`, `p_new_date date`, `p_new_time time DEFAULT null`
- Updates `event_date` (and optionally `event_time`) on that child row only
- Validates new date is not in the past
- Only the event owner can do this

> Note: these operate on **child rows** (parent_event_id IS NOT NULL). Applying to a parent or non-recurring event should return an error.

---

### 12 — Profile-level notification settings

**What's needed:**

**Schema change — `creator_profiles` table:**
- Add `reminder_enabled boolean NOT NULL DEFAULT false` — global on/off toggle for this profile
- Add `reminder_minutes int DEFAULT 10` — how many minutes before each event to notify followers
- Migration:
  ```sql
  ALTER TABLE public.creator_profiles
    ADD COLUMN IF NOT EXISTS reminder_enabled boolean NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS reminder_minutes int DEFAULT 10;
  ```

**Behaviour:**
- When a user follows a profile with `reminder_enabled = true`, they automatically receive a notification `reminder_minutes` minutes before every event on that profile
- No manual per-event setup required — it is automatic for all followers
- This is different from the existing `event_reminders` table which is manual and per-event per-user

**New SP: `update_profile_reminder_settings`**
- Input: `p_profile_id uuid`, `p_user_id uuid`, `p_reminder_enabled boolean`, `p_reminder_minutes int DEFAULT null`
- Validates `p_reminder_minutes` is between 1 and 1440 (max 24 hours)
- Owner check: profile must belong to `p_user_id`
- Updates both columns on `creator_profiles`

**Update `process_event_reminders` cron job:**
- Add a second query block that fires for followers of profiles where `reminder_enabled = true`
- Must deduplicate against `event_reminders` (manual) to avoid double-notifying

---

### 13 — Recurring-event notification options

**What's needed:**

This feature allows a user to configure a reminder for an **entire recurring series** rather than individual occurrences.

**Schema — new table `recurring_event_reminders`:**
```sql
CREATE TABLE IF NOT EXISTS public.recurring_event_reminders (
    id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          uuid        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    event_id         uuid        NOT NULL REFERENCES public.event_mst(event_id) ON DELETE CASCADE,
    -- event_id must be the PARENT event (parent_event_id IS NULL, is_recurring = true)
    reminder_minutes int         NOT NULL,
    is_active        boolean     NOT NULL DEFAULT true,
    created_at       timestamptz DEFAULT now(),
    updated_at       timestamptz DEFAULT now(),
    UNIQUE (user_id, event_id)
);
```

**Behaviour:**
- Setting a reminder on the parent event applies automatically to every child occurrence
- `process_event_reminders` resolves child occurrences via `parent_event_id` and fires at the configured time before each child

**New SPs:**
- `set_recurring_reminder` — upsert a row in `recurring_event_reminders`; validates `event_id` is a parent recurring event
- `remove_recurring_reminder` — soft-deactivate (`is_active = false`) or delete the row

**Update `process_event_reminders`:**
- Add a third query block that joins `recurring_event_reminders` → child events via `parent_event_id` and fires at the right time

> **Dependency:** Task 12 (profile-level notifications) should be implemented first, as `process_event_reminders` needs to be refactored for both features together.

---

## Suggested Implementation Order

| Priority | Tasks | Reason |
|----------|-------|--------|
| 1st | #2 · #3 · #4 | Single schema column + 2 small SPs. Quick win, unblocks notification UX. |
| 2nd | #11 | Self-contained. No schema changes — two new SPs on existing tables. |
| 3rd | #12 | Schema change on `creator_profiles` + SP + cron update. |
| 4th | #13 | New table + SPs + cron update. Builds on #12's cron refactor. |
