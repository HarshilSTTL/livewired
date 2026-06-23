# Table: `system_config`

> Application-wide configuration table. Stores all changeable settings (auth, events, platforms, notifications, etc.) so admins can modify them without code changes.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Config entry ID |
| config_key | text | — | No | UNIQUE | Setting identifier (e.g. `max_collaborators_per_event`) |
| config_value | text | — | No | — | Setting value (can be JSON for complex types) |
| data_type | text | `'string'` | Yes | — | Value type: `string`, `integer`, `boolean`, `json`, `interval` |
| category | text | NULL | Yes | — | Grouping: `auth`, `event`, `platform`, `notification`, `general` |
| description | text | NULL | Yes | — | Human-readable explanation of what this setting does |
| is_sensitive | boolean | false | No | — | Hide in admin UI if `true` (e.g., API keys) |
| created_at | timestamptz | now() | Yes | — | When this config was added |
| updated_at | timestamptz | now() | Yes | — | Last time this config was modified |

## Indexes

```sql
CREATE INDEX idx_system_config_category ON system_config(category);
CREATE INDEX idx_system_config_key ON system_config(config_key);
```

## Business Rules

- `config_key` is unique — one key, one value at a time
- `config_value` is always stored as text; SPs cast to appropriate type based on `data_type`
- `is_sensitive = true` hides value from `/rpc/get_all_configs` for security
- `category` helps admins group related settings in UI
- `updated_at` tracks when last modified for audit purposes

## Default Values

| config_key | config_value | data_type | category | Notes |
|---|---|---|---|---|
| `email_verification_enabled` | `true` | boolean | auth | Require email verification on signup |
| `email_verification_expiry_hours` | `24` | integer | auth | Hours before token expires |
| `password_min_length` | `8` | integer | auth | Minimum password length |
| `password_max_length` | `128` | integer | auth | Maximum password length |
| `max_login_attempts` | `5` | integer | auth | Failed attempts before lockout |
| `account_lockout_duration_minutes` | `15` | integer | auth | Minutes account is locked |
| `resend_verification_cooldown_minutes` | `5` | integer | auth | Cooldown before resend allowed |
| `default_event_duration_hours` | `2` | integer | event | Default event duration if end time not specified |
| `max_collaborators_per_event` | `5` | integer | event | Maximum collaborators per event |
| `recurring_event_max_months` | `12` | integer | event | Max months for recurring event generation |
| `event_conflict_check_enabled` | `true` | boolean | event | Enable conflict detection |
| `default_platforms` | `[1,2,3]` | json | platform | Default platform IDs (YouTube, Twitch, Rumble, etc.) |
| `featured_platforms` | `[1,2]` | json | platform | Featured platforms shown first in UI |
| `platform_stream_url_validation` | `true` | boolean | platform | Require stream URL for each platform |
| `recurring_event_expiry_notification_days` | `7` | integer | notification | Days before recurring end to notify owner |
| `notification_retention_days` | `30` | integer | notification | Days to keep notifications before auto-delete |
| `app_name` | `LiveWired` | string | general | Application name |
| `max_username_length` | `50` | integer | general | Maximum username length |
| `min_username_length` | `3` | integer | general | Minimum username length |

## Used By (Stored Procedures)

| SP | How | Config Keys |
|---|---|---|
| `signup` | Read token expiry | `email_verification_expiry_hours` |
| `create_event` (v1.0) | Read defaults | `default_event_duration_hours`, `max_collaborators_per_event` |
| `create_event_v2` | Read defaults | `default_event_duration_hours`, `max_collaborators_per_event` |
| `get_config` | Fetch any single value | — |
| `get_all_configs` | Admin dashboard | All non-sensitive keys |
| `update_config` | Admin updates | Any key |

## SQL Reference

See [`functions/admin/`](../../../functions/admin/) for CRUD operations.
