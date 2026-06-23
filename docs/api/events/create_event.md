# SP: `create_event`

## Versions

| Version | Function | Endpoint | Status |
|---------|----------|----------|--------|
| v2.0 | `create_event_v2` | `POST /rpc/create_event_v2` | ✅ Current |
| v1.0 | `create_event` | `POST /rpc/create_event` | ❌ Deprecated |

> **Use `create_event_v2`** — v1 is deprecated. Only difference is default end time behavior (see below).

**Group:** Events
**SQL:** [`functions/events/create_event.md`](../../../functions/events/create_event.md)
**Tables written:** `event_mst` (INSERT) · `event_platforms` (INSERT) · `event_recurring` (INSERT if recurring) · `event_collaborators` (INSERT if collaborative) · `notifications` (INSERT if collaborative)

---

## Overview

Creates a new event for a creator profile and optionally links it to streaming platforms.

For **recurring events**, the SP automatically pre-generates individual rows in `event_mst`
for every matching date between `recurring_start_date` and `recurring_end_date`. This means
querying events for any specific date will find them directly — no runtime expansion required.

---

## v2.0 vs v1.0 — Default End Time

| | v2.0 (`create_event_v2`) | v1.0 (`create_event`) |
|---|---|---|
| `p_event_end_time` omitted | Defaults to `p_event_time + 2 hours` | Stored as `NULL` |
| `p_event_end_time` provided | Used as-is | Used as-is |
| Cross-midnight wrap (e.g. 23:00 → 01:00) | ✅ Handled | ✅ Handled |

---

## Recurring Event Pre-generation

When `p_is_recurring = true`, `create_event_v2` inserts:

| What | `parent_event_id` | Purpose |
|---|---|---|
| **1 parent row** in `event_mst` | `NULL` | Stores the event definition (title, time, type) |
| **1 row** in `event_recurring` | — | Stores the recurrence rule (days, type, interval, dates) |
| **1 row** in `event_platforms` per platform | — | Stored on parent; all children inherit |
| **N child rows** in `event_mst` | `<parent event_id>` | One row per computed occurrence date |

Each child row has the correct `event_date` for its occurrence. `get_profile_events` returns
child rows directly by date — no calculation at query time.

If `p_recurring_end_date` is not provided, occurrences are generated **up to 3 months** from `p_recurring_start_date`. The computed end date is always stored in `event_recurring` — 7 days before that date, `notify_expiring_recurring_events` (run daily via pg_cron) sends a renewal reminder to the owner.

### Occurrence date generation algorithm

| `recurring_type` | How occurrence dates are computed |
|---|---|
| `weekly` | For each day in `recurring_days`: find first occurrence of that weekday on/after `start_date`, then step +7×interval days until `end_date` |
| `first` | For each day in `recurring_days`: find the first occurrence of that weekday in each calendar month from `start_date` to `end_date` |
| `last` | For each day in `recurring_days`: find the last occurrence of that weekday in each calendar month |

### Example — weekly / Mon+Wed / every 2 weeks / Apr–May 2026

`p_recurring_days=["Mon","Wed"]`, `p_recurring_type="weekly"`, `p_recurring_interval=2`, `p_recurring_start_date=2026-04-06`

Rows inserted into `event_mst`:

| Row | `parent_event_id` | `event_date` |
|---|---|---|
| Parent | NULL | 2026-04-06 (p_event_date) |
| Child 1 | parent id | 2026-04-06 (Mon) |
| Child 2 | parent id | 2026-04-08 (Wed) |
| Child 3 | parent id | 2026-04-20 (Mon — skip week) |
| Child 4 | parent id | 2026-04-22 (Wed — skip week) |
| Child 5 | parent id | 2026-05-04 (Mon) |
| ... | parent id | ... |

---

## Parameters

### Core (always required/optional)

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `p_profile_id` | uuid | ✅ | — | Profile creating the event |
| `p_user_id` | uuid | ✅ | — | Caller's user ID (ownership check) |
| `p_title` | text | ✅ | — | Event title |
| `p_event_date` | date | ✅ | — | Date of the event in creator's local timezone (`YYYY-MM-DD`) |
| `p_event_time` | time | ✅ | — | Time of the event in creator's local timezone (`HH:MM:SS`) |
| `p_event_end_time` | time | ❌ | `start + 2h` | Optional end time in creator's local timezone (`HH:MM:SS`). If omitted, defaults to 2 hours after `p_event_time`. If less than `p_event_time`, treated as next-day (cross-midnight). Cannot equal `p_event_time`. |
| `p_timezone` | text | ❌ | `'UTC'` | Creator's IANA timezone — e.g. `'America/New_York'`, `'Asia/Kolkata'` |
| `p_description` | text | ❌ | null | Event description |
| `p_livestream` | boolean | ❌ | false | Is this a live stream? |
| `p_video` | boolean | ❌ | false | Is this a video premiere? |
| `p_is_collaborative` | boolean | ❌ | false | Enable collaborator invites on this event (max 5 accepted collaborators) |
| `p_collaborator_ids` | uuid[] | ❌ | null | Profile IDs to invite as collaborators. Requires `p_is_collaborative = true`. Max 5. Invalid/inactive IDs are skipped and returned in `skipped_collaborator_ids`. |
| `p_is_recurring` | boolean | ❌ | false | Is this recurring? If true, recurring params below are required |
| `p_platforms` | jsonb | ❌ | null | Platforms to stream on (see format below) |

### Recurring (required when `p_is_recurring = true`)

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_recurring_days` | text[] | ✅ | Days the event recurs. e.g. `["Mon","Wed","Fri"]` |
| `p_recurring_type` | text | ✅ | `'weekly'` · `'first'` · `'last'` |
| `p_recurring_interval` | int | ✅ when type=weekly | 1–12 weeks. Must be null for `first`/`last` |
| `p_recurring_start_date` | date | ✅ | When the recurring schedule begins |
| `p_recurring_end_date` | date | ❌ | When recurring ends. If omitted, defaults to `p_recurring_start_date + 3 months`. A renewal notification is sent to the owner 7 days before this date |

### p_platforms format

```json
[
  { "platform_id": 1, "stream_url": "https://youtube.com/live/abc123" },
  { "platform_id": 2, "stream_url": "https://twitch.tv/handle" }
]
```

---

## Collaborator Invites

Collaboration is controlled by two params:

| Param | Role |
|-------|------|
| `p_is_collaborative` | Toggle — enables the collaborator feature on this event. Must be `true` to accept invites. |
| `p_collaborator_ids` | Optional array of profile UUIDs to invite at creation time. Requires `p_is_collaborative = true`. |

### Behaviour

| Scenario | Result |
|----------|--------|
| `p_is_collaborative: false` | Event created with no collaboration. `p_collaborator_ids` must not be passed. |
| `p_is_collaborative: true`, no IDs | Event marked collaborative, no invites sent. Use [`invite_collaborator`](invite_collaborator.md) later to add people. |
| `p_is_collaborative: true`, IDs provided | Event created + pending invites sent in one call. Each invitee gets a push notification. |
| `p_is_collaborative: false`, IDs provided | **Error:** `"Cannot add collaborators when is_collaborative is false"` |

### Skip Rules

IDs in `p_collaborator_ids` that cannot be invited are silently skipped and returned in `skipped_collaborator_ids`:

| Skip reason | Condition |
|-------------|-----------|
| Self-invite | `collab_id = p_profile_id` |
| Cap reached | 5 accepted collaborators already on this event |
| Invalid profile | Profile not found or `status ≠ 'active'` |

### Flutter Usage

```dart
// Toggle ON — invite collaborators at creation
await supabase.rpc('create_event', params: {
  'p_profile_id':       profileId,
  'p_user_id':          userId,
  'p_title':            'Co-stream Night',
  'p_event_date':       '2026-05-10',
  'p_event_time':       '20:00:00',
  'p_is_collaborative': true,
  'p_collaborator_ids': ['uuid-1', 'uuid-2'],
});

// Toggle OFF — no collaborators yet, invite later
await supabase.rpc('create_event', params: {
  'p_profile_id':       profileId,
  'p_user_id':          userId,
  'p_title':            'Co-stream Night',
  'p_event_date':       '2026-05-10',
  'p_event_time':       '20:00:00',
  'p_is_collaborative': false,
});
```

### Notification Payload (sent to each invitee)

When an invite is sent, the invitee receives a push notification with this `data` payload:

```json
{
  "type":                  "collaborator_invite",
  "event_id":              "parent-event-uuid",
  "invited_profile_id":    "invitee-profile-uuid",
  "invited_by_profile_id": "creator-profile-uuid"
}
```

Flutter uses `type = 'collaborator_invite'` to show **Accept** / **Decline** action buttons. On tap, call [`respond_collaborator_invite`](respond_collaborator_invite.md) using `event_id` and `invited_profile_id` from this payload.

> Use [`search_collaborator_profiles`](../search/search_collaborator_profiles.md) to populate the collaborator picker UI before calling this SP.

---

## `recurring_type` + `recurring_interval` Mapping

| UI (Repeats dropdown) | `p_recurring_type` | `p_recurring_interval` |
|-----------------------|--------------------|------------------------|
| Every week            | `"weekly"`         | `1`                    |
| Every 2nd week        | `"weekly"`         | `2`                    |
| Every 3rd week        | `"weekly"`         | `3`                    |
| Every 4th week        | `"weekly"`         | `4`                    |
| Custom (slider 1–12)  | `"weekly"`         | `1`–`12`               |
| First                 | `"first"`          | omit / null            |
| Last                  | `"last"`           | omit / null            |

---

## Request Examples

### Non-recurring event
```json
{
  "p_profile_id": "profile-uuid",
  "p_user_id":    "user-uuid",
  "p_title":      "Special Stream",
  "p_event_date": "2026-04-15",
  "p_event_time": "18:00:00",
  "p_event_end_time": "20:00:00",
  "p_timezone":   "America/New_York",
  "p_livestream": true
}
```

### Recurring — Every 2nd week on Mon/Wed/Fri
```json
{
  "p_profile_id":             "profile-uuid",
  "p_user_id":                "user-uuid",
  "p_title":                  "Weekly Gaming Session",
  "p_event_date":             "2026-04-08",
  "p_event_time":             "20:00:00",
  "p_event_end_time":         "22:00:00",
  "p_livestream":             true,
  "p_is_recurring":           true,
  "p_recurring_days":         ["Mon", "Wed", "Fri"],
  "p_recurring_type":         "weekly",
  "p_recurring_interval":     2,
  "p_recurring_start_date":   "2026-04-08",
  "p_recurring_end_date":     "2026-12-31",
  "p_platforms": [
    { "platform_id": 1, "stream_url": "https://youtube.com/live/xyz" }
  ]
}
```

### Recurring — First occurrence of Mon/Tue in each month
```json
{
  "p_profile_id":           "profile-uuid",
  "p_user_id":              "user-uuid",
  "p_title":                "Monthly Recap",
  "p_event_date":           "2026-04-06",
  "p_event_time":           "19:00:00",
  "p_event_end_time":       "20:00:00",
  "p_is_recurring":         true,
  "p_recurring_days":       ["Mon", "Tue"],
  "p_recurring_type":       "first",
  "p_recurring_start_date": "2026-04-06"
}
```

---

## Response

### Success
```json
{
  "status":  true,
  "message": "Event created successfully",
  "data": {
    "event_id":                 "parent-event-uuid",
    "skipped_collaborator_ids": []
  }
}
```

> `event_id` returned is the **parent** event_id. All child occurrences link back to it
> via `parent_event_id`. Use this ID to update or delete the entire recurring series.
>
> `skipped_collaborator_ids` is always present. It is an empty array when all invites
> succeeded, or contains the profile IDs that were skipped (invalid/inactive profile,
> duplicate of creating profile, or over the 5-collaborator cap).

### Error
```json
{
  "status":  false,
  "message": "<reason>"
}
```

---

## Error Cases

| Message | Cause |
|---|---|
| `Profile ID is required` | `p_profile_id` is null |
| `User ID is required` | `p_user_id` is null |
| `Profile not found, access denied, or profile is not active` | Profile doesn't exist, wrong owner, or status ≠ 'active' |
| `Event title is required` | `p_title` null or empty |
| `Event date is required` | `p_event_date` is null |
| `Event time is required` | `p_event_time` is null |
| `Event end time cannot be the same as event start time` | `p_event_end_time = p_event_time` (zero-duration). Values less than start time are valid — treated as next day |
| `Cannot add collaborators when is_collaborative is false` | `p_collaborator_ids` was provided but `p_is_collaborative` is false or omitted |
| `One or more platform IDs are invalid` | `platform_id` not in `platforms` table |
| `Stream URL is required for each platform` | Platform object missing `stream_url` |
| `Recurring days are required` | `p_recurring_days` null or empty when `p_is_recurring = true` |
| `Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun` | Invalid day string in array |
| `recurring_type must be weekly, first, or last` | Invalid or null `p_recurring_type` |
| `recurring_interval is required for weekly type` | `p_recurring_interval` null when type='weekly' |
| `recurring_interval must be between 1 and 12` | Interval out of range |
| `recurring_interval must be null for first/last type` | Interval passed when type='first' or 'last' |
| `Recurring start date is required` | `p_recurring_start_date` null when `p_is_recurring = true` |
| `Recurring end date must be after start date` | `p_recurring_end_date <= p_recurring_start_date` |
| `Something went wrong` | Unhandled exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Null check: p_profile_id, p_user_id
2. Ownership + active check on creator_profiles
3. Collaborator guard: if p_collaborator_ids provided AND p_is_collaborative = false → error
4. Required field checks: title, event_date, event_time
5. Platform validation (if p_platforms non-null/non-empty)
6. Recurring validation (only if p_is_recurring = true):
   ├── recurring_days: non-null, non-empty, all valid abbreviations
   ├── recurring_type: must be 'weekly' | 'first' | 'last'
   ├── If type='weekly': interval required, must be 1–12
   ├── If type='first'/'last': interval must be null
   ├── recurring_start_date: required
   └── recurring_end_date: if provided, must be > start_date
7. INSERT parent row into event_mst → returns v_event_id
8. If p_platforms non-null/non-empty:
   └── INSERT into event_platforms (on parent only; children inherit)
9. If p_is_recurring = true:
   ├── INSERT into event_recurring (recurrence rule for parent)
   ├── v_safe_end = COALESCE(p_recurring_end_date, p_recurring_start_date + 3 months)
   ├── Stored in event_recurring.recurring_end_date = v_safe_end (always a concrete date)
   └── Generate child occurrence rows:
       weekly → FOREACH day: find first_occ >= start, WHILE occ <= safe_end: INSERT, advance +7×interval
       first  → FOREACH day: WHILE month <= safe_end: INSERT first weekday of month (if in range), advance month
       last   → FOREACH day: WHILE month <= safe_end: INSERT last weekday of month (if in range), advance month
10. If p_is_collaborative = true AND p_collaborator_ids non-null/non-empty:
    FOREACH collab_id in p_collaborator_ids:
    ├── Skip if collab_id = p_profile_id (cannot invite self) → add to skipped
    ├── Skip if collab_count >= 5 (cap reached) → add to skipped
    ├── Skip if profile not found or inactive → add to skipped
    ├── INSERT into event_collaborators (status = 'pending')
    └── INSERT notification for invitee
11. RETURN success with event_id + skipped_collaborator_ids
```

---

## Related

- [`update_event`](update_event.md) — update event + recurring schedule
- [`delete_event`](delete_event.md) — delete event (cascades to all child occurrences)
- [`get_profile_events`](get_profile_events.md) — fetch events for a week (reads pre-generated child rows)
- [`get_event_list`](get_event_list.md) — read events by date
- [`invite_collaborator`](invite_collaborator.md) — invite additional collaborators after creation
- [`search_collaborator_profiles`](../search/search_collaborator_profiles.md) — search profiles to pass as `p_collaborator_ids`
- [`event_mst` table](../../database/tables/08_event_mst.md)
- [`event_platforms` table](../../database/tables/09_event_platforms.md)
- [`event_recurring` table](../../database/tables/13_event_recurring.md)
- [`event_collaborators` table](../../database/tables/15_event_collaborators.md)
- [`notify_expiring_recurring_events`](notify_expiring_recurring_events.md) — renewal reminder SP
