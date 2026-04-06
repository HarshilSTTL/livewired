# Table: `users`

> Core authentication and user accounts table.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Auto-generated user ID |
| created_at | timestamptz | now() | Yes | — | Registration timestamp |
| email | text | NULL | Yes | UNIQUE | Login email — unique across all users |
| is_creator | bool | false | No | — | Legacy field — role now tracked via `role_id` |
| updated_at | timestamptz | now() | Yes | — | Last update timestamp |
| created_device_ip | text | NULL | **Yes** | — | IP address at registration (nullable) |
| updated_device_ip | text | NULL | **Yes** | — | IP address at last update (nullable) |
| password | text | NULL | **Yes** | — | Plain/hashed password — `NULL` for Google users |
| username | text | NULL | **Yes** | UNIQUE | Account-level username — required on new registrations, NULL for existing rows |
| role_id | int8 | — | Yes | — | 1 = user, 2 = creator — set by `is_creator` SP |
| auth_provider | text | `'email'` | Yes | — | `'email'` = registered with password · `'google'` = Google OAuth |
| is_deleted | bool | false | No | — | Soft delete flag — `true` = account is deleted |
| deleted_at | timestamptz | NULL | **Yes** | — | Timestamp when account was soft deleted |

## Foreign Keys

None — `users` is a root table. `role_id` references the `roles` table logically but no FK constraint is enforced at DB level.

## Business Rules

- `email` must be unique across all users
- `username` must be unique across all users (case-insensitive check in SPs); NULL allowed only for rows created before this column was added
- `username` is required by `signup` and `register` SPs — minimum 3 characters
- `role_id` is automatically set to `2` by `create_profile` when a user creates their first creator profile — no separate step needed
- Any registered user can create a creator profile — there is no pre-approval gate
- `is_creator` boolean is also present but `role_id` is what SPs check for creator permission
- `created_device_ip` and `updated_device_ip` are both set to the same value on initial registration
- Password is stored as-is (no bcrypt in SP layer as of current implementation)
- `create_profile` SP checks `role_id = 2` before allowing profile creation
- `password` is `NULL` for Google users — they authenticate via Supabase OAuth, not this column
- `auth_provider = 'google'` users are created/found via the `google_auth` SP
- If a Google user signs in with an email that already exists (`auth_provider = 'email'`), they get the same account — no duplicate is created

## ⚠️ Design Notes

- The `is_creator` SP was originally documented as `creator_enable` — actual DB function name is `is_creator`
- Both `is_creator` (bool) and `role_id` (int8) exist on the table; SPs use `role_id` for permission checks

## Used By (Stored Procedures)

| SP | How |
|----|-----|
| `register` | INSERT into users (email/password flow) |
| `signup` | INSERT into users (email/password flow) |
| `login` | SELECT id, email, password (email/password flow) |
| `google_auth` | INSERT or SELECT by email (Google OAuth flow) |
| `is_creator` | UPDATE role_id, updated_device_ip, updated_at |
| `create_profile` | CHECK role_id = 2 |
| `submit_platform` | Validates user exists |
| `submit_tags` | Validates user exists |
| `follow_creator` | Validates user exists |
| `unfollow_creator` | Validates user exists |
| `get_following_list` | JOIN via follows.user_id |
| `get_followers_list` | Returns user email |

## SQL Reference

See [`schema/tables/02_users.md`](../../../schema/tables/02_users.md)
