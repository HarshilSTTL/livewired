# SP: `respond_collaborator_invite`

**Endpoint:** `POST /rpc/respond_collaborator_invite`
**Group:** Events
**SQL:** [`functions/events/respond_collaborator_invite.md`](../../../functions/events/respond_collaborator_invite.md)
**Tables written:** `event_collaborators` (UPDATE) · `notifications` (INSERT)

---

## Overview

Allows the invited collaborator to accept or decline a pending invite. The caller must own the invited profile. Re-checks the 5-collaborator limit before accepting (race-condition safe). Notifies the event owner of the response.

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
await supabase.rpc('respond_collaborator_invite', params: {
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
| `Collaborator limit reached — cannot accept this invite` | 5 others accepted while this was pending |
| `Something went wrong` | Unhandled DB exception |

---

## Side Effects

- Updates `event_collaborators.status`, `responded_at`, `updated_at`
- Inserts a `notifications` row for the event owner with `type = 'collaborator_response'`

---

## Logic Flow

```
1. Null checks
2. Validate p_response ∈ {'accepted', 'declined'}
3. Verify caller owns p_profile_id
4. Find pending invite for (event_id, profile_id) WHERE is_deleted = false
5. If accepting: re-check accepted count < 5
6. UPDATE event_collaborators SET status = p_response, responded_at = now()
7. INSERT notification for event owner
8. Return success
```

---

## Related

- [`invite_collaborator`](invite_collaborator.md) — sends the original invite
- [`remove_collaborator`](remove_collaborator.md) — owner removes a collaborator
- [`event_collaborators` table](../../database/tables/15_event_collaborators.md)
