# API Reference — All Stored Procedures

**Total APIs:** 20 completed · 7 pending
**Base URL:** `https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc`
**Auth:** `apiKey` header + `Authorization: Bearer {{token}}`

---

## Standard Response Format

```json
{ "status": true,  "message": "...", "data": {} }
{ "status": false, "message": "...", "error": "..." }
```

---

## Complete API Table

| # | SP Name | Endpoint | Method | Group | Status |
|---|---------|----------|--------|-------|--------|
| 1 | [register](./auth/register.md) | /rpc/register | POST | Auth | ✅ |
| 2 | [signup](./auth/signup.md) | /rpc/signup | POST | Auth | ✅ |
| 3 | [login](./auth/login.md) | /rpc/login | POST | Auth | ✅ |
| 4 | [get_all_platforms](./platforms/get_all_platforms.md) | /rpc/get_all_platforms | GET | Platform | ✅ |
| 5 | [submit_platform](./platforms/submit_platform.md) | /rpc/submit_platform | POST | Platform | ✅ |
| 6 | [get_all_tags](./tags/get_all_tags.md) | /rpc/get_all_tags | GET | Tags | ✅ |
| 7 | [submit_tags](./tags/submit_tags.md) | /rpc/submit_tags | POST | Tags | ✅ |
| 8 | [creator_enable](./profiles/creator_enable.md) | /rpc/creator_enable | POST | Profile | ✅ |
| 9 | [create_profile](./profiles/create_profile.md) | /rpc/create_profile | POST | Profile | ✅ |
| 10 | [update_profile](./profiles/update_profile.md) | /rpc/update_profile | POST | Profile | ✅ |
| 11 | [get_profiles_by_username](./profiles/get_profiles_by_username.md) | /rpc/get_profiles_by_username | POST | Profile | ✅ |
| 12 | [get_single_profile_by_username](./profiles/get_single_profile_by_username.md) | /rpc/get_single_profile_by_username | POST | Profile | ✅ |
| 13 | [get_creators](./follow/get_creators.md) | /rpc/get_creators | GET | Follow | ✅ |
| 14 | [follow_creator](./follow/follow_creator.md) | /rpc/follow_creator | POST | Follow | ✅ |
| 15 | [unfollow_creator](./follow/unfollow_creator.md) | /rpc/unfollow_creator | POST | Follow | ✅ |
| 16 | [get_following_list](./follow/get_following_list.md) | /rpc/get_following_list | POST | Follow | ✅ |
| 17 | [get_followers_list](./follow/get_followers_list.md) | /rpc/get_followers_list | POST | Follow | ✅ |
| 18 | [get_event_list](./events/get_event_list.md) | /rpc/get_event_list | POST | Events | ✅ |
| 19 | [search_profiles](./search/search_profiles.md) | /rpc/search_profiles | POST | Search | ✅ |
| 20 | [search_events](./search/search_events.md) | /rpc/search_events | POST | Search | ✅ |

---

## Pending APIs

| Group | API | Notes |
|-------|-----|-------|
| Events | create_event | POST /rpc/create_event |
| Events | update_event | POST /rpc/update_event |
| Events | delete_event | POST /rpc/delete_event |
| Events | get_event_by_id | POST /rpc/get_event_by_id |
| Notifications | send_notification | TBD |
| Notifications | get_notifications | TBD |
| Settings | update_settings | TBD |
