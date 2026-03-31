# Table: `profile_tags`

> Junction table linking creator profiles to interest/category tags.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Record ID |
| profile_id | uuid | NULL | **Yes** | FK → creator_profiles.id | Which profile (nullable) |
| tag_id | int8 | NULL | **Yes** | FK → tags.tag_id | Which tag (nullable) |

## Foreign Keys

| Column | References | On Delete |
|--------|-----------|-----------|
| profile_id | `creator_profiles.id` | CASCADE |
| tag_id | `tags.tag_id` | — |

## Business Rules

- Both `profile_id` and `tag_id` are nullable at the table level
- `create_profile` SP validates tag IDs exist before inserting
- Maximum 10 tags per profile — enforced in `create_profile` SP
- Tags are bulk-inserted via `INSERT ... SELECT unnest(p_tag_ids)` in `create_profile` SP

## Referenced By (Stored Procedures)

| SP | How |
|----|-----|
| `create_profile` | Bulk INSERT via unnest(p_tag_ids) |
| `update_profile` | DELETE + re-INSERT tags |

## SQL Reference

See [`schema/tables/07_profile_tags.md`](../../../schema/tables/07_profile_tags.md)
