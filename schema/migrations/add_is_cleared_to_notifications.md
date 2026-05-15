# Migration: Add `is_cleared` column to notifications table

```sql
-- Add is_cleared column
ALTER TABLE notifications
ADD COLUMN is_cleared bool NOT NULL DEFAULT false;

-- Add index for efficient filtering
CREATE INDEX idx_notifications_user_id_is_cleared ON notifications(user_id, is_cleared);
```

---

## Changes

1. **Add `is_cleared` column** to `notifications` table
   - Type: `bool`
   - Default: `false`
   - Not nullable

2. **Add index** for efficient queries filtering by `is_cleared` status

---

## Purpose

This migration enables the `clear_notifications` API endpoint to mark notifications as cleared (hidden from the user's notification list) without deleting them from the database.

---

## Rollback

```sql
DROP INDEX IF EXISTS idx_notifications_user_id_is_cleared;
ALTER TABLE notifications DROP COLUMN is_cleared;
```
