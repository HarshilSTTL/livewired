# Table: `event_recurring`

> Stores recurring schedule details for events. One row per recurring event (1:1 with `event_mst`
> where `is_recurring = true`). The `event_mst` table keeps `is_recurring bool` as the flag;
> this table holds the actual schedule data.

## Columns

| Column | Type | Default | Nullable | Constraints | Notes |
|--------|------|---------|----------|-------------|-------|
| id | uuid | gen_random_uuid() | No | PRIMARY KEY | Record ID |
| event_id | uuid | — | No | FK → event_mst.event_id ON DELETE CASCADE | Linked event |
| recurring_days | text[] | — | No | — | Days the event recurs. e.g. `{Mon,Tue,Wed}` |
| recurring_type | text | — | No | — | `'weekly'` · `'first'` · `'last'` |
| recurring_interval | int | NULL | **Yes** | — | 1–12 (weeks). Only for `recurring_type = 'weekly'`. NULL for first/last |
| recurring_start_date | date | — | No | — | When the recurring schedule begins |
| recurring_end_date | date | NULL | **Yes** | — | When recurring ends. Always populated — defaults to `recurring_start_date + 3 months` if not provided |
| renewal_notified_at | timestamptz | NULL | **Yes** | — | Timestamp when the renewal reminder notification was sent. NULL = not yet sent |
| created_at | timestamptz | now() | No | — | Record creation time |

## Foreign Keys

| Constraint | Column | References | On Delete |
|-----------|--------|-----------|-----------|
| event_recurring_event_id_fkey | event_id | `public.event_mst.event_id` | CASCADE |

## `recurring_type` Values

| Value | Meaning | `recurring_interval` |
|-------|---------|---------------------|
| `'weekly'` | Repeats every N weeks on selected days | Required (1–12) |
| `'first'` | First occurrence of selected days in each month | Must be NULL |
| `'last'` | Last occurrence of selected days in each month | Must be NULL |

## `recurring_days` Valid Values

Array of day abbreviations — any non-empty subset of:
`Mon` · `Tue` · `Wed` · `Thu` · `Fri` · `Sat` · `Sun`

## How the UI Maps to DB

| UI (Repeats dropdown) | `recurring_type` | `recurring_interval` |
|---|---|---|
| Every week | `weekly` | `1` |
| Every 2nd week | `weekly` | `2` |
| Every 3rd week | `weekly` | `3` |
| Every 4th week | `weekly` | `4` |
| Custom (slider 1–12) | `weekly` | `1`–`12` |
| First | `first` | `NULL` |
| Last | `last` | `NULL` |

## Business Rules

- This table only has a row if `event_mst.is_recurring = true`
- Exactly **one** `event_recurring` row per recurring event
- `recurring_days` must have at least one valid day abbreviation
- `recurring_interval` is required when `recurring_type = 'weekly'`; must be NULL for `'first'` / `'last'`
- `recurring_end_date`, if provided, must be after `recurring_start_date`. If not provided, `create_event` stores `recurring_start_date + 3 months` as the default — this value is always written so the notification SP can query it
- `renewal_notified_at` is set by `notify_expiring_recurring_events` when a renewal reminder is sent. Once set, the SP will not send a second notification for the same event
- Deleting the parent event automatically deletes this row (ON DELETE CASCADE)
- Validation is enforced by the `create_event` SP, not DB constraints

## Referenced By (Stored Procedures)

| SP | How |
|----|-----|
| `create_event` | INSERT when `p_is_recurring = true` |
| `update_event` | UPDATE recurring rule + regenerate child rows |
| `notify_expiring_recurring_events` | Reads `recurring_end_date` + writes `renewal_notified_at` |

## SQL Reference

See [`schema/tables/13_event_recurring.md`](../../../schema/tables/13_event_recurring.md)
