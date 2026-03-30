# Table: `creator_platform_accounts`

> Links a creator profile to their accounts on specific streaming platforms.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Record ID |
| profile_id | uuid | — | No | FK → creator_profiles.id | Which profile |
| platform_id | int8 | — | No | FK → platforms.plat_id | Which platform |
| channel_url | text | NULL | **Yes** | — | Full channel/stream URL (nullable) |
| username | text | NULL | **Yes** | — | Username on that platform (nullable) |
| is_default | boolean | false | No | — | Is this the primary platform for the profile |

## Foreign Keys

| Column | References | On Delete |
|--------|-----------|-----------|
| profile_id | `creator_profiles.id` | CASCADE |
| platform_id | `platforms.plat_id` | — |

## Business Rules

- `channel_url` is nullable at the table level, but `create_profile` SP validates it is required when platforms are passed
- `username` is nullable — defaults to the profile's username when inserted via `create_profile` SP
- `is_default` marks the primary platform for a creator profile
- One profile can be linked to multiple platforms (one row per platform)

## Referenced By (Stored Procedures)

| SP | How |
|----|-----|
| `create_profile` | INSERT per platform in p_platforms array |
| `update_profile` | UPDATE platform links |
| `get_creators` | JOIN to get platform list per creator |
| `get_following_list` | JOIN to get platform list |
| `get_event_list` | JOIN via profile for platform info |

## SQL Reference

See [`schema/tables/06_creator_platform_accounts.sql`](../../../schema/tables/06_creator_platform_accounts.sql)
