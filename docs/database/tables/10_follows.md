# Table: `follows`

> Tracks which users follow which creator profiles. Uses soft delete pattern.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Record ID |
| user_id | uuid | NULL | Yes | FK → users.id | The follower |
| profile_id | uuid | NULL | Yes | FK → creator_profiles.id | Profile being followed |
| created_at | timestamptz | now() | **Yes** | — | When followed (nullable) |
| is_active | bool | true | No | — | true = following, false = unfollowed |
| unfollowed_at | timestamptz | NULL | **Yes** | — | When unfollowed (nullable) |

## Foreign Keys

| Constraint | Column | References |
|-----------|--------|-----------|
| fk_user | user_id | `public.users.id` |
| fk_profile | profile_id | `public.creator_profiles.id` |

## Business Rules

- **Follow** → INSERT new row with `is_active = true`, `unfollowed_at = null`
- **Unfollow** → soft delete: `is_active = false`, `unfollowed_at = now()`
- **Re-follow** → UPDATE existing row: `is_active = true`, `unfollowed_at = null`, `created_at = now()`
- No duplicate rows — one row per `(user_id, profile_id)` pair; re-follow updates existing row
- A user cannot follow their own creator profile (enforced in `follow_creator` SP)
- Follower count = `COUNT(*) FROM follows WHERE profile_id = ? AND is_active = true`
- `created_at` and `unfollowed_at` are both nullable

## Referenced By (Stored Procedures)

| SP | How |
|----|-----|
| `follow_creator` | INSERT or UPDATE |
| `unfollow_creator` | UPDATE is_active=false, unfollowed_at=now() |
| `get_following_list` | SELECT WHERE is_active=true |
| `get_followers_list` | SELECT WHERE is_active=true |
| `get_creators` | Subquery COUNT followers |
| `get_event_list` | Subquery COUNT followers |
| `search_events` | Subquery COUNT followers |
| `search_profiles` | Subquery COUNT followers |

## SQL Reference

See [`schema/tables/10_follows.md`](../../../schema/tables/10_follows.md)
