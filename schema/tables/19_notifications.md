# Table: `notifications`

```sql
CREATE TABLE IF NOT EXISTS notifications (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    title           text,
    body            text,
    data            jsonb,
    is_read         bool NOT NULL DEFAULT false,
    is_cleared      bool NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_notifications_user_id_created_at ON notifications(user_id, created_at DESC);
CREATE INDEX idx_notifications_user_id_is_read ON notifications(user_id, is_read);
CREATE INDEX idx_notifications_user_id_is_cleared ON notifications(user_id, is_cleared);
```

---

## Columns

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `id` | uuid | ❌ | `gen_random_uuid()` | Primary key |
| `user_id` | uuid | ❌ | — | Foreign key to `users` table. Cascade on delete. |
| `title` | text | ✅ | NULL | Notification title (push notification title) |
| `body` | text | ✅ | NULL | Notification body (event title or descriptive text) |
| `data` | jsonb | ✅ | NULL | JSON payload containing type, event_id, profile_id, reminder_minutes, etc. |
| `is_read` | bool | ❌ | `false` | Whether the notification has been marked as read |
| `is_cleared` | bool | ❌ | `false` | Whether the notification has been cleared (hidden from list) |
| `created_at` | timestamptz | ❌ | `now()` | Timestamp when the notification was created |

---

## Indexes

- `idx_notifications_user_id_created_at` — for efficient `get_notifications` queries (user + time-based sorting)
- `idx_notifications_user_id_is_read` — for efficient `get_unread_notification_count` queries
- `idx_notifications_user_id_is_cleared` — for efficient filtering out cleared notifications

---

## Foreign Keys

| Foreign Key | References | On Delete |
|-------------|-----------|-----------|
| `user_id` | `public.users(id)` | CASCADE |

---

## Notes

- `is_read` = notification has been viewed/marked as read
- `is_cleared` = notification has been hidden/deleted from the user's notification list
- Both flags default to `false`
- A notification can be both read AND cleared
- Cleared notifications are excluded from `get_notifications` and `get_unread_notification_count`
