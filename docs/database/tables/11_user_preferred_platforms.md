# Table: `user_preferred_platforms`

> Stores which streaming platforms a user selected during onboarding. Replaced entirely on each `submit_platform` call.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Record ID |
| user_id | uuid | NULL | Yes | FK → users.id | Which user |
| platform_id | int8 | NULL | Yes | FK → platforms.plat_id | Which platform |
| created_at | timestamptz | now() | Yes | — | When preference was set |

## Foreign Keys

| Constraint | Column | References |
|-----------|--------|-----------|
| user_preferred_platforms_user_id_fkey | user_id | `public.users.id` |
| user_preferred_platforms_platform_id_fkey | platform_id | `public.platforms.plat_id` |

## Business Rules

- `submit_platform` **deletes all existing rows** for the user then re-inserts — full replace, not append
- `platform_id` is `int8` here (unlike `event_platforms.platform_id` which is `int4`)
- No unique constraint enforced at DB level — uniqueness controlled by the delete+insert pattern in SP

## Referenced By (Stored Procedures)

| SP | How |
|----|-----|
| `submit_platform` | DELETE all + INSERT new set |

## SQL Reference

See [`schema/tables/11_user_preferred_platforms.md`](../../../schema/tables/11_user_preferred_platforms.md)
