# SP: `get_user_profiles`

**Endpoint:** `POST /rpc/get_user_profiles`
**Group:** Profile
**SQL:** [`functions/profiles/get_user_profiles.md`](../../../functions/profiles/get_user_profiles.md)
**Tables read:** `creator_profiles`

---

## Overview

Lightweight SP for the **post-login profile selector**. Returns only the minimal fields
needed to display profile cards and let the user pick which profile to enter with.
No platforms, tags, or follower counts — just what the UI needs to render the list fast.

Only returns `active` profiles.

---

## Parameters

| Parameter | Type | Required | Description |
|---|---|---|---|
| `p_user_id` | uuid | ✅ | The logged-in user's ID |

---

## Request Example

```json
{
  "p_user_id": "user-uuid"
}
```

---

## Response

### Success — user has profiles
```json
{
  "status":  true,
  "message": "Profiles fetched successfully",
  "data": {
    "profiles": [
      {
        "profile_id":   "uuid-1",
        "profile_name": "Gaming Channel",
        "avatar":       "<base64-encoded-image>",
        "is_default":   true,
        "p_twitch_by_default": false,
        "p_kick_by_default":   false
      },
      {
        "profile_id":   "uuid-2",
        "profile_name": "Tech Reviews",
        "avatar":       null,
        "is_default":   false,
        "p_twitch_by_default": true,
        "p_kick_by_default":   false
      }
    ]
  }
}
```

### Success — no profiles yet
```json
{
  "status":  true,
  "message": "Profiles fetched successfully",
  "data": {
    "profiles": []
  }
}
```

### Error
```json
{ "status": false, "message": "<reason>" }
```

---

## Response Field Notes

| Field | Notes |
|---|---|
| `profile_id` | Pass this to all subsequent API calls (create_event, update_profile, etc.) |
| `profile_name` | Display name shown on the profile card |
| `avatar` | Nullable — show placeholder if null |
| `is_default` | Default profile is always first in the array |
| `p_twitch_by_default` | Whether Twitch is enabled by default for this profile |
| `p_kick_by_default` | Whether Kick is enabled by default for this profile |
| `profiles` | Always array, `[]` if no active profiles |

---

## Error Cases

| Message | Cause |
|---|---|
| `User ID is required` | `p_user_id` is null |
| `User not found` | No user with that ID |
| `Something went wrong` | Unhandled exception |

---

## When to Use This vs `get_profiles_by_userid`

| | `get_user_profiles` | `get_profiles_by_userid` |
|---|---|---|
| **Use case** | Post-login profile picker | Profile management screen |
| **Fields returned** | profile_id, profile_name, avatar, is_default, p_twitch_by_default, p_kick_by_default | Full profile with platforms, tags, followers |
| **Status filter** | `active` only | All statuses |
| **Speed** | Fast — single table, 6 fields | Heavier — 4 tables, nested subqueries |

---

## Related

- [`get_profiles_by_userid`](get_profiles_by_userid.md) — full profile data for management screen
- [`create_profile`](create_profile.md) — create a new profile
- [`creator_profiles` table](../../database/tables/05_creator_profiles.md)
