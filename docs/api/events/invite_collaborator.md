# SP: `invite_collaborator`

**Endpoint:** `POST /rpc/invite_collaborator`
**Group:** Events
**SQL:** [`functions/events/invite_collaborator.md`](../../../functions/events/invite_collaborator.md)
**Tables written:** `event_collaborators` (INSERT / UPDATE) · `notifications` (INSERT)

---

## Overview

Sends a collaboration invite to any active creator profile for a given event. Only the event owner can send invites. The event must have `is_collaborative = true`. Up to **5 accepted** collaborators are allowed per event.

If the same profile was previously removed (soft-deleted), the existing row is reactivated as a fresh `pending` invite instead of inserting a new row.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event to invite to (use parent event_id for recurring events) |
| `p_inviting_user_id` | uuid | ✅ | Must be the owner of the event's profile |
| `p_collaborator_profile_id` | uuid | ✅ | The creator profile being invited |

---

## Request Example

```json
{
  "p_event_id":                "event-uuid",
  "p_inviting_user_id":        "owner-user-uuid",
  "p_collaborator_profile_id": "collaborator-profile-uuid"
}
```

---

## Response

### Success
```json
{ "status": true, "message": "Invitation sent successfully" }
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `Event ID is required` | `p_event_id` is null |
| `User ID is required` | `p_inviting_user_id` is null |
| `Collaborator profile ID is required` | `p_collaborator_profile_id` is null |
| `Event not found or access denied` | Event doesn't exist, is deleted, or caller doesn't own it |
| `Event is not marked as collaborative` | `event_mst.is_collaborative = false` |
| `You cannot invite yourself as a collaborator` | Caller is inviting their own profile |
| `Collaborator profile not found or inactive` | Target profile doesn't exist or status ≠ 'active' |
| `Collaborator limit reached (maximum 5 collaborators per event)` | Already 5 accepted collaborators |
| `This profile has already been invited to collaborate on this event` | Active (non-deleted) invite already exists |
| `Something went wrong` | Unhandled DB exception |

---

## Side Effects

- Inserts a `notifications` row for the invited profile's user with `type = 'collaborator_invite'`

---

## Logic Flow

```
1. Null checks
2. Verify caller owns the event (event_mst → creator_profiles → users)
3. Verify is_collaborative = true on the event
4. Prevent owner from inviting themselves
5. Verify collaborator profile is active → get their user_id
6. Count accepted (non-deleted) collaborators → reject if >= 5
7. Check for existing row:
   - Active row exists → return error (already invited)
   - Soft-deleted row exists → reactivate it (status=pending, reset dates)
   - No row → INSERT fresh invite
8. INSERT notification for invitee
9. Return success
```

---

## Related

- [`respond_collaborator_invite`](respond_collaborator_invite.md) — invitee accepts or declines
- [`remove_collaborator`](remove_collaborator.md) — owner removes a collaborator
- [`event_collaborators` table](../../database/tables/15_event_collaborators.md)
