# Table: `event_mst`

> Master event records. A creator schedules a live event from one of their profiles.

## Columns

| Column           | Type        | Default           | Nullable | Constraints                    | Notes                                                                  |
|------------------|-------------|-------------------|----------|--------------------------------|------------------------------------------------------------------------|
| event_id         | uuid        | gen_random_uuid() | No       | PRIMARY KEY                    | Event ID                                                               |
| profile_id       | uuid        | NULL              | Yes      | FK → creator_profiles.id       | Which creator profile owns this event                                  |
| parent_event_id  | uuid        | NULL              | **Yes**  | FK → event_mst.event_id        | If set, this row is a generated occurrence of a recurring series       |
| title            | text        | NULL              | Yes      | —                              | Event title                                                            |
| description      | text        | NULL              | **Yes**  | —                              | Event description (nullable)                                           |
| event_date       | date        | NULL              | Yes      | —                              | Date of the event in UTC (or occurrence date for child rows)           |
| event_time       | time        | NULL              | Yes      | —                              | Time of the event (stored as UTC)                                      |
| event_timezone   | text        | `'UTC'`           | No       | —                              | Creator's IANA timezone at time of creation (e.g. `'America/New_York'`) |
| livestream       | bool        | false             | No       | —                              | Is this a live stream?                                                 |
| video            | bool        | false             | No       | —                              | Is this a video premiere?                                              |
| is_recurring     | bool        | false             | No       | —                              | Is this a repeating event?                                             |
| created_at       | timestamptz | now()             | Yes      | —                              | Record creation time                                                   |
| updated_at       | timestamptz | now()             | **Yes**  | —                              | Last update time (nullable)                                            |
| is_deleted       | bool        | false             | No       | —                              | Soft delete flag — `true` = event is deleted                           |
| deleted_at       | timestamptz | NULL              | **Yes**  | —                              | Timestamp when event was soft deleted                                  |

## Foreign Keys

| Constraint                      | Column          | References                    | On Delete |
|---------------------------------|-----------------|-------------------------------|-----------|
| event_mst_profile_id_fkey       | profile_id      | `public.creator_profiles.id`  | CASCADE   |
| event_mst_parent_event_id_fkey  | parent_event_id | `public.event_mst.event_id`   | CASCADE   |

## Recurring Event Row Model

When `create_event` is called with `p_is_recurring = true`, it inserts:

| Row type | `parent_event_id` | `is_recurring` | `event_date` | `event_platforms` |
|---|---|---|---|---|
| **Parent / template** | `NULL` | `true` | The `p_event_date` passed in | ✅ Stored here |
| **Child occurrences** | `<parent event_id>` | `true` | Each computed occurrence date | ❌ Inherited from parent |

- The **parent row** stores the event definition (title, description, time, platforms).
- **Child rows** are generated automatically for every matching date between `recurring_start_date` and `recurring_end_date`.
- Deleting the parent cascades to all children via `ON DELETE CASCADE`.
- `event_platforms` is stored **only on the parent**. When fetching events, platforms are looked up via `COALESCE(child.parent_event_id, event_id)`.

### Example — weekly / every Monday / 3 weeks

| event_id | parent_event_id | event_date   | Notes         |
|----------|-----------------|--------------|---------------|
| `uuid-A` | NULL            | 2026-03-30   | Parent row    |
| `uuid-B` | `uuid-A`        | 2026-03-30   | Week 1        |
| `uuid-C` | `uuid-A`        | 2026-04-06   | Week 2        |
| `uuid-D` | `uuid-A`        | 2026-04-13   | Week 3        |

> `get_profile_events` filters out the parent row by requiring
> `is_recurring = false OR parent_event_id IS NOT NULL`

## Business Rules

- Events belong to a creator **profile**, not directly to a user
- `description` and `updated_at` are nullable
- `parent_event_id` is only set on generated occurrence rows; the parent itself has `parent_event_id = NULL`
- `is_recurring = true` on both the parent template and all child occurrence rows
- `livestream = true` → used for live section logic in `get_event_list`
- `video = true` → video premiere (not a live stream)
- One event can stream on multiple platforms via `event_platforms` table
- `event_date` and `event_time` are stored in **UTC**. Creator's local timezone is stored in `event_timezone`.
- Read SPs accept `p_timezone` (viewer's IANA timezone) and convert UTC → viewer's local date/time before returning.
- **Live section rule:** `livestream = true` AND `event UTC time <= NOW()` AND `event UTC time >= NOW() - 3 hours`
- **Terminated:** Started more than 3 hours ago → hidden from both live and today sections

## Referenced By (Stored Procedures & Tables)

| SP / Table | How |
|------------|-----|
| `create_event` | INSERT (parent + child occurrences) |
| `get_event_list` | SELECT with date-based branching logic |
| `get_profile_events` | SELECT — filters `is_recurring = false OR parent_event_id IS NOT NULL` |
| `search_events` | Full-text + fuzzy search on title, description |
| `event_platforms` | FK via event_id |
| `event_recurring` | FK via event_id (stores recurrence rule for parent) |

## SQL Reference

See [`schema/tables/08_event_mst.md`](../../../schema/tables/08_event_mst.md)
