# Table: `user_interests`

> Stores which interest/category tags a user selected during onboarding. Replaced entirely on each `submit_tags` call.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Record ID |
| user_id | uuid | NULL | Yes | FK → users.id | Which user |
| tag_id | int8 | NULL | Yes | FK → tags.tag_id | Which interest tag |
| created_at | timestamptz | now() | Yes | — | When interest was set |

## Foreign Keys

| Constraint | Column | References |
|-----------|--------|-----------|
| user_interests_user_id_fkey | user_id | `public.users.id` |
| user_interests_tag_id_fkey | tag_id | `public.tags.tag_id` |

## Business Rules

- `submit_tags` **deletes all existing rows** for the user then re-inserts — full replace, not append
- No unique constraint enforced at DB level — uniqueness controlled by the delete+insert pattern in SP

## Referenced By (Stored Procedures)

| SP | How |
|----|-----|
| `submit_tags` | DELETE all + INSERT new set |

## SQL Reference

See [`schema/tables/12_user_interests.md`](../../../schema/tables/12_user_interests.md)
