# SP: `remove_collaborator`

**Endpoint:** `POST /rpc/remove_collaborator`
**Group:** Events
**SQL:** [`functions/events/remove_collaborator.md`](../../../functions/events/remove_collaborator.md)
**Tables written:** `event_collaborators` (UPDATE — soft delete)

---

## Overview

Soft-deletes a collaborator from an event. Only the event owner can remove collaborators. The removed profile can be re-invited later via `invite_collaborator` — the soft-deleted row will be reactivated.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to remove the collaborator from |
| `p_requesting_user_id` | uuid | ✅ | Must be the owner of the event |
| `p_collaborator_profile_id` | uuid | ✅ | The profile to remove |

---

## Request Example

```json
{
  "p_event_id":                "event-uuid",
  "p_requesting_user_id":      "owner-user-uuid",
  "p_collaborator_profile_id": "collaborator-profile-uuid"
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Collaborator removed successfully" }
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id, p_requesting_user_id, and p_collaborator_profile_id are all required` | Any required param is null |
| `Event not found or access denied` | Event doesn't exist, deleted, or caller doesn't own it |
| `Collaborator not found for this event` | No active (non-deleted) collaborator row found |
| `Something went wrong` | Unhandled DB exception |

---

## Logic Flow

```
1. Null checks
2. Verify caller owns the event
3. Find active (is_deleted = false) row for (event_id, collaborator_profile_id)
4. Soft delete: SET is_deleted = true, deleted_at = now(), updated_at = now()
5. Return success
```

---

## Related

- [`invite_collaborator`](invite_collaborator.md) — re-invite after removal
- [`respond_collaborator_invite`](respond_collaborator_invite.md)
- [`event_collaborators` table](../../database/tables/15_event_collaborators.md)
