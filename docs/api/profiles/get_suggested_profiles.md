# SP: `get_suggested_profiles`

**Endpoint:** `POST /rpc/get_suggested_profiles`
**Group:** Profile
**Description:** Returns a ranked list of creator profiles to follow, personalised to the user's selected platforms and interests. Used in the onboarding suggestion screen — after the user completes `submit_platform` and `submit_tags`, this SP scores every eligible creator by how many of their platforms and tags overlap with the user's preferences.

## App Screen

![Suggested Profiles — Onboarding](../../assets/screenshots/onboarding_suggestions.png)

> Onboarding step after choosing platforms and interests. Shows ranked creator cards with avatar, name, followers, platform icons, and a Follow button.
> Save screenshot as: `docs/assets/screenshots/onboarding_suggestions.png`

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| p_user_id | uuid | Yes | — | Used to load preferences and exclude own/already-followed profiles |
| p_limit | int | No | 20 | Page size — clamped to max 100 |
| p_offset | int | No | 0 | Rows to skip — use for pagination |

---

## Onboarding Flow

```
signup / login
     ↓
submit_platform  — user picks platforms (YouTube, Twitch, Kick…)
     ↓
submit_tags      — user picks interests (Gaming, Tech, Music…)
     ↓
get_suggested_profiles  ← THIS SP
     ↓
follow_creator   — user taps Follow on suggestion cards
```

---

## Request Example

```json
{
  "p_user_id": "uuid..."
}
```

---

## Response

### Success
```json
{
  "status": true,
  "data": {
    "total": 42,
    "limit": 20,
    "offset": 0,
    "profiles": [
      {
        "profile_id": "uuid...",
        "profile_name": "Harshil Gaming",
        "avatar": "base64...",
        "followers": 12400,
        "platforms": [
          { "platform_id": 1, "logo_url": "https://..." },
          { "platform_id": 2, "logo_url": "https://..." }
        ],
        "tags": [
          { "tag_id": 1, "tag_name": "Gaming" },
          { "tag_id": 2, "tag_name": "Tech" }
        ],
        "match_score": 4
      }
    ]
  }
}
```

### Success — no suggestions
```json
{
  "status": true,
  "data": {
    "total": 0,
    "limit": 20,
    "offset": 0,
    "profiles": []
  }
}
```

### Fail — missing user_id
```json
{
  "status": false,
  "message": "p_user_id is required"
}
```

### Fail — user not found
```json
{
  "status": false,
  "message": "User not found"
}
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| p_user_id is null | `"p_user_id is required"` |
| user not found in users table | `"User not found"` |
| DB / runtime exception | `"Something went wrong"` + sqlerrm |

---

## Scoring Logic

`match_score = platform_matches + tag_matches`

| Match type | How |
|---|---|
| Platform match | Creator has a platform in `creator_platform_accounts` that also appears in user's `user_preferred_platforms` |
| Tag match | Creator has a tag in `profile_tags` that also appears in user's `user_interests` |

**Example:**
- User selected: YouTube, Twitch · Gaming, Tech
- Creator A has: YouTube, Kick · Gaming, Music → score = **2** (1 platform + 1 tag)
- Creator B has: YouTube, Twitch · Gaming, Tech → score = **4** (2 platform + 2 tag)
- Creator C has: Rumble · Sports → score = **0**

Results ordered: B (4) → A (2) → C (0, tie-broken by followers DESC)

---

## Behaviour Notes

| Rule | Detail |
|------|--------|
| Already followed | Excluded — profiles where `follows.is_active = true` for this user are not returned |
| Own profiles | Excluded — `creator_profiles.user_id != p_user_id` |
| No preferences set | User skipped platform/tag steps → all scores = 0 → ordered by followers DESC |
| `followers` | Respects `show_followers` flag — returns count if `true`, `null` if `false` |
| Score = 0 profiles | Still returned — fills the list when preferences are sparse |
| `platforms` | Always an array — `[]` if none |
| `tags` | Always an array — `[]` if none |
| `match_score` | Integer — use in UI to show "X matches" badge if needed |
| `p_limit` max | Clamped to 100 |

---

## Pagination

```
total pages  = ceil(total / limit)
has_next     = offset + limit < total
next_offset  = offset + limit
```

---

## Tables Read

| Table | How |
|-------|-----|
| `users` | Existence check |
| `creator_profiles` | Main SELECT + COUNT |
| `follows` | Exclude already-followed; ORDER BY followers |
| `user_preferred_platforms` | User's chosen platforms for scoring |
| `user_interests` | User's chosen tags for scoring |
| `creator_platform_accounts` | Creator's platforms — matched + returned |
| `platforms` | JOIN for logo_url |
| `profile_tags` | Creator's tags — matched + returned |
| `tags` | JOIN for tag_name |

---

## SQL Reference

See [`functions/profiles/get_suggested_profiles.md`](../../../functions/profiles/get_suggested_profiles.md)
