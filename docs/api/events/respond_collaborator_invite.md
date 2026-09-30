# SP: `respond_collaborator_invite`

| Version | Function | Endpoint | Status |
|---------|----------|----------|--------|
| v3 | `respond_collaborator_invite_v3` | `POST /rpc/respond_collaborator_invite_v3` | ✅ Current |
| v2 | `respond_collaborator_invite_v2` | `POST /rpc/respond_collaborator_invite_v2` | ❌ Deprecated |
| v1 | `respond_collaborator_invite` | `POST /rpc/respond_collaborator_invite` | ❌ Deprecated |

> **Use `respond_collaborator_invite_v3`** — additionally clears the invitee's invite notification after they respond (v2 raised the cap from 5 to 9). See [`functions/events/respond_collaborator_invite.md`](../../../functions/events/respond_collaborator_invite.md).

**Endpoint:** `POST /rpc/respond_collaborator_invite_v3`
**Group:** Events
**SQL:** [`functions/events/respond_collaborator_invite.md`](../../../functions/events/respond_collaborator_invite.md)
**Tables written:** `event_collaborators` (UPDATE) · `notifications` (INSERT, UPDATE)

---

## Overview

Allows the invited collaborator to accept or decline a pending invite. The caller must own the invited profile. Re-checks the 9-collaborator limit before accepting (race-condition safe). Notifies the event owner of the response, and removes the invitee's own invite notification from their notifications page. **Declining automatically removes the collaborator from the event** (soft delete), so the organizer has nothing to remove manually.

---

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `p_event_id` | uuid | ✅ | The event the invite is for |
| `p_profile_id` | uuid | ✅ | The collaborator's own profile |
| `p_user_id` | uuid | ✅ | Must own `p_profile_id` |
| `p_response` | text | ✅ | `'accepted'` or `'declined'` |

---

## Request Examples

### Accept
```json
{
  "p_event_id":   "event-uuid",
  "p_profile_id": "collaborator-profile-uuid",
  "p_user_id":    "collaborator-user-uuid",
  "p_response":   "accepted"
}
```

### Decline
```json
{
  "p_event_id":   "event-uuid",
  "p_profile_id": "collaborator-profile-uuid",
  "p_user_id":    "collaborator-user-uuid",
  "p_response":   "declined"
}
```

> `p_event_id` and `p_profile_id` come from the `collaborator_invite` push notification payload fields `event_id` and `invited_profile_id`. `p_user_id` is the logged-in user's ID (already known to the app).

---

## Flutter Usage

```dart
// Called when the user taps Accept or Decline on the notification
// notif.data comes from the push notification payload
await supabase.rpc('respond_collaborator_invite_v3', params: {
  'p_event_id':   notif.data['event_id'],
  'p_profile_id': notif.data['invited_profile_id'],
  'p_user_id':    currentUserId,
  'p_response':   'accepted',  // or 'declined'
});
```

---

## Response

### Success
```json
{ "status": true, "message": "Invite accepted successfully" }
```
```json
{ "status": true, "message": "Invite declined successfully" }
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Error Cases

| Message | Cause |
|---------|-------|
| `p_event_id, p_profile_id, p_user_id, and p_response are all required` | Any required param is null |
| `p_response must be accepted or declined` | Invalid response value |
| `Profile not found or access denied` | Caller doesn't own the profile |
| `No pending invite found for this event and profile` | No pending non-deleted invite exists |
| `Collaborator limit reached — cannot accept this invite` | 9 others accepted while this was pending |
| `Something went wrong` | Unhandled DB exception |

---

## Side Effects

- Updates `event_collaborators.status`, `responded_at`, `updated_at`
- On `'declined'`, also sets `is_deleted = true` — the collaborator disappears from the event's collaborator list; they can be re-invited later
- Inserts a `notifications` row for the event owner with `type = 'collaborator_response'`
- Sets `is_cleared = true` on the caller's `collaborator_invite` notification(s) for this event (matched by `user_id` + `event_id`), so `get_notifications` no longer returns them

---

## Logic Flow

```
1. Null checks
2. Validate p_response ∈ {'accepted', 'declined'}
3. Verify caller owns p_profile_id
4. Find pending invite for (event_id, profile_id) WHERE is_deleted = false
5. If accepting: re-check accepted count < 9
6. UPDATE event_collaborators SET status = p_response, is_deleted = (p_response = 'declined'), responded_at = now()
7. UPDATE notifications SET is_cleared = true for the invitee's collaborator_invite (user_id + event_id)
8. INSERT notification for event owner
9. Return success
```

---

## Related

- [`invite_collaborator`](invite_collaborator.md) — sends the original invite
- [`remove_collaborator`](remove_collaborator.md) — owner removes a collaborator
- [`event_collaborators` table](../../database/tables/15_event_collaborators.md)
