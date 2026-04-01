# Database Overview

**Total Tables:** 12
**Database:** PostgreSQL via Supabase

---

## Table Index

| #   | Table                                                                 | Purpose                             |
| --- | --------------------------------------------------------------------- | ----------------------------------- |
| 1   | [roles](./tables/01_roles.md)                                         | 3 user roles (user, creator, admin) |
| 2   | [users](./tables/02_users.md)                                         | Core auth and user accounts         |
| 3   | [platforms](./tables/03_platforms.md)                                 | Supported streaming platforms       |
| 4   | [tags](./tables/04_tags.md)                                           | Interest/category tags              |
| 5   | [creator_profiles](./tables/05_creator_profiles.md)                   | Public creator profiles             |
| 6   | [creator_platform_accounts](./tables/06_creator_platform_accounts.md) | Creator → platform channel links    |
| 7   | [profile_tags](./tables/07_profile_tags.md)                           | Junction: profile ↔ tags            |
| 8   | [event_mst](./tables/08_event_mst.md)                                 | Master event records                |
| 9   | [event_platforms](./tables/09_event_platforms.md)                     | Event → platform stream links       |
| 10  | [follows](./tables/10_follows.md)                                     | User → creator follow relationships |
| 11  | [user_preferred_platforms](./tables/11_user_preferred_platforms.md)   | User platform preferences           |
| 12  | [user_interests](./tables/12_user_interests.md)                       | User interest tags                  |


---

## Relationship Map

```
roles
  └── users (role_id)
        ├── creator_profiles (user_id)
        │       ├── creator_platform_accounts (profile_id)
        │       │         └── platforms (platform_id)
        │       ├── profile_tags (profile_id)
        │       │         └── tags (tag_id)
        │       └── event_mst (profile_id)
        │                 └── event_platforms (event_id)
        │                           └── platforms (platform_id)
        ├── follows (user_id)
        │       └── creator_profiles (profile_id)
        ├── user_preferred_platforms (user_id)
        │       └── platforms (platform_id)
        └── user_interests (user_id)
                └── tags (tag_id)
```

---

## Extensions Required

- `pg_trgm` — for fuzzy/elastic search on profiles and events

## Indexes

- Trigram indexes on `creator_profiles` (profile_name, username, bio)
- Trigram indexes on `event_mst` (title, description)

See `schema/extensions/` and `schema/indexes/` for SQL.
