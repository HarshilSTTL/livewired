# Table: `creator_profiles`

> Public creator profiles. A user with `role_id = 2` can create one or more independent profiles.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Profile ID |
| user_id | uuid | — | No | FK → users.id | Owner of the profile |
| profile_name | text | — | No | — | Display name |
| username | text | — | No | **UNIQUE** | Unique handle across all profiles |
| avatar | text | NULL | **Yes** | — | Profile picture Base64 (nullable) |
| bio | text | NULL | **Yes** | — | Short bio (nullable) |
| is_default | boolean | false | No | — | Is this the primary profile? |
| status | text | 'active' | No | — | `active` / `suspended` / `deleted` |
| show_followers | boolean | true | No | — | Whether to show follower count publicly |
| created_at | timestamptz | now() | Yes | — | Profile creation time |
| updated_at | timestamptz | now() | Yes | — | Last update time |

## Foreign Keys

| Column | References | On Delete |
|--------|-----------|-----------|
| user_id | `users.id` | CASCADE |

## Business Rules

- Only users with `role_id = 2` can create profiles (checked in `create_profile` SP)
- `username` is **globally unique** across all creator profiles
- First profile created is automatically set as `is_default = true`
- When a new profile is set as default, all other profiles for the same user are set to `is_default = false`
- `avatar` and `bio` are optional (nullable)
- Valid `status` values: `active`, `suspended`, `deleted`
  - `suspended` → UI shows "This account has been suspended"
  - `deleted` → UI shows "This account no longer exists"
- `show_followers` controls whether followers are visible on the profile — default `true`
- Maximum 10 tags per profile (enforced in `create_profile` SP)

## Referenced By (Stored Procedures & Tables)

| SP / Table | How |
|------------|-----|
| `create_profile` | INSERT |
| `update_profile` | UPDATE |
| `get_profiles_by_username` | SELECT by username |
| `get_single_profile_by_username` | SELECT single by username |
| `get_creators` | SELECT all active |
| `follow_creator` | Validates profile exists and is active |
| `get_following_list` | JOIN via follows.profile_id |
| `get_followers_list` | Validated by profile_id |
| `get_event_list` | JOIN via event_mst.profile_id |
| `creator_platform_accounts` | FK via profile_id |
| `profile_tags` | FK via profile_id |
| `event_mst` | FK via profile_id |
| `follows` | FK via profile_id |

## SQL Reference

See [`schema/tables/05_creator_profiles.md`](../../../schema/tables/05_creator_profiles.md)
