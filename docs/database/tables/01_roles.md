# Table: `roles`

> Lookup table for user roles. Controls what a user can do in the app.
> Referenced by `users.role_id`.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| role_id | int8 | — | No | PRIMARY KEY | Role identifier |
| role_name | text | NULL | Yes | — | Human-readable role label |

## Foreign Keys

None — this is a lookup/seed table. It is referenced by:

| Table | Column | Constraint |
|-------|--------|-----------|
| `users` | `role_id` | FK → roles.role_id |

## Seed Data

| role_id | role_name |
|---------|-----------|
| 1 | user |
| 2 | creator |

> Assigned via `is_creator` SP: sets `role_id = 2` (creator) or `role_id = 1` (user).

## Business Rules

- `role_id = 1` → regular user (default after registration)
- `role_id = 2` → creator — required to call `create_profile`
- Role is promoted/demoted via the `is_creator` SP (POST /rpc/is_creator)
- `create_profile` validates `role_id = 2` before allowing profile creation
- No FK constraint defined on `roles` table itself (it is the parent table)

## Referenced By (Stored Procedures)

| SP | How |
|----|-----|
| `is_creator` | Sets `users.role_id = 2` (creator) or `1` (user) |
| `create_profile` | Checks `users.role_id = 2` before allowing profile creation |

## SQL Reference

See [`schema/tables/01_roles.sql`](../../../schema/tables/01_roles.sql)
