# SP: `update_event`

**Endpoint:** `POST /rpc/update_event`
**Group:** Events
**SQL:** [`functions/events/update_event.md`](../../../functions/events/update_event.md)
**Tables written:** `event_mst` · `event_platforms` · `event_recurring` · `event_collaborators` (INSERT/UPDATE if collaborative) · `notifications` (INSERT if collaborative)

---

## Overview

Updates a single event. All fields except `p_event_id` and `p_user_id` are optional — only passed (non-null) fields are applied (COALESCE pattern). Only the event **owner** can update — collaborators do not have update permission.

**Empty-array tolerance:** `p_recurring_days: []` and `p_collaborator_ids: []` are treated the same as `null` (no intent to change). The SP only triggers a recurring rule update or collaborator-invite path when these arrays are passed **non-empty**. Lets a client always include the keys (e.g. from form state) without tripping a guard.

**Per-scope vs series-level routing:**

| Field type | Examples | Scope behaviour |
|-----------|---------|-----------------|
| Per-occurrence (scalar) | `p_title`, `p_event_date`, `p_event_time`, `p_event_end_time`, `p_timezone`, `p_livestream`, `p_video`, `p_description` | `'this'` → applied to the child only · `'all'` → applied to parent + propagated to children |
| Per-occurrence (platforms) | `p_platforms` | `'this'` → override stored on the child's own `event_id` · `'all'` → replaces on parent, clears per-child overrides |
| Series-level (auto-routed) | `p_is_collaborative`, `p_collaborator_ids` | **Always applied to the parent** regardless of scope. Safe to send with `p_scope='this'`. |
| Series-level (rejected with `'this'`) | `p_recurring_days` (non-empty) | Allowed only with `p_scope='all'` — regenerating children would delete the row being edited |

**Platforms:** `null` = don't touch · `[]` = clear all · `[{...}]` = replace all

**Recurring:** Pass `p_recurring_days` non-empty to trigger a recurring rule update. All existing child occurrence rows are deleted and regenerated from the new rules. Any recurring field not passed keeps its existing value via COALESCE. (`'all'` scope only)

**Collaborators:** `null` or `[]` = don't touch · `[uuid, ...]` non-empty = append new invites only. This is a **PATCH** — existing collaborator rows are never deleted or modified. Already-invited profiles (active row with any status) are skipped silently. **Always applied to the parent series**, regardless of `p_scope`.

**Scope (`p_scope`):** `'all'` (default) = update parent + all occurrences · `'this'` = update only this specific occurrence (scalar + platforms). `null` / `''` is treated as `'all'`. Pass the child's `event_id` for `'this'` scope. Flutter should show the dialog whenever `is_recurring = true`.

---

## Parameters

### Core fields

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to update. For `p_scope='this'`: pass the **child** occurrence's `event_id`. For `p_scope='all'`: can pass child or parent — SP resolves to parent automatically |
| `p_user_id` | uuid | ✅ | Must own the profile that created this event |
| `p_scope` | text | ❌ | `'all'` (default) = update parent + all occurrences · `'this'` = update only this child occurrence's scalar + platforms. `null` or empty string is treated as `'all'`. |
| `p_title` | text | ❌ | New title |
| `p_description` | text | ❌ | New description |
| `p_event_date` | date | ❌ | New date in creator's local timezone (`YYYY-MM-DD`) |
| `p_event_time` | time | ❌ | New time in creator's local timezone (`HH:MM:SS`) |
| `p_event_end_time` | time | ❌ | Optional end time (`HH:MM:SS`). If less than start time, treated as next-day (cross-midnight). Cannot equal start time. |
| `p_timezone` | text | ❌ | Creator's IANA timezone — e.g. `'America/New_York'`, `'Asia/Kolkata'` |
| `p_livestream` | boolean | ❌ | Toggle livestream flag |
| `p_video` | boolean | ❌ | Toggle video flag |
| `p_is_collaborative` | boolean | ❌ | Enable or disable collaborative mode. **Series-level** — always applied to parent + propagated to all children, regardless of `p_scope`. |
| `p_collaborator_ids` | uuid[] | ❌ | Profile IDs to invite. `null` or `[]` = no change. Non-empty requires `p_is_collaborative = true` (current or being set in same call). **Series-level** — invites are always recorded on the parent. Appends only — never removes existing collaborators. Max 5 accepted per event. |
| `p_platforms` | jsonb | ❌ | `null` = no change · `[]` = clear · `[{...}]` = replace |

### Recurring fields (pass `p_recurring_days` non-empty to trigger recurring update)

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_recurring_days` | text[] | ❌ | Days to recur — e.g. `["Mon","Wed"]`. `null` or `[]` = no change. Non-empty triggers full child regeneration. `'all'` scope only. |
| `p_recurring_type` | text | ❌ | `'weekly'` · `'first'` · `'last'` — kept from existing if not passed |
| `p_recurring_interval` | int | ❌ | 1–12 weeks (weekly type only) |
| `p_recurring_start_date` | date | ❌ | New start date for the recurring schedule |
| `p_recurring_end_date` | date | ❌ | New end date. If omitted, keeps the existing value. If no existing value, defaults to `recurring_start_date + 3 months` |

> Passing `p_recurring_days` **non-empty** is the trigger. Any recurring field not passed keeps its current value via COALESCE.

---

## Request Examples

> All examples below use the test owner profile and test event id:
> - `p_user_id` = `be7bb571-1811-49f7-9bd5-a7db98c47815`
> - `p_event_id` = `ace2c42d-d493-4513-bea5-78858654d5ee` (a child occurrence of a recurring series)

### 1. Update title only — all occurrences (scope omitted → defaults to `'all'`)

```json
{
  "p_event_id": "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":  "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_title":    "Metroid Monday — Special Edition"
}
```

### 2. Update only this occurrence (`p_scope = 'this'`)

```json
{
  "p_event_id":   "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":    "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_scope":      "this",
  "p_description": "updated event description",
  "p_event_date": "2026-05-19",
  "p_event_time": "21:00:00"
}
```

**Response:**
```json
{
  "status": true,
  "message": "Event occurrence updated successfully",
  "data": { "skipped_collaborator_ids": [] }
}
```

### 3. Update only this occurrence — also includes empty arrays from form state

```json
{
  "p_event_id":         "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":          "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_scope":            "this",
  "p_event_date":       "2026-05-19",
  "p_event_time":       "21:00:00",
  "p_recurring_days":   [],
  "p_collaborator_ids": []
}
```

The empty arrays are equivalent to `null` and are silently ignored. The occurrence is updated normally.

### 4. Update one occurrence AND invite collaborators in one call (auto-routing)

> Demonstrates series-level routing: scalar/platform changes apply to this child, while `p_is_collaborative` and `p_collaborator_ids` apply to the **parent series**.

```json
{
  "p_event_id":         "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":          "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_scope":            "this",
  "p_title":            "birthday12",
  "p_event_date":       "2026-05-12",
  "p_event_time":       "00:00:00",
  "p_event_end_time":   "18:30:00",
  "p_timezone":         "Asia/Kolkata",
  "p_is_collaborative": true,
  "p_collaborator_ids": [
    "44d804c3-18e7-4104-85bc-cee324c7de95",
    "b54bceda-c1c5-4a5e-b1ab-da00d2b33a9b"
  ],
  "p_platforms": [
    { "platform_id": 1, "stream_url": "https://www.youtube.com/" }
  ]
}
```

**What happens:**
- This child row gets `title`, `event_date`, `event_time`, `event_end_time`, `event_timezone` updated + `is_overridden = true`.
- This child's `event_platforms` rows are replaced with the YouTube entry (per-occurrence override).
- The **parent** row + all child rows get `is_collaborative = true`.
- Two collaborator invite rows are inserted on the **parent's** `event_id`; both invitees receive notifications.

**Response:**
```json
{
  "status": true,
  "message": "Event occurrence updated successfully",
  "data": { "skipped_collaborator_ids": [] }
}
```

### 5. Update all occurrences (`p_scope = 'all'`)

```json
{
  "p_event_id":   "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":    "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_scope":      "all",
  "p_event_time": "20:00:00"
}
```

### 6. Update recurring schedule — change to every 2 weeks on Mon + Wed

```json
{
  "p_event_id":           "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":            "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_recurring_days":     ["Mon", "Wed"],
  "p_recurring_type":     "weekly",
  "p_recurring_interval": 2,
  "p_recurring_end_date": "2026-12-31"
}
```

### 7. Update recurring schedule — change to "first Friday of month"

```json
{
  "p_event_id":           "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":            "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_recurring_days":     ["Fri"],
  "p_recurring_type":     "first",
  "p_recurring_interval": null,
  "p_recurring_end_date": "2026-12-31"
}
```

### 8. Replace platforms (all occurrences)

```json
{
  "p_event_id":  "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":   "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_platforms": [
    { "platform_id": 1, "stream_url": "https://youtube.com/live/abc" },
    { "platform_id": 2, "stream_url": "https://twitch.tv/creatorone" }
  ]
}
```

### 9. Per-occurrence platform override (`p_scope = 'this'`)

```json
{
  "p_event_id":  "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":   "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_scope":     "this",
  "p_platforms": [
    { "platform_id": 3, "stream_url": "https://kick.com/creator-special" }
  ]
}
```

### 10. Clear all platforms (parent + children)

```json
{
  "p_event_id":  "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":   "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_platforms": []
}
```

### 11. Append collaborators only

```json
{
  "p_event_id":         "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":          "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_collaborator_ids": [
    "44d804c3-18e7-4104-85bc-cee324c7de95",
    "b54bceda-c1c5-4a5e-b1ab-da00d2b33a9b"
  ]
}
```

### 12. Enable collaboration AND invite in one call

```json
{
  "p_event_id":         "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":          "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_is_collaborative": true,
  "p_collaborator_ids": ["44d804c3-18e7-4104-85bc-cee324c7de95"]
}
```

### 13. Cross-midnight end time (end < start = next-day end)

```json
{
  "p_event_id":      "ace2c42d-d493-4513-bea5-78858654d5ee",
  "p_user_id":       "be7bb571-1811-49f7-9bd5-a7db98c47815",
  "p_scope":         "this",
  "p_event_time":    "22:00:00",
  "p_event_end_time":"01:30:00"
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

> `skipped_collaborator_ids` is always present in both responses. Empty array `[]` when all invites succeeded or `p_collaborator_ids` was not passed (or was empty). Contains profile UUIDs that were skipped (already invited, invalid/inactive profile, self-invite, or cap reached).

### Error

```json
{ "status": false, "message": "<reason>", "error": "<sqlerrm>" }
```

`error` is only populated for the catch-all `Something went wrong` case.

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id and p_user_id are required` | Either required param is null |
| `p_scope must be 'all' or 'this'` | Invalid scope value passed |
| `Event not found or access denied` | No matching event, or caller is not the event owner |
| `Scope 'this' can only be used on a specific recurring occurrence — pass the child event_id, not the parent` | `p_scope='this'` with a parent or non-recurring `event_id` |
| `Recurring schedule cannot be changed for a single occurrence — use scope 'all'` | `p_recurring_days` passed **non-empty** with `p_scope='this'`. Cannot regen children without deleting the row being edited. |
| `Cannot add collaborators when is_collaborative is false` | `p_collaborator_ids` non-empty but neither `p_is_collaborative: true` is being set in the same call nor the parent's current `is_collaborative` is true |
| `Event end time cannot be the same as event start time` | Final end time equals final start time (zero-duration). End time less than start time is valid — treated as next day |
| `One or more platform IDs are invalid` | A `platform_id` in `p_platforms` does not exist |
| `Stream URL is required for each platform` | A platform object is missing `stream_url` |
| `Invalid recurring day — must be Mon, Tue, Wed, Thu, Fri, Sat, or Sun` | Invalid day string in `p_recurring_days` |
| `recurring_type must be weekly, first, or last` | Invalid type value (or no existing type and none provided) |
| `recurring_interval is required for weekly type` | Interval null when type is weekly |
| `recurring_interval must be between 1 and 12` | Interval out of range |
| `recurring_interval must be null for first/last type` | Interval passed for first/last |
| `Recurring start date is required` | No start date in DB or passed |
| `Recurring end date must be after start date` | End ≤ start |
| `Something went wrong` | Unhandled DB exception (see `error` field for SQLERRM) |

> `Collaborator invites cannot be scoped to a single occurrence` is **no longer a returnable error** — collaborator invites with `p_scope='this'` now auto-route to the parent.
> `Recurring days cannot be empty` is **no longer a returnable error** — empty arrays are treated as "no intent to change."

---

## Logic Flow

```
1. Null check: p_event_id, p_user_id
2. Normalise p_scope (null/'' → 'all'); validate ∈ {'all', 'this'}
3. Compute intent flags:
   - v_update_recurring  = p_recurring_days   IS NOT NULL AND len > 0
   - v_update_collabs    = p_collaborator_ids IS NOT NULL AND len > 0
   - v_has_scalar        = any of p_title, p_description, p_event_date/time/end_time, p_timezone, p_livestream, p_video IS NOT NULL
   - v_has_platforms     = p_platforms IS NOT NULL
   - v_occurrence_change = v_has_scalar OR v_has_platforms
4. Ownership check: event_mst JOIN creator_profiles (owner only)
5. Resolve parent:
   - SELECT parent_event_id INTO v_parent_event_id
   - v_target_parent_id = COALESCE(v_parent_event_id, p_event_id)

── BRANCH A: p_scope = 'this' ──────────────────────────────────────────────
6a. Guard: v_parent_event_id must not be NULL (must be a child occurrence row)
7a. Guard: v_update_recurring must be FALSE (regen would delete this row)
8a. End-time validation against this child's current values (only when v_has_scalar)
9a. Platform validation (only when p_platforms non-empty)
10a. If v_occurrence_change:
     UPDATE event_mst SET COALESCE scalar fields + is_overridden=true WHERE event_id = p_event_id
11a. If p_platforms IS NOT NULL:
     - DELETE event_platforms WHERE event_id = p_event_id
     - INSERT new rows on the child's own event_id (per-occurrence override)
12a. v_success_message = "Event occurrence updated successfully"

── BRANCH B: p_scope = 'all' (default) ─────────────────────────────────────
6b. End-time validation against parent's current values
7b. Platform validation (only when p_platforms non-empty)
8b. If v_update_recurring: validate day names, fetch+merge recurring rule, validate
9b. UPDATE parent (event_mst) with COALESCE for all optional scalar fields (no is_collaborative — handled in shared section)
10b. Propagate scalar changes to all child rows + reset is_overridden = false (no is_collaborative)
11b. If p_platforms IS NOT NULL: clear parent's platforms + per-child overrides, insert new platform rows on parent
12b. v_success_message = "Event updated successfully"

── SHARED: is_collaborative (always parent-level, applies to both scopes) ──
13. If p_is_collaborative IS NOT NULL:
    UPDATE event_mst SET is_collaborative = p_is_collaborative
    WHERE event_id = v_target_parent_id OR parent_event_id = v_target_parent_id

── SHARED: recurring rule + regen (Branch B only) ──────────────────────────
14. If v_scope = 'all' AND v_update_recurring:
    - UPDATE event_recurring (clear renewal_notified_at)
    - DELETE all child rows
    - Regenerate children from new rule (weekly | first | last)
      (inherits parent's freshly-set is_collaborative)

── SHARED: collaborator invites (always parent-level, PATCH append) ────────
15. If v_update_collabs:
    - Compute effective is_collaborative (COALESCE p_is_collaborative, parent.is_collaborative)
    - If effective = false → error "Cannot add collaborators when is_collaborative is false"
    - FOREACH collab_id:
      ├── Skip null slots
      ├── Skip if = owner (self-invite)
      ├── Skip if accepted count >= 5 (cap)
      ├── Skip if active non-deleted row already exists (any status)
      ├── Skip if profile not found or inactive
      ├── If soft-deleted row exists → reactivate (UPDATE to pending, is_deleted = false)
      └── Else → INSERT new pending invite + notify invitee (with invited_profile_id in data)

16. RETURN { status: true, message: v_success_message, data: { skipped_collaborator_ids: v_skipped_ids } }
```

---

## Behavioural Matrix — what does each combination do?

| `p_scope` | `p_recurring_days` | `p_collaborator_ids` | `p_is_collaborative` | Result |
|-----------|--------------------|----------------------|----------------------|--------|
| `'this'`  | null / `[]`        | null / `[]`          | null                 | Update this occurrence only |
| `'this'`  | null / `[]`        | non-empty            | null / true          | Update this occurrence + append invites on parent |
| `'this'`  | null / `[]`        | non-empty            | false (or parent flag false) | Error: `Cannot add collaborators when is_collaborative is false` |
| `'this'`  | null / `[]`        | null / `[]`          | true / false         | Update this occurrence + set is_collaborative on parent + propagate |
| `'this'`  | non-empty          | any                  | any                  | Error: schedule can't be per-occurrence |
| `'all'`   | null / `[]`        | null / `[]`          | null                 | Update parent + propagate to children |
| `'all'`   | non-empty          | any                  | any                  | Update parent + regenerate children from new rule |
| `'all'`   | any                | non-empty            | null / true          | Append invites on parent |

---

## Deployment

The function signature changed on 2026-05-08 (added `p_scope`) and again on 2026-05-11 (empty-array tolerance, series-level auto-routing, conditional `is_overridden`). PostgreSQL keeps old overloads alongside new ones whenever the signature changes, and PostgREST routes based on JSON-key match — so an old overload can keep serving traffic invisibly.

**Always re-deploy with this two-step pattern:**

```sql
-- 1) Drop every existing update_event overload
DO $$
DECLARE r record;
BEGIN
    FOR r IN
        SELECT p.oid::regprocedure AS sig
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.proname = 'update_event' AND n.nspname = 'public'
    LOOP
        EXECUTE 'DROP FUNCTION ' || r.sig || ' CASCADE';
    END LOOP;
END $$;

-- 2) Paste the full CREATE FUNCTION block from functions/events/update_event.md, then:
NOTIFY pgrst, 'reload schema';
```

Verify only one signature exists after deploy:

```sql
SELECT p.oid::regprocedure AS signature
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'update_event' AND n.nspname = 'public';
-- Expected: exactly one row
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
