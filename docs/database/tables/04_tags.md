# Table: `tags`

> Interest/category tags used for personalisation during onboarding and creator profile setup.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| tag_id | int8 | NULL | No | PRIMARY KEY | Tag ID |
| tag_name | text | NULL | **Yes** | — | Tag display name (nullable) |

## Foreign Keys

None — `tags` is a lookup/master table with no FK dependencies.

## Business Rules

- `tag_name` is nullable — a tag may exist without a name (edge case)
- No `is_active` flag — all tags are always returned by `get_all_tags`
- Tags are selected by users during onboarding → saved in `user_interests`
- Tags are assigned to creator profiles → saved in `profile_tags`

## Seed Data

| tag_id | tag_name |
|--------|----------|
| 1 | Gaming |
| 2 | Tech |
| 3 | Music |
| 4 | Sports |
| 5 | Travel |
| 6 | Finance |
| 7 | Cooking |
| 8 | Health |
| 9 | News |
| 10 | Science |
| 11 | Entertainment |
| 12 | Politics |
| 13 | Automotive |

## Referenced By (Stored Procedures & Tables)

| SP / Table | How |
|------------|-----|
| `get_all_tags` | SELECT all tags |
| `submit_tags` | Validates tag IDs exist |
| `user_interests` | FK via tag_id |
| `profile_tags` | FK via tag_id |

## SQL Reference

See [`schema/tables/04_tags.md`](../../../schema/tables/04_tags.md)
