# Table: `event_mst`

> Master event records. A creator schedules a live event from one of their profiles.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| event_id | uuid | gen_random_uuid() | No | PRIMARY KEY | Event ID |
| profile_id | uuid | NULL | Yes | FK → creator_profiles.id | Which creator profile owns this event |
| title | text | NULL | Yes | — | Event title |
| description | text | NULL | **Yes** | — | Event description (nullable) |
| event_link | text | NULL | Yes | — | Primary stream link |
| event_date | date | NULL | Yes | — | Date of the event |
| event_time | time | NULL | Yes | — | Time of the event |
| livestream | bool | false | No | — | Is this a live stream? |
| video | bool | false | No | — | Is this a video premiere? |
| is_recurring | bool | false | No | — | Is this a repeating event? |
| created_at | timestamptz | now() | Yes | — | Record creation time |
| updated_at | timestamptz | now() | **Yes** | — | Last update time (nullable) |

## Foreign Keys

| Constraint | Column | References | On Delete |
|-----------|--------|-----------|-----------|
| event_mst_profile_id_fkey | profile_id | `public.creator_profiles.id` | CASCADE |

## Business Rules

- Events belong to a creator **profile**, not directly to a user
- `description` and `updated_at` are nullable
- `livestream = true` → used for live section logic in `get_event_list`
- `video = true` → video premiere (not a live stream)
- `is_recurring = true` → repeating event
- One event can stream on multiple platforms via `event_platforms` table
- **Live section rule:** `livestream = true` AND `event_time <= current_time` AND `event_time >= (current_time - 3 hours)`
- **Terminated:** Started more than 3 hours ago → hidden from both live and today sections

## Referenced By (Stored Procedures & Tables)

| SP / Table | How |
|------------|-----|
| `get_event_list` | SELECT with date-based branching logic |
| `search_events` | Full-text + fuzzy search on title, description |
| `event_platforms` | FK via event_id |

## SQL Reference

See [`schema/tables/08_event_mst.sql`](../../../schema/tables/08_event_mst.sql)
