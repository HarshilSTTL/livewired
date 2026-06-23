# Admin: `system_config`

**Endpoints:**
- `POST /rpc/get_all_configs` — List all configs (optional filter by category)
- `POST /rpc/list_config_categories` — List available categories
- `POST /rpc/update_config` — Update a config (admin only)

**Schema:** [`schema/tables/16_system_config.md`](../../../schema/tables/16_system_config.md)
**SQL:** [`functions/admin/`](../../../functions/admin/)

---

## Overview

The `system_config` table stores all changeable application settings — auth expiry times, event limits, platform defaults, notification rules, etc. Admins can modify these via API without code changes.

**Access:** Admin-only (requires `role_id = 1`)

---

## Endpoints

### 1. `GET /rpc/get_all_configs`

Fetch all non-sensitive configs, optionally filtered by category.

#### Parameters

| Parameter | Type | Required | Notes |
|---|---|---|---|
| `p_user_id` | uuid | ✅ | Caller's user ID (auth check) |
| `p_category` | text | ❌ | Filter by category: `auth`, `event`, `platform`, `notification`, `general`. If omitted, returns all. |

#### Response

```json
{
  "status": true,
  "data": {
    "email_verification_enabled": {
      "value": "true",
      "type": "boolean",
      "category": "auth",
      "description": "Require email verification on signup",
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    "max_collaborators_per_event": {
      "value": "5",
      "type": "integer",
      "category": "event",
      "description": "Maximum collaborators per event",
      "updated_at": "2026-06-23T10:00:00+00:00"
    }
  }
}
```

#### Examples

**Get all configs:**
```bash
curl -X POST https://yourdb.supabase.co/rest/v1/rpc/get_all_configs \
  -H "apikey: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_user_id": "user-uuid"}'
```

**Get only event configs:**
```bash
curl -X POST https://yourdb.supabase.co/rest/v1/rpc/get_all_configs \
  -H "apikey: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_user_id": "user-uuid", "p_category": "event"}'
```

---

### 2. `GET /rpc/list_config_categories`

List all config categories (for admin UI tabs/sidebar).

#### Parameters

| Parameter | Type | Required | Notes |
|---|---|---|---|
| `p_user_id` | uuid | ✅ | Caller's user ID |

#### Response

```json
{
  "status": true,
  "data": [
    {
      "category": "auth",
      "count": 7,
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    {
      "category": "event",
      "count": 4,
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    {
      "category": "general",
      "count": 3,
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    {
      "category": "notification",
      "count": 2,
      "updated_at": "2026-06-23T10:00:00+00:00"
    },
    {
      "category": "platform",
      "count": 3,
      "updated_at": "2026-06-23T10:00:00+00:00"
    }
  ]
}
```

---

### 3. `PUT /rpc/update_config`

Update a single config value. Admin-only.

#### Parameters

| Parameter | Type | Required | Notes |
|---|---|---|---|
| `p_config_key` | text | ✅ | Key to update (e.g. `max_collaborators_per_event`) |
| `p_config_value` | text | ✅ | New value (always text; SPs cast based on `data_type`) |
| `p_user_id` | uuid | ✅ | Caller's user ID |

#### Response

```json
{
  "status": true,
  "message": "Config updated successfully",
  "data": {
    "config_key": "max_collaborators_per_event",
    "config_value": "10",
    "updated_at": "2026-06-23T10:30:00+00:00"
  }
}
```

#### Examples

**Increase max collaborators to 10:**
```bash
curl -X POST https://yourdb.supabase.co/rest/v1/rpc/update_config \
  -H "apikey: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_config_key": "max_collaborators_per_event",
    "p_config_value": "10",
    "p_user_id": "user-uuid"
  }'
```

**Change email verification expiry to 48 hours:**
```bash
curl -X POST https://yourdb.supabase.co/rest/v1/rpc/update_config \
  -H "apikey: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_config_key": "email_verification_expiry_hours",
    "p_config_value": "48",
    "p_user_id": "user-uuid"
  }'
```

**Update default platforms (JSON):**
```bash
curl -X POST https://yourdb.supabase.co/rest/v1/rpc/update_config \
  -H "apikey: YOUR_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "p_config_key": "default_platforms",
    "p_config_value": "[1,2,3,4]",
    "p_user_id": "user-uuid"
  }'
```

---

## Config Categories

### `auth` (7 settings)
- `email_verification_enabled` — Enable/disable email verification
- `email_verification_expiry_hours` — Token expiry time
- `password_min_length` — Minimum password length
- `password_max_length` — Maximum password length
- `max_login_attempts` — Failed attempts before lockout
- `account_lockout_duration_minutes` — Lockout duration
- `resend_verification_cooldown_minutes` — Cooldown before resend

### `event` (4 settings)
- `default_event_duration_hours` — Default duration if end time not specified
- `max_collaborators_per_event` — Max collaborators per event
- `recurring_event_max_months` — Max months for recurrence generation
- `event_conflict_check_enabled` — Enable conflict detection

### `platform` (3 settings)
- `default_platforms` — Default platform IDs (JSON array)
- `featured_platforms` — Featured platforms (JSON array)
- `platform_stream_url_validation` — Require stream URL

### `notification` (2 settings)
- `recurring_event_expiry_notification_days` — Days before recurring end to notify
- `notification_retention_days` — Days to keep notifications

### `general` (3 settings)
- `app_name` — Application name
- `max_username_length` — Maximum username length
- `min_username_length` — Minimum username length

---

## Error Responses

### Admin access denied
```json
{
  "status": false,
  "message": "Admin access required"
}
```

### Config key not found
```json
{
  "status": false,
  "message": "Config key not found: invalid_key_name"
}
```

### Invalid input
```json
{
  "status": false,
  "message": "Config key is required"
}
```

---

## How SPs use config

SPs read config via the `get_config(key, default)` helper:

```sql
-- In signup SP
v_expiry := now() + (get_config('email_verification_expiry_hours', '24') || ' hours')::INTERVAL;

-- In create_event_v2 SP
v_max_collabs := (get_config('max_collaborators_per_event', '5'))::int;
```

No code changes needed when admins update config — SPs read fresh values on each call.
