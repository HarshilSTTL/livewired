# LiveWired — Project Documentation

**Tech Stack:** Flutter (Frontend) · Supabase (Backend · PostgreSQL)
**Architecture:** PostgreSQL Stored Procedures (RPC) as APIs
**Base URL:** `https://vzieacbdhrandechlljw.supabase.co/rest/v1/rpc`
**Auth:** `apiKey` header + `Authorization: Bearer {{token}}`

---

## What is LiveWired?

LiveWired is a platform where creators announce when and where they will go live across multiple streaming platforms (YouTube, Twitch, Kick, Rumble). Users can follow creators, get notified of upcoming streams, and see who is currently live — all in one place.

---

## Repository Purpose

This repository serves as the **single source of truth** for the LiveWired backend architecture. Since the project uses Supabase with PostgreSQL stored procedures as APIs (no traditional backend server), this repo documents:

- All 12 database tables (schema + relationships)
- All 20 stored procedures (SQL functions acting as APIs)
- API request/response contracts
- Business rules and data flow
- Version history of all changes

> **For AI Assistants:** Start with [`CONTEXT.md`](./CONTEXT.md) for a full project overview, then navigate to `docs/` for detailed documentation.

> **For Team Members:** Check [`updates/log.md`](./updates/log.md) for the latest changes and progress.

---

## Folder Structure

```
livewired/
├── README.md                        ← You are here
├── CONTEXT.md                       ← Full AI-readable project context
│
├── docs/
│   ├── README.md                    ← Documentation index
│   ├── business-rules.md            ← All business logic & rules
│   ├── database/
│   │   ├── README.md                ← Table overview + relationship map
│   │   └── tables/                  ← 12 individual table docs
│   └── api/
│       ├── README.md                ← Full API reference (all 20 SPs)
│       ├── auth/                    ← register, signup, login
│       ├── platforms/               ← get_all_platforms, submit_platform
│       ├── tags/                    ← get_all_tags, submit_tags
│       ├── profiles/                ← creator_enable, create/update/get_profile
│       ├── follow/                  ← get_creators, follow/unfollow, get lists
│       ├── events/                  ← get_event_list
│       └── search/                  ← search_profiles, search_events
│
├── schema/
│   ├── tables/                      ← 12 CREATE TABLE SQL files
│   ├── extensions/                  ← pg_trgm and other extensions
│   ├── indexes/                     ← Trigram and performance indexes
│   └── seed/                        ← Seed data for roles, platforms, tags
│
├── functions/
│   ├── auth/                        ← 3 auth stored procedures
│   ├── platforms/                   ← 2 platform stored procedures
│   ├── tags/                        ← 2 tag stored procedures
│   ├── profiles/                    ← 5 profile stored procedures
│   ├── follow/                      ← 5 follow stored procedures
│   ├── events/                      ← 1 event stored procedure
│   └── search/                      ← 2 search stored procedures
│
└── updates/
    └── log.md                       ← Chronological change log
```

---

## Quick Stats

| Category | Count |
|----------|-------|
| Database Tables | 12 |
| Stored Procedures (APIs) | 20 |
| Completed APIs | 20 |
| Pending APIs | 7 |
| User Roles | 3 (User, Creator, Admin) |
| Supported Platforms | 4 (YouTube, Twitch, Kick, Rumble) |

---

## API Groups

| Group | APIs | Status |
|-------|------|--------|
| Auth | register, signup, login | ✅ Done |
| Platform | get_all_platforms, submit_platform | ✅ Done |
| Tags | get_all_tags, submit_tags | ✅ Done |
| Profile | creator_enable, create_profile, update_profile, get_profiles_by_username, get_single_profile_by_username | ✅ Done |
| Follow | get_creators, follow_creator, unfollow_creator, get_following_list, get_followers_list | ✅ Done |
| Events | get_event_list | ✅ Done |
| Search | search_profiles, search_events | ✅ Done |
| Events (CRUD) | create, update, delete, get by ID | ⏳ Pending |
| Notifications | send, get | ⏳ Pending |
| Settings | update | ⏳ Pending |
