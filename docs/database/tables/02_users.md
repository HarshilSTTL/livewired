# Table: `users`

> Core authentication and user accounts table.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | int8 | — | No | PRIMARY KEY | Auto-generated user ID |
| created_at | timestamptz | now() | Yes | — | Registration timestamp |
| email | text | NULL | Yes | UNIQUE | Login email — unique across all users |
| is_creator | bool | false | No | — | true = creator mode enabled |
| updated_at | timestamptz | now() | Yes | — | Last update timestamp |
| created_device_ip | text | NULL | **Yes** | — | IP address at registration (nullable) |
| updated_device_ip | text | NULL | **Yes** | — | IP address at last update (nullable) |
| password | text | NULL | Yes | — | Plain/hashed password |

## Foreign Keys

None — `users` is a root table with no FK dependencies.

## Business Rules

- `email` must be unique across all users
- `is_creator` defaults to `false`; set to `true` via `creator_enable` SP
- `created_device_ip` and `updated_device_ip` are both set to the same value on initial registration
- Password is stored as-is (no bcrypt in SP layer as of current implementation)

## ⚠️ Difference from Initial Design

The original design planned `role_id` (FK → roles) to differentiate users. The actual implementation uses `is_creator boolean` instead:
- `is_creator = false` → regular user
- `is_creator = true` → creator

The `roles` table still exists in the schema but is **not linked** to `users` via FK in the current implementation.

## Used By (Stored Procedures)

| SP | How |
|----|-----|
| `register` | INSERT into users |
| `signup` | INSERT into users |
| `login` | SELECT id, email, password |
| `creator_enable` | UPDATE is_creator |
| `submit_platform` | Validates user exists |
| `submit_tags` | Validates user exists |
| `follow_creator` | Validates user exists |
| `unfollow_creator` | Validates user exists |
| `get_following_list` | JOIN via follows.user_id |
| `get_followers_list` | Returns user email |

## SQL Reference

See [`schema/tables/02_users.sql`](../../../schema/tables/02_users.sql)
