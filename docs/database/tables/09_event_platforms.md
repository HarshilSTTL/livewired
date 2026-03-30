# Table: `event_platforms`

> Links an event to one or more streaming platforms with their stream URLs. One event can stream on multiple platforms.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Record ID |
| event_id | uuid | NULL | Yes | FK → event_mst.event_id | Which event |
| platform_id | int4 | NULL | Yes | FK → platforms.plat_id | Which platform (**int4**, not int8) |
| stream_url | text | NULL | Yes | — | Direct stream URL for this platform |
| created_at | timestamp | now() | **Yes** | — | Record creation time (nullable, `timestamp` not `timestamptz`) |

## Foreign Keys

| Constraint | Column | References | On Delete |
|-----------|--------|-----------|-----------|
| fk_event | event_id | `public.event_mst.event_id` | CASCADE |
| fk_platform | platform_id | `public.platforms.plat_id` | — |

## ⚠️ Critical Type Note

`platform_id` is **`int4`** (integer), while `platforms.plat_id` is **`int8`** (bigint).

**Always cast when joining:**
```sql
LEFT JOIN platforms p ON p.plat_id = ep.platform_id::bigint
```
This cast is used in `get_event_list`, `search_events`, `search_profiles`, `get_creators`, and `get_following_list`.

## ⚠️ Timestamp Type Note

`created_at` is **`timestamp`** (without timezone), not `timestamptz`. This differs from other tables.

## Business Rules

- One event can have multiple rows here (one per platform)
- `stream_url` is the direct link to the stream on that specific platform
- `created_at` is nullable
- Platform join requires explicit `::bigint` cast due to int4/int8 mismatch

## Referenced By (Stored Procedures)

| SP | How |
|----|-----|
| `get_event_list` | Subquery JOIN to get streaming platforms per event |
| `search_events` | Subquery JOIN to get streaming platforms per event |

## SQL Reference

See [`schema/tables/09_event_platforms.sql`](../../../schema/tables/09_event_platforms.sql)
