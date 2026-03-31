# Table: `platforms`

> Master list of all supported live streaming platforms.

## Columns

| Column     | Type        | Default | Nullable | Constraints | Notes                                                 |
| ---------- | ----------- | ------- | -------- | ----------- | ----------------------------------------------------- |
| plat_id    | int8        | —       | No       | PRIMARY KEY | Platform ID                                           |
| created_at | timestamptz | now()   | Yes      | —           | Record creation time                                  |
| plat_name  | text        | NULL    | Yes      | —           | Platform display name (YouTube, Twitch, Kick, Rumble) |
| logo_url   | text        | NULL    | **Yes**  | —           | Platform logo image URL (nullable)                    |
| is_active  | int2        | `1`     | Yes      | —           | 1 = active, 0 = inactive                              |

## Foreign Keys

None — `platforms` is a lookup/master table with no FK dependencies.

## Business Rules

- `is_active = 1` means the platform is available for selection
- `is_active = 0` means the platform is hidden/disabled
- `logo_url` is nullable — platform may not have a logo configured yet
- `get_all_platforms` SP filters by `is_active = 1` (only returns active platforms)

## Seed Data

| plat_id | plat_name |
|---------|-----------|
| 1 | YouTube |
| 2 | Twitch |
| 3 | Kick |
| 4 | Rumble |

## Referenced By (Stored Procedures & Tables)

| SP / Table                  | How                                                        |
| --------------------------- | ---------------------------------------------------------- |
| `get_all_platforms`         | SELECT WHERE is_active = 1                                 |
| `creator_platform_accounts` | FK via platform_id                                         |
| `event_platforms`           | FK via platform_id (integer — cast to bigint when joining) |
| `user_preferred_platforms`  | FK via platform_id                                         |
| `get_creators`              | JOIN to get platform logo + name                           |
| `get_following_list`        | JOIN to get platform details                               |
| `get_event_list`            | JOIN to get streaming platform info                        |

## SQL Reference

See [`schema/tables/03_platforms.md`](../../../schema/tables/03_platforms.md)
