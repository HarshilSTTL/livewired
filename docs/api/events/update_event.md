# SP: `update_event`

**Endpoint:** `POST /rpc/update_event`
**Group:** Events
**SQL:** [`functions/events/update_event.md`](../../../functions/events/update_event.md)
**Tables written:** `event_mst` · `event_platforms` · `event_recurring` · `event_collaborators` (INSERT/UPDATE if collaborative) · `notifications` (INSERT if collaborative)

---

## Overview

Updates a single event. All fields except `p_event_id` and `p_user_id` are optional — only passed (non-null) fields are applied (COALESCE pattern). Only the event **owner** can update — collaborators do not have update permission.

**Platforms:** `null` = don't touch · `[]` = clear all · `[{...}]` = replace all

**Recurring:** Pass `p_recurring_days` to trigger a recurring rule update. All existing child occurrence rows are deleted and regenerated from the new rules. Any recurring field not passed keeps its existing value.

**Collaborators:** `null` = don't touch · `[uuid, ...]` = append new invites only. This is a **PATCH** — existing collaborator rows are never deleted or modified. Already-invited profiles (active row with any status) are skipped silently. (`'all'` scope only)

**Scope (`p_scope`):** `'all'` (default) = update parent + all occurrences · `'this'` = update only this specific occurrence. Pass the child's `event_id` for `'this'` scope. Flutter should show the dialog whenever `is_recurring = true`.

---

## Parameters

### Core fields

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to update. For `p_scope='this'`: pass the **child** occurrence's `event_id`. For `p_scope='all'`: can pass child or parent — SP resolves to parent automatically |
| `p_user_id` | uuid | ✅ | Must own the profile that created this event |
| `p_scope` | text | ❌ | `'all'` (default) = update parent + all occurrences · `'this'` = update only this child occurrence |
| `p_title` | text | ❌ | New title |
| `p_description` | text | ❌ | New description |
| `p_event_date` | date | ❌ | New date in creator's local timezone (`YYYY-MM-DD`) |
| `p_event_time` | time | ❌ | New time in creator's local timezone (`HH:MM:SS`) |
| `p_event_end_time` | time | ❌ | Optional end time (`HH:MM:SS`). If less than start time, treated as next-day (cross-midnight). Cannot equal start time. |
| `p_timezone` | text | ❌ | Creator's IANA timezone — e.g. `'America/New_York'` |
| `p_livestream` | boolean | ❌ | Toggle livestream flag |
| `p_video` | boolean | ❌ | Toggle video flag |
| `p_is_collaborative` | boolean | ❌ | Enable or disable collaborative mode |
| `p_collaborator_ids` | uuid[] | ❌ | Profile IDs to invite. Requires `p_is_collaborative = true` (current or being set now). Appends only — never removes existing collaborators. Max 5 accepted per event. |
| `p_platforms` | jsonb | ❌ | `null` = no change · `[]` = clear · `[{...}]` = replace |

### Recurring fields (pass `p_recurring_days` to trigger recurring update)

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_recurring_days` | text[] | ❌ | Days to recur — e.g. `["Mon","Wed"]`. Triggers full child regeneration |
| `p_recurring_type` | text | ❌ | `'weekly'` · `'first'` · `'last'` — kept from existing if not passed |
| `p_recurring_interval` | int | ❌ | 1–12 weeks (weekly type only) |
| `p_recurring_start_date` | date | ❌ | New start date for the recurring schedule |
| `p_recurring_end_date` | date | ❌ | New end date. If omitted, keeps the existing value. If no existing value, defaults to `recurring_start_date + 3 months` |

> Passing `p_recurring_days` is the trigger. Any recurring field not passed keeps its current value via COALESCE.

---

## Request Examples

### Update title only — all occurrences (default)
```json
{
  "p_event_id": "uuid...",
  "p_user_id":  "uuid...",
  "p_title":    "Metroid Monday — Special Edition"
}
```

### Update only this occurrence (`p_scope = 'this'`)
> Pass the **child** occurrence's `event_id`. Parent and all other occurrences are untouched.
```json
{
  "p_event_id":       "child-occurrence-uuid",
  "p_user_id":        "uuid...",
  "p_scope":          "this",
  "p_event_date":     "2026-05-19",
  "p_event_time":     "21:00:00",
  "p_event_end_time": "23:00:00"
}
```

### Update all occurrences (`p_scope = 'all'`)
> Can pass child or parent `event_id` — SP always resolves to the parent.
```json
{
  "p_event_id":   "uuid...",
  "p_user_id":    "uuid...",
  "p_scope":      "all",
  "p_event_time": "20:00:00"
}
```

### Update recurring schedule — change to every 2 weeks
```json
{
  "p_event_id":           "uuid...",
  "p_user_id":            "uuid...",
  "p_recurring_days":     ["Mon", "Wed"],
  "p_recurring_type":     "weekly",
  "p_recurring_interval": 2,
  "p_recurring_end_date": "2026-12-31"
}
```

### Replace platforms
```json
{
  "p_event_id":  "uuid...",
  "p_user_id":   "uuid...",
  "p_platforms": [
    { "platform_id": 1, "stream_url": "https://youtube.com/live/abc" },
    { "platform_id": 2, "stream_url": "https://twitch.tv/creatorone" }
  ]
}
```

### Clear all platforms
```json
{
  "p_event_id":  "uuid...",
  "p_user_id":   "uuid...",
  "p_platforms": []
}
```

### Append collaborators (existing collaborators are untouched)
```json
{
  "p_event_id":          "uuid...",
  "p_user_id":           "uuid...",
  "p_collaborator_ids":  ["profile-uuid-1", "profile-uuid-2"]
}
```

### Enable collaboration and invite in one call
```json
{
  "p_event_id":          "uuid...",
  "p_user_id":           "uuid...",
  "p_is_collaborative":  true,
  "p_collaborator_ids":  ["profile-uuid-1"]
}
```

### Collaborator invite notification payload

Each invited profile receives a push notification with this `data` payload:

```json
{
  "type":                  "collaborator_invite",
  "event_id":              "parent-event-uuid",
  "invited_profile_id":    "invitee-profile-uuid",
  "invited_by_profile_id": "owner-profile-uuid"
}
```

Flutter uses `type = 'collaborator_invite'` to show **Accept** / **Decline** buttons. On tap, call [`respond_collaborator_invite`](respond_collaborator_invite.md) with `event_id` and `invited_profile_id` from this payload.

---

## Response

### Success — `p_scope = 'all'` (default)
```json
{
  "status":  true,
  "message": "Event updated successfully",
  "data": {
    "skipped_collaborator_ids": []
  }
}
```

### Success — `p_scope = 'this'`
```json
{
  "status":  true,
  "message": "Event occurrence updated successfully",
  "data": {
    "skipped_collaborator_ids": []
  }
}
```

> `skipped_collaborator_ids` is always present in both responses. Empty array `[]` when all invites succeeded or `p_collaborator_ids` was not passed. Contains profile UUIDs that were skipped (already invited, invalid/inactive profile, self-invite, or cap reached).

### Error
```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id and p_user_id are required` | Either required param is null |
| `Event not found or access denied` | No matching event, or caller is not the event owner |
| `Event end time cannot be the same as event start time` | Final end time equals final start time (zero-duration). End time less than start time is valid — treated as next day |
| `One or more platform IDs are invalid` | A `platform_id` in `p_platforms` does not exist |
| `Stream URL is required for each platform` | A platform object is missing `stream_url` |
| `Recurring days cannot be empty` | `p_recurring_days` passed as empty array |
| `Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun` | Invalid day string |
| `recurring_type must be weekly, first, or last` | Invalid type value |
| `recurring_interval is required for weekly type` | Interval null when type is weekly |
| `recurring_interval must be between 1 and 12` | Interval out of range |
| `recurring_interval must be null for first/last type` | Interval passed for first/last |
| `Recurring start date is required` | No start date in DB or passed |
| `Recurring end date must be after start date` | End ≤ start |
| `p_scope must be 'all' or 'this'` | Invalid scope value passed |
| `Scope 'this' can only be used on a specific recurring occurrence` | `p_scope='this'` passed with a parent or non-recurring event_id |
| `Recurring schedule cannot be changed for a single occurrence` | `p_recurring_days` passed with `p_scope='this'` |
| `Collaborator invites cannot be scoped to a single occurrence` | `p_collaborator_ids` passed with `p_scope='this'` |
| `Cannot add collaborators when is_collaborative is false` | `p_collaborator_ids` passed but neither `p_is_collaborative: true` nor the event's current flag is true |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null check: p_event_id, p_user_id
2. Ownership check: event_mst JOIN creator_profiles (owner only)
   - Fetch v_parent_event_id (NULL if p_event_id is the parent)
   - v_target_parent_id = COALESCE(v_parent_event_id, p_event_id)
3. Validate p_scope ∈ {'all', 'this'} (default 'all')

── BRANCH A: p_scope = 'this' ──────────────────────────────────────────────
4a. Guard: v_parent_event_id must not be NULL (must be a child occurrence row)
5a. Guard: p_recurring_days must be NULL (cannot change schedule for one occurrence)
6a. Guard: p_collaborator_ids must be NULL (collaborators are always parent-level)
7a. UPDATE event_mst SET COALESCE fields WHERE event_id = p_event_id (child only)
8a. If p_platforms IS NOT NULL:
    - DELETE event_platforms WHERE event_id = p_event_id (child's own rows)
    - INSERT new platform rows on the child's own event_id (per-occurrence override)
    - Read SPs detect this via EXISTS CASE and serve child's platforms instead of parent's
9a. RETURN "Event occurrence updated successfully" + skipped_collaborator_ids: []

── BRANCH B: p_scope = 'all' (default) ─────────────────────────────────────
4b. Collaborator guard: if p_collaborator_ids provided AND effective is_collaborative = false → error
5b. Validate p_platforms (if provided and non-empty)
6b. If p_recurring_days IS NOT NULL:
    - Fetch existing event_recurring row (for COALESCE)
    - Merge passed values over existing
    - Validate merged recurring rule
7b. UPDATE event_mst (parent) with COALESCE for all optional fields WHERE event_id = v_target_parent_id
8b. Propagate scalar changes to all child rows:
    UPDATE event_mst SET title, description, event_time, event_end_time, event_timezone,
                         livestream, video, is_collaborative
    WHERE parent_event_id = v_target_parent_id (COALESCE — unchanged fields kept)
9b. If p_platforms IS NOT NULL:
    - DELETE event_platforms WHERE event_id = v_target_parent_id (parent)
    - DELETE event_platforms for all child event_ids (clears per-occurrence overrides)
    - INSERT new platform rows on parent (children inherit via EXISTS CASE in read SPs)
10b. If p_recurring_days IS NOT NULL:
    - UPDATE event_recurring with merged values
    - DELETE all child rows (WHERE parent_event_id = v_target_parent_id)
    - Regenerate child rows — each inherits is_collaborative from parent
      weekly → FOREACH day: find first occ, step +7×interval until safe_end
      first/last → FOREACH day: WHILE month <= safe_end: insert first/last weekday of month
11b. If p_collaborator_ids IS NOT NULL and non-empty (PATCH append):
    - Pre-fetch accepted collaborator count
    - FOREACH collab_id:
      ├── Skip if = owner (self-invite)
      ├── Skip if accepted count >= 5 (cap)
      ├── Skip if active non-deleted row already exists (any status)
      ├── Skip if profile not found or inactive
      ├── If soft-deleted row exists → reactivate (UPDATE to pending, is_deleted = false)
      └── Else → INSERT new pending invite + notify invitee (with invited_profile_id in data)
12b. RETURN "Event updated successfully" + skipped_collaborator_ids
```

---

## Related

- [`get_event_by_id`](get_event_by_id.md) — fetch current event state before editing
- [`create_event`](create_event.md) — original creation (also supports bundled collaborator invites)
- [`delete_event`](delete_event.md) — remove this event
- [`remove_collaborator`](remove_collaborator.md) — owner removes a collaborator
- [`respond_collaborator_invite`](respond_collaborator_invite.md) — invitee accepts/declines
- [`search_collaborator_profiles`](../search/search_collaborator_profiles.md) — search profiles for the collaborator picker
- [`event_recurring` table](../../database/tables/13_event_recurring.md)
- [`event_collaborators` table](../../database/tables/15_event_collaborators.md)
