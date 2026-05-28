# SP: `search_collaborator_profiles` (v1, v2, v2.1)

**Latest Endpoint:** `POST /rpc/search_collaborator_profiles_v2_1`
**Previous Endpoint:** `POST /rpc/search_collaborator_profiles_v2`
**Deprecated Endpoint:** `POST /rpc/search_collaborator_profiles`
**Group:** Search
**SQL:** [`functions/search/search_collaborator_profiles.md`](../../../functions/search/search_collaborator_profiles.md)
**Tables read:** `creator_profiles` · `creator_platform_accounts` · `platforms` · `event_collaborators`

---

## Overview

Searches active creator profiles for use in the collaborator picker during event creation or the invite flow.

- Always excludes `p_exclude_profile_id` (the profile creating or managing the event — can never collaborate with itself).
- If `p_event_id` is provided, also excludes profiles that already have a pending or accepted (non-deleted) invite for that event, so already-invited profiles do not appear in results.

Use `search_profiles` for general profile search. Use this SP only for the collaborator picker.

---

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `p_keyword` | text | ✅ | — | Search term (min 2 characters). Matched against `profile_name` and `bio` |
| `p_exclude_profile_id` | uuid | ✅ | — | The creating/inviting profile's ID — always excluded from results |
| `p_event_id` | uuid | ❌ | null | If provided, additionally excludes profiles already invited (pending/accepted) to this event |
| `p_limit` | int | ❌ | 20 | Max number of results to return |

---

## Request Examples

### During event creation (no event yet)
```json
{
  "p_keyword":            "james",
  "p_exclude_profile_id": "creating-profile-uuid"
}
```

### After event created (invite more collaborators)
```json
{
  "p_keyword":            "james",
  "p_exclude_profile_id": "creating-profile-uuid",
  "p_event_id":           "event-uuid"
}
```

---

## Response

### Success — profiles found
```json
{
  "status":  true,
  "message": "Profiles fetched successfully",
  "data": [
    {
      "profile_id":   "uuid...",
      "profile_name": "JamesStreams",
      "avatar":       "https://...",
      "bio":          "Gaming creator",
      "platforms": [
        { "platform_id": 1, "platform_name": "YouTube", "logo_url": "https://..." }
      ],
      "match_score": 0.85
    }
  ]
}
```

### Success — no profiles found
```json
{
  "status":  true,
  "message": "No profiles found",
  "data":    []
}
```

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
|---------|-------|
| `Search keyword is required` | `p_keyword` is null or empty |
| `Search keyword must be at least 2 characters` | Keyword shorter than 2 characters |
| `p_exclude_profile_id is required` | `p_exclude_profile_id` is null |
| `Something went wrong` | Unhandled DB exception — `error` field contains `SQLERRM` |

---

## Logic Flow

```
1. Validate p_keyword (non-null, >= 2 chars)
2. Validate p_exclude_profile_id (non-null)
3. Query creator_profiles WHERE:
   ├── status = 'active'
   ├── id != p_exclude_profile_id
   ├── If p_event_id provided:
   │   └── id NOT IN (pending/accepted non-deleted invites for that event)
   └── profile_name or bio matches keyword (ILIKE or word_similarity > 0.3)
4. Order by match_score DESC, LIMIT p_limit
5. Return profiles with platform list
```

---

## Related

- [`invite_collaborator`](../events/invite_collaborator.md) — send invite after selecting a profile
- [`search_profiles`](search_profiles.md) — general profile search (no collaborator exclusion logic)
- [`create_event`](../events/create_event.md) — bundle invites at creation via `p_collaborator_ids`
- [`event_collaborators` table](../../database/tables/15_event_collaborators.md)
