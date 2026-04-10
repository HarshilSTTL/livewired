# LiveWired — API Index

> Master cross-reference for all stored procedures, tables, and schemas.
> Every API is linked to its SQL file, API doc, and the tables it reads/writes.

**Total SPs:** 24 &nbsp;|&nbsp; **Tables:** 13 &nbsp;|&nbsp; **Groups:** 7

---

## Quick Navigation

| Group        | SPs | Jump                          |
| ------------ | --- | ----------------------------- |
| 🔐 Auth      | 3   | [→ Auth](#-auth)              |
| 👤 Profiles  | 7   | [→ Profiles](#-profiles)      |
| 🎯 Platforms | 2   | [→ Platforms](#-platforms)    |
| 🏷️ Tags     | 2   | [→ Tags](#-tags)              |
| 📅 Events    | 3   | [→ Events](#-events)          |
| 👥 Follow    | 5   | [→ Follow](#-follow)          |
| 🔍 Search    | 2   | [→ Search](#-search)          |
|              |     | [→ Table Index](#table-index) |
|              |     | [→ File Map](#file-map)       |

---

## 🔐 Auth

| SP | Endpoint | Input | Tables | SQL | Doc |
|---|---|---|---|---|---|
| `register` | POST /rpc/register | email, password, created_device_i | `users` ✏️ | [SQL](../functions/auth/register.md) | [Doc](auth/register.md) |
| `signup` | POST /rpc/signup | email, password, created_device_ip | `users` ✏️ | [SQL](../functions/auth/signup.md) | [Doc](auth/signup.md) |
| `login` | POST /rpc/login | email, password | `users` 👁️ | [SQL](../functions/auth/login.md) | [Doc](auth/login.md) |

**Tables involved:** [`users`](database/tables/02_users.md)

**Notes:**
- `register` and `signup` both insert into `users` — `signup` has better validation
- Plain text password compare in `login` — no hashing
- `register` has a typo param: `created_device_i` (not `created_device_ip`)

---

## 👤 Profiles

| SP | Endpoint | Input | Tables | SQL | Doc |
|---|---|---|---|---|---|
| `is_creator` | POST /rpc/is_creator | p_user_id, p_is_creator | `users` ✏️ | [SQL](../functions/profiles/creator_enable.md) | [Doc](profiles/creator_enable.md) |
| `create_profile` | POST /rpc/create_profile | p_user_id, p_profile_name, p_username, p_platforms (jsonb), p_tag_ids (bigint[]), ... | `creator_profiles` ✏️ `creator_platform_accounts` ✏️ `profile_tags` ✏️ | [SQL](../functions/profiles/create_profile.md) | [Doc](profiles/create_profile.md) |
| `update_profile` | POST /rpc/update_profile | p_profile_id, p_user_id, + any fields to update | `creator_profiles` ✏️ `creator_platform_accounts` ✏️ `profile_tags` ✏️ | [SQL](../functions/profiles/update_profile.md) | [Doc](profiles/update_profile.md) |
| `get_user_profiles` | POST /rpc/get_user_profiles | p_user_id | `creator_profiles` 👁️ | [SQL](../functions/profiles/get_user_profiles.md) | [Doc](profiles/get_user_profiles.md) |
| `get_profile_by_id` | POST /rpc/get_profile_by_id | p_profile_id | `creator_profiles` 👁️ `creator_platform_accounts` 👁️ `profile_tags` 👁️ `follows` 👁️ | [SQL](../functions/profiles/get_profile_by_id.md) | [Doc](profiles/get_profile_by_id.md) |
| `get_profile_by_username` | POST /rpc/get_profile_by_username | p_username | `creator_profiles` 👁️ `creator_platform_accounts` 👁️ `profile_tags` 👁️ `follows` 👁️ | [SQL](../functions/profiles/get_profile_by_username.md) | [Doc](profiles/get_profile_by_username.md) |
| `get_profile_by_userid` | POST /rpc/get_profile_by_userid | p_user_id | `creator_profiles` 👁️ `creator_platform_accounts` 👁️ `profile_tags` 👁️ `follows` 👁️ | [SQL](../functions/profiles/get_profile_by_userid.md) | [Doc](profiles/get_profile_by_userid.md) |

**Tables involved:** [`users`](database/tables/02_users.md) · [`creator_profiles`](database/tables/05_creator_profiles.md) · [`creator_platform_accounts`](database/tables/06_creator_platform_accounts.md) · [`profile_tags`](database/tables/07_profile_tags.md) · [`follows`](database/tables/10_follows.md)

**When to use which GET:**

| SP | Input | Returns | Use Case |
|---|---|---|---|
| `get_user_profiles` | user_id | id, name, avatar only | Post-login profile picker |
| `get_profile_by_id` | profile_id | Full detail | After picking profile / profile dashboard |
| `get_profile_by_username` | username | Full detail | Public profile view page |
| `get_profile_by_userid` | user_id | Full detail (all profiles) | Profile management screen |

---

## 🎯 Platforms

| SP | Endpoint | Input | Tables | SQL | Doc |
|---|---|---|---|---|---|
| `get_all_platforms` | GET /rpc/get_all_platforms | none | `platforms` 👁️ | [SQL](../functions/platforms/get_all_platforms.md) | [Doc](platforms/get_all_platforms.md) |
| `submit_platform` | POST /rpc/submit_platform | p_user_id, p_platformid (int[]) | `user_preferred_platforms` ✏️ | [SQL](../functions/platforms/submit_platform.md) | [Doc](platforms/submit_platform.md) |

**Tables involved:** [`platforms`](database/tables/03_platforms.md) · [`user_preferred_platforms`](database/tables/11_user_preferred_platforms.md)

**Notes:**
- `submit_platform` is **replace-all** — deletes all existing rows then re-inserts
- Error codes returned: `USER_NOT_FOUND` · `EMPTY_PLATFORM_LIST` · `INVALID_PLATFORM_ID`

---

## 🏷️ Tags

| SP | Endpoint | Input | Tables | SQL | Doc |
|---|---|---|---|---|---|
| `get_all_tags` | GET /rpc/get_all_tags | none | `tags` 👁️ | [SQL](../functions/tags/get_all_tags.md) | [Doc](tags/get_all_tags.md) |
| `submit_tags` | POST /rpc/submit_tags | p_user_id, p_tag_ids (bigint[]) | `user_interests` ✏️ | [SQL](../functions/tags/submit_tags.md) | [Doc](tags/submit_tags.md) |

**Tables involved:** [`tags`](database/tables/04_tags.md) · [`user_interests`](database/tables/12_user_interests.md)

**⚠️ Notes:**
- `submit_tags` returns `resultFlag` not `status` — unique among all SPs
- `submit_tags` is **replace-all** — deletes all existing then re-inserts
- `p_tag_ids` is `bigint[]` (vs `submit_platform` which uses `int[]`)

---

## 📅 Events

| SP                   | Endpoint                     | Input                                                                                                  | Tables                                                                     | SQL                                              | Doc                                 |
| -------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------- | ------------------------------------------------ | ----------------------------------- |
| `create_event`       | POST /rpc/create_event       | p_profile_id, p_user_id, p_title, p_event_date, p_event_time, p_platforms (jsonb), recurring params... | `event_mst` ✏️ `event_platforms` ✏️ `event_recurring` ✏️                   | [SQL](../functions/events/create_event.md)       | [Doc](events/create_event.md)       |
| `get_event_list`     | POST /rpc/get_event_list     | p_date, p_device_ip                                                                                    | `event_mst` 👁️ `event_platforms` 👁️ `creator_profiles` 👁️ `follows` 👁️ | [SQL](../functions/events/get_event_list.md)     | [Doc](events/get_event_list.md)     |
| `get_profile_events` | POST /rpc/get_profile_events | p_profile_id, p_week_start                                                                             | `event_mst` 👁️ `event_platforms` 👁️ `platforms` 👁️                      | [SQL](../functions/events/get_profile_events.md) | [Doc](events/get_profile_events.md) |

**Tables involved:** [`event_mst`](database/tables/08_event_mst.md) · [`event_platforms`](database/tables/09_event_platforms.md) · [`event_recurring`](database/tables/13_event_recurring.md) · [`creator_profiles`](database/tables/05_creator_profiles.md)

**⚠️ Notes:**
- `event_platforms.platform_id` is **int4** — always cast `::bigint` when joining `platforms.plat_id`
- `create_event` writes to 3 tables atomically
- Recurring fields: `p_recurring_type` (`weekly`/`first`/`last`) + `p_recurring_interval` (1–12 for weekly)

**When to use which GET:**

| SP | Input | Returns | Use Case |
|---|---|---|---|
| `get_event_list` | date | Live + today sections (all profiles) | Global home feed |
| `get_profile_events` | profile_id + week_start | 7-day window for one profile | Profile view calendar |

---

## 👥 Follow

| SP                   | Endpoint                     | Input                   | Tables                                                               | SQL                                              | Doc                                 |
| -------------------- | ---------------------------- | ----------------------- | -------------------------------------------------------------------- | ------------------------------------------------ | ----------------------------------- |
| `follow_creator`     | POST /rpc/follow_creator     | p_user_id, p_profile_id | `follows` ✏️ `users` 👁️                                             | [SQL](../functions/follow/follow_creator.md)     | [Doc](follow/follow_creator.md)     |
| `unfollow_creator`   | POST /rpc/unfollow_creator   | p_user_id, p_profile_id | `follows` ✏️                                                         | [SQL](../functions/follow/unfollow_creator.md)   | [Doc](follow/unfollow_creator.md)   |
| `get_following_list` | POST /rpc/get_following_list | p_user_id               | `follows` 👁️ `creator_profiles` 👁️ `creator_platform_accounts` 👁️ | [SQL](../functions/follow/get_following_list.md) | [Doc](follow/get_following_list.md) |
| `get_followers_list` | POST /rpc/get_followers_list | p_profile_id            | `follows` 👁️ `users` 👁️                                            | [SQL](../functions/follow/get_followers_list.md) | [Doc](follow/get_followers_list.md) |
| `get_creators`       | GET /rpc/get_creators        | none                    | `creator_profiles` 👁️ `creator_platform_accounts` 👁️ `follows` 👁️ | [SQL](../functions/follow/get_creators.md)       | [Doc](follow/get_creators.md)       |

**Tables involved:** [`follows`](database/tables/10_follows.md) · [`users`](database/tables/02_users.md) · [`creator_profiles`](database/tables/05_creator_profiles.md) · [`creator_platform_accounts`](database/tables/06_creator_platform_accounts.md)

**⚠️ Notes:**
- `follows` uses **soft delete** — unfollow sets `is_active=false`, re-follow updates existing row
- `follow_creator` has a bug: `p_device_ip` is referenced in body but **not in function signature**
- `get_creators` followers count has **no `is_active` filter** — counts all rows
- `get_creators` platforms returns **string array** not objects

---

## 🔍 Search

| SP | Endpoint | Input | Tables | SQL | Doc |
|---|---|---|---|---|---|
| `search_profiles` | POST /rpc/search_profiles | p_keyword, p_limit (default 20) | `creator_profiles` 👁️ `creator_platform_accounts` 👁️ `follows` 👁️ | [SQL](../functions/search/search_profiles.md) | [Doc](search/search_profiles.md) |
| `search_events` | POST /rpc/search_events | p_keyword, p_limit (default 20) | `event_mst` 👁️ `event_platforms` 👁️ `creator_profiles` 👁️ | [SQL](../functions/search/search_events.md) | [Doc](search/search_events.md) |

**Tables involved:** [`creator_profiles`](database/tables/05_creator_profiles.md) · [`event_mst`](database/tables/08_event_mst.md) · [`event_platforms`](database/tables/09_event_platforms.md)

**⚠️ Notes:**
- Both require `pg_trgm` extension — `word_similarity()` threshold > 0.3
- `search_profiles` searches: profile_name, username, bio
- `search_events` searches: title, description (`coalesce(description, '')` for null safety)
- Min keyword length: 2 characters

---

## Table Index

Every table with the SPs that read (👁️) or write (✏️) it.

| Table                       | Doc                                                    | Schema                                                     | SPs                                                                                                                                                                                                                                                                                                                                |
| --------------------------- | ------------------------------------------------------ | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `roles`                     | [Doc](database/tables/01_roles.md)                     | [Schema](../schema/tables/01_roles.md)                     | `is_creator` ✏️ · `create_profile` 👁️                                                                                                                                                                                                                                                                                             |
| `users`                     | [Doc](database/tables/02_users.md)                     | [Schema](../schema/tables/02_users.md)                     | `register` ✏️ · `signup` ✏️ · `login` 👁️ · `is_creator` ✏️ · `create_profile` 👁️ · `get_profile_by_userid` 👁️ · `submit_platform` 👁️ · `submit_tags` 👁️ · `follow_creator` 👁️ · `get_followers_list` 👁️                                                                                                                     |
| `platforms`                 | [Doc](database/tables/03_platforms.md)                 | [Schema](../schema/tables/03_platforms.md)                 | `get_all_platforms` 👁️ · `create_profile` 👁️ · `update_profile` 👁️ · `submit_platform` 👁️ · `get_event_list` 👁️ · `get_profile_events` 👁️ · `search_events` 👁️ · `get_creators` 👁️ · `get_following_list` 👁️                                                                                                              |
| `tags`                      | [Doc](database/tables/04_tags.md)                      | [Schema](../schema/tables/04_tags.md)                      | `get_all_tags` 👁️ · `create_profile` 👁️ · `update_profile` 👁️ · `submit_tags` 👁️                                                                                                                                                                                                                                               |
| `creator_profiles`          | [Doc](database/tables/05_creator_profiles.md)          | [Schema](../schema/tables/05_creator_profiles.md)          | `create_profile` ✏️ · `update_profile` ✏️ · `get_user_profiles` 👁️ · `get_profile_by_id` 👁️ · `get_profile_by_username` 👁️ · `get_profile_by_userid` 👁️ · `get_creators` 👁️ · `follow_creator` 👁️ · `get_following_list` 👁️ · `get_event_list` 👁️ · `get_profile_events` 👁️ · `search_profiles` 👁️ · `search_events` 👁️ |
| `creator_platform_accounts` | [Doc](database/tables/06_creator_platform_accounts.md) | [Schema](../schema/tables/06_creator_platform_accounts.md) | `create_profile` ✏️ · `update_profile` ✏️ · `get_profile_by_id` 👁️ · `get_profile_by_username` 👁️ · `get_profile_by_userid` 👁️ · `get_creators` 👁️ · `get_following_list` 👁️ · `search_profiles` 👁️                                                                                                                          |
| `profile_tags`              | [Doc](database/tables/07_profile_tags.md)              | [Schema](../schema/tables/07_profile_tags.md)              | `create_profile` ✏️ · `update_profile` ✏️ · `get_profile_by_id` 👁️ · `get_profile_by_username` 👁️ · `get_profile_by_userid` 👁️                                                                                                                                                                                                  |
| `event_mst`                 | [Doc](database/tables/08_event_mst.md)                 | [Schema](../schema/tables/08_event_mst.md)                 | `create_event` ✏️ · `get_event_list` 👁️ · `get_profile_events` 👁️ · `search_events` 👁️                                                                                                                                                                                                                                          |
| `event_platforms`           | [Doc](database/tables/09_event_platforms.md)           | [Schema](../schema/tables/09_event_platforms.md)           | `create_event` ✏️ · `get_event_list` 👁️ · `get_profile_events` 👁️ · `search_events` 👁️                                                                                                                                                                                                                                          |
| `follows`                   | [Doc](database/tables/10_follows.md)                   | [Schema](../schema/tables/10_follows.md)                   | `follow_creator` ✏️ · `unfollow_creator` ✏️ · `get_following_list` 👁️ · `get_followers_list` 👁️ · `get_creators` 👁️ · `get_profile_by_id` 👁️ · `get_profile_by_username` 👁️ · `get_profile_by_userid` 👁️ · `get_event_list` 👁️                                                                                              |
| `user_preferred_platforms`  | [Doc](database/tables/11_user_preferred_platforms.md)  | [Schema](../schema/tables/11_user_preferred_platforms.md)  | `submit_platform` ✏️                                                                                                                                                                                                                                                                                                               |
| `user_interests`            | [Doc](database/tables/12_user_interests.md)            | [Schema](../schema/tables/12_user_interests.md)            | `submit_tags` ✏️                                                                                                                                                                                                                                                                                                                   |
| `event_recurring`           | [Doc](database/tables/13_event_recurring.md)           | [Schema](../schema/tables/13_event_recurring.md)           | `create_event` ✏️                                                                                                                                                                                                                                                                                                                  |

---

## File Map

```
functions/                          docs/api/
├── auth/                           ├── auth/
│   ├── register.md ──────────────► │   ├── register.md
│   ├── signup.md ────────────────► │   ├── signup.md
│   └── login.md ─────────────────► │   └── login.md
├── profiles/                       ├── profiles/
│   ├── creator_enable.md ────────► │   ├── creator_enable.md
│   ├── create_profile.md ────────► │   ├── create_profile.md
│   ├── update_profile.md ────────► │   ├── update_profile.md
│   ├── get_user_profiles.md ─────► │   ├── get_user_profiles.md
│   ├── get_profile_by_id.md ─────► │   ├── get_profile_by_id.md
│   ├── get_profile_by_username.md► │   ├── get_profile_by_username.md
│   └── get_profile_by_userid.md ─► │   └── get_profile_by_userid.md
├── platforms/                      ├── platforms/
│   ├── get_all_platforms.md ─────► │   ├── get_all_platforms.md
│   └── submit_platform.md ───────► │   └── submit_platform.md
├── tags/                           ├── tags/
│   ├── get_all_tags.md ──────────► │   ├── get_all_tags.md
│   └── submit_tags.md ───────────► │   └── submit_tags.md
├── events/                         ├── events/
│   ├── create_event.md ──────────► │   ├── create_event.md
│   ├── get_event_list.md ────────► │   ├── get_event_list.md
│   └── get_profile_events.md ───► │   └── get_profile_events.md
├── follow/                         ├── follow/
│   ├── follow_creator.md ────────► │   ├── follow_creator.md
│   ├── unfollow_creator.md ──────► │   ├── unfollow_creator.md
│   ├── get_following_list.md ───► │   ├── get_following_list.md
│   ├── get_followers_list.md ───► │   ├── get_followers_list.md
│   └── get_creators.md ──────────► │   └── get_creators.md
└── search/                         └── search/
    ├── search_profiles.md ───────►     ├── search_profiles.md
    └── search_events.md ─────────►     └── search_events.md

schema/
├── tables/          01_roles · 02_users · 03_platforms · 04_tags
│                    05_creator_profiles · 06_creator_platform_accounts
│                    07_profile_tags · 08_event_mst · 09_event_platforms
│                    10_follows · 11_user_preferred_platforms
│                    12_user_interests · 13_event_recurring
├── extensions/      pg_trgm        (required for search SPs)
├── indexes/         trigram_indexes
└── seed/            roles · platforms · tags

docs/database/tables/    mirror of schema/ — human-readable table docs
updates/log.md           append-only change history
CONTEXT.md               full AI-readable project context
README.md                project overview
docs/API_INDEX.md        ← this file
```

---

## Legend

| Symbol | Meaning |
|---|---|
| ✏️ | SP writes to this table (INSERT / UPDATE / DELETE) |
| 👁️ | SP reads from this table (SELECT) |

---

*Last updated: 2026-04-10 — 24 SPs · 13 tables*
