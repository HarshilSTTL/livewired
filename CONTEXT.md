# LiveWired — Full Project Context (AI Reference)

> This file is the primary context document for AI assistants.
> Read this first to understand the entire project before making any changes.
> For detailed docs, navigate to `docs/`. For SQL, navigate to `schema/` and `functions/`.

---

## Project Identity

| Field | Value |
|-------|-------|
| Project Name | LiveWired |
| Platform | Supabase (PostgreSQL) + Flutter |
| API Style | PostgreSQL Stored Procedures via Supabase RPC |
| Base URL | `https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc` |
| Auth | `apiKey` header + `Authorization: Bearer {{token}}` |
| Response Format | `{ "status": bool, "message": "...", "data": {} }` |

---

## Project Description

LiveWired is a creator-discovery and live-stream scheduling platform. Creators announce their upcoming live streams across multiple platforms (YouTube, Twitch, Kick, Rumble) in one place. Users follow creators and see who is live or scheduled to go live.

**There is no traditional backend server.** All business logic lives inside PostgreSQL stored procedures called via Supabase's `/rpc/` endpoint. Each stored procedure IS the API.

---

## User Roles

| role_id | Role | Capabilities |
|---------|------|-------------|
| 1 | User | Follow creators, view events, get notified |
| 2 | Creator | All user capabilities + create profiles, schedule events |
| 3 | Admin | Platform administration |

---

## Database: 13 Tables

| # | Table | Purpose |
|---|-------|---------|
| 1 | `roles` | 3 user roles |
| 2 | `users` | Core auth + user accounts |
| 3 | `platforms` | Supported streaming platforms (YouTube, Twitch, Kick, Rumble) |
| 4 | `tags` | Interest/category tags (13 tags) |
| 5 | `creator_profiles` | Public creator profiles (user can have multiple) |
| 6 | `creator_platform_accounts` | Links creator profile to their platform channel |
| 7 | `profile_tags` | Junction: creator profile ↔ interest tags |
| 8 | `event_mst` | Master event records |
| 9 | `event_platforms` | Links event to platform(s) with stream URLs |
| 10 | `follows` | User → Creator follow relationships (soft delete) |
| 11 | `user_preferred_platforms` | User's platform preferences (onboarding) |
| 12 | `user_interests` | User's interest tags (onboarding) |
| 13 | `event_collaborators` | Collaboration invites for events (pending/accepted/declined, soft delete) |

Full table schemas → `docs/database/tables/`
SQL CREATE statements → `schema/tables/`

---

## APIs: 27 Stored Procedures

| # | Function | Endpoint | Method | Group |
|---|----------|----------|--------|-------|
| 1 | register | /rpc/register | POST | Auth |
| 2 | signup | /rpc/signup | POST | Auth |
| 3 | login | /rpc/login | POST | Auth |
| 4 | get_all_platforms | /rpc/get_all_platforms | GET | Platform |
| 5 | submit_platform | /rpc/submit_platform | POST | Platform |
| 6 | get_all_tags | /rpc/get_all_tags | GET | Tags |
| 7 | submit_tags | /rpc/submit_tags | POST | Tags |
| 8 | creator_enable | /rpc/creator_enable | POST | Profile |
| 9 | create_profile | /rpc/create_profile | POST | Profile |
| 10 | update_profile | /rpc/update_profile | POST | Profile |
| 11 | get_profiles_by_username | /rpc/get_profiles_by_username | POST | Profile |
| 12 | get_single_profile_by_username | /rpc/get_single_profile_by_username | POST | Profile |
| 13 | get_creators | /rpc/get_creators | GET | Follow |
| 14 | follow_creator | /rpc/follow_creator | POST | Follow |
| 15 | unfollow_creator | /rpc/unfollow_creator | POST | Follow |
| 16 | get_following_list | /rpc/get_following_list | POST | Follow |
| 17 | get_followers_list | /rpc/get_followers_list | POST | Follow |
| 18 | get_event_list | /rpc/get_event_list | POST | Events |
| 19 | search_profiles | /rpc/search_profiles | POST | Search |
| 20 | search_events | /rpc/search_events | POST | Search |
| 25 | search_collaborator_profiles | /rpc/search_collaborator_profiles | POST | Search |
| 21 | invite_collaborator | /rpc/invite_collaborator | POST | Events |
| 22 | respond_collaborator_invite | /rpc/respond_collaborator_invite | POST | Events |
| 23 | remove_collaborator | /rpc/remove_collaborator | POST | Events |
| 24 | notify_expiring_recurring_events | /rpc/notify_expiring_recurring_events | POST | Events |
| 26 | get_unread_notification_count | /rpc/get_unread_notification_count | POST | Notifications |
| 27 | mark_notifications_read | /rpc/mark_notifications_read | POST | Notifications |

Full API docs → `docs/api/`
SQL function code → `functions/`

---

## Standard Response Format

```json
{ "status": true,  "message": "...", "data": {} }
{ "status": false, "message": "...", "error": "..." }
```

---

## Key Technical Notes

1. All APIs use Supabase RPC — `POST /rpc/<function_name>` or `GET /rpc/<function_name>`
2. `event_platforms.platform_id` is `integer` — must cast to `bigint` when joining `platforms.plat_id`
3. Search requires `pg_trgm` extension — see `schema/extensions/pg_trgm.md`
4. Follower count is always calculated live via `COUNT(*) WHERE is_active = true`
5. Unfollowing is soft delete — row kept with `is_active = false`
6. Only `role_id = 2` users can create creator profiles
7. One user can have multiple creator profiles — each is independent
8. Only one profile can be `is_default = true` per user at a time

---

## Onboarding Flow

```
Register → Login → Select Platforms → Select Tags → Follow Creators → (Is Creator?) → Create Profile
```

---

## Pending Work

| Group | API | Status |
|-------|-----|--------|
| Events | Create Event | ⏳ Pending |
| Events | Update Event | ⏳ Pending |
| Events | Delete Event | ⏳ Pending |
| Events | Get Event by ID | ⏳ Pending |
| Notifications | Send Notification | ⏳ Pending |
| Notifications | Get Notifications | ⏳ Pending |
| Settings | Update Settings | ⏳ Pending |

---

## Navigation Guide

| What you need | Where to look |
|---------------|---------------|
| Table column definitions | `docs/database/tables/` |
| SQL CREATE TABLE | `schema/tables/` |
| API parameters + response | `docs/api/<group>/<sp_name>.md` |
| SQL stored procedure code | `functions/<group>/<sp_name>.md` |
| Business rules | `docs/business-rules.md` |
| Change history | `updates/log.md` |
| Seed data SQL | `schema/seed/` |
