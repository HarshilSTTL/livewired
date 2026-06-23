# `init_system_config` — Insert Default Values

```sql
-- Function: init_system_config
-- Group: Admin
-- Purpose: Populate system_config table with default values.
--          Run once during initial deployment.
--
-- This is a reference SQL — not a stored procedure.
-- Execute directly in Supabase SQL editor.

-- ─────────────────────────────────────────────────────────────────────────────
-- INSERT DEFAULT CONFIG VALUES
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO system_config (config_key, config_value, data_type, category, description, is_sensitive)
VALUES
    -- AUTH SETTINGS
    ('email_verification_enabled', 'true', 'boolean', 'auth', 'Require email verification on signup', false),
    ('email_verification_expiry_hours', '24', 'integer', 'auth', 'Hours until verification token expires', false),
    ('password_min_length', '8', 'integer', 'auth', 'Minimum password length', false),
    ('password_max_length', '128', 'integer', 'auth', 'Maximum password length', false),
    ('max_login_attempts', '5', 'integer', 'auth', 'Failed login attempts before account lockout', false),
    ('account_lockout_duration_minutes', '15', 'integer', 'auth', 'Minutes to lock account after max failed attempts', false),
    ('resend_verification_cooldown_minutes', '5', 'integer', 'auth', 'Minutes user must wait before requesting new verification email', false),

    -- EVENT SETTINGS
    ('default_event_duration_hours', '2', 'integer', 'event', 'Default event duration in hours if end time not specified', false),
    ('max_collaborators_per_event', '5', 'integer', 'event', 'Maximum number of collaborators allowed per event', false),
    ('recurring_event_max_months', '12', 'integer', 'event', 'Maximum months for recurring event pre-generation', false),
    ('event_conflict_check_enabled', 'true', 'boolean', 'event', 'Enable conflict detection for overlapping events', false),

    -- PLATFORM SETTINGS
    ('default_platforms', '[1,2,3]', 'json', 'platform', 'Default platform IDs shown to new users (YouTube=1, Twitch=2, Rumble=3, Kick=4, etc.)', false),
    ('featured_platforms', '[1,2]', 'json', 'platform', 'Featured platforms shown first in UI (YouTube, Twitch)', false),
    ('platform_stream_url_validation', 'true', 'boolean', 'platform', 'Require stream URL for each platform when creating events', false),

    -- NOTIFICATION SETTINGS
    ('recurring_event_expiry_notification_days', '7', 'integer', 'notification', 'Days before recurring event end to send expiry notification to owner', false),
    ('notification_retention_days', '30', 'integer', 'notification', 'Days to keep notifications before auto-delete', false),

    -- GENERAL SETTINGS
    ('app_name', 'LiveWired', 'string', 'general', 'Application name used in emails and UI', false),
    ('max_username_length', '50', 'integer', 'general', 'Maximum allowed username length', false),
    ('min_username_length', '3', 'integer', 'general', 'Minimum required username length', false)
ON CONFLICT (config_key) DO NOTHING;

-- Verify insertion
SELECT config_key, config_value, category, updated_at
FROM system_config
ORDER BY category, config_key;
```

---

## Deployment steps

1. **Create the table** (if not exists):
   ```sql
   CREATE TABLE IF NOT EXISTS system_config (
       id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
       config_key text NOT NULL UNIQUE,
       config_value text NOT NULL,
       data_type text DEFAULT 'string',
       category text,
       description text,
       is_sensitive boolean DEFAULT false,
       created_at timestamptz DEFAULT now(),
       updated_at timestamptz DEFAULT now()
   );

   CREATE INDEX idx_system_config_category ON system_config(category);
   CREATE INDEX idx_system_config_key ON system_config(config_key);
   ```

2. **Create the helper SPs**: `get_config`, `get_all_configs`, `list_config_categories`, `update_config`
   (From their respective `.md` files)

3. **Run this init SQL** in Supabase SQL Editor to insert default values

4. **Verify** that all 18 default configs were inserted

5. **Update existing SPs** to use `get_config()` instead of hardcoded values
