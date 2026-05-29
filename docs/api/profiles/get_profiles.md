# SP: `get_profiles` (v1, v2, v2.1)

**Latest Endpoint:** `POST /rpc/get_profiles_v2_1`
**Previous Endpoint:** `POST /rpc/get_profiles_v2`
**Deprecated Endpoint:** `POST /rpc/get_profiles`
**Group:** Profile
**Description:** Dashboard profile browser with optional search, fuzzy matching, and pagination. Returns all active creator profiles by default. When a keyword is provided, results are filtered by profile name using both ILIKE and `word_similarity` (fuzzy match), ordered by relevance. Designed for the dashboard search screen — distinct from `search_profiles` which requires a keyword.
**Requires:** `pg_trgm` extension

---

## Version Comparison

| Version | Endpoint | Ordering | Features |
|---------|----------|----------|----------|
| **v2.1** (Current) | `/rpc/get_profiles_v2_1` | User preferences | All 3 groups, preference ordering, type field |
| **v2** | `/rpc/get_profiles_v2` | ID-based (1-4) | Main platforms only (1-4) |
| **v1** (Deprecated) | `/rpc/get_profiles` | Database order | All platforms |

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| p_keyword | text | No | null | Filter by profile name — if null or empty, all profiles returned |
| p_limit | int | No | 20 | Page size — clamped to max 100 |
| p_offset | int | No | 0 | Number of rows to skip — use for pagination |

---

## Request Examples

### Load all profiles (dashboard open / search button clicked with no input)
```json
{}
```

### Filter by name
```json
{
  "p_keyword": "harshil"
}
```

### Paginate (page 3 with 20 per page)
```json
{
  "p_limit": 20,
  "p_offset": 40
}
```

### Filter + paginate
```json
{
  "p_keyword": "gaming",
  "p_limit": 10,
  "p_offset": 0
}
```

---

## Response

### Success (v2.1)
```json
{
  "status": true,
  "data": {
    "total": 84,
    "limit": 20,
    "offset": 0,
    "profiles": [
      {
        "profile_id": "uuid...",
        "profile_name": "Harshil Gaming",
        "avatar": "base64...",
        "followers": 1240,
        "platforms": [
          {
            "platform_id": 1,
            "type": "platform",
            "logo_url": "https://..."
          },
          {
            "platform_id": 2,
            "type": "platform",
            "logo_url": "https://..."
          }
        ],
        "additional_links": [
          {
            "platform_id": 5,
            "type": "additional_link",
            "logo_url": "https://..."
          }
        ],
        "custom_links": [
          {
            "platform_id": null,
            "type": "custom_link",
            "logo_url": null
          }
        ],
        "tags": [
          { "tag_id": 1, "tag_name": "Gaming" },
          { "tag_id": 2, "tag_name": "Tech" }
        ],
        "created_at": "2026-03-30T18:45:00Z"
      }
    ]
  }
}
```

### Success — no results
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

### Fail — server error
```json
{
  "status": false,
  "message": "Something went wrong",
  "error": "<sqlerrm>"
}
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| DB / runtime exception | `"Something went wrong"` + sqlerrm |

> There are no validation errors — all params are optional with safe defaults. Invalid `p_limit` / `p_offset` values are silently clamped.

---

## Pagination

Use `total`, `limit`, and `offset` to drive pagination in the UI:

```
total pages  = ceil(total / limit)
current page = floor(offset / limit) + 1
has_next     = offset + limit < total
```

**Example — 84 total, limit 20:**

| Page | offset |
|------|--------|
| 1 | 0 |
| 2 | 20 |
| 3 | 40 |
| 4 | 60 |
| 5 | 80 — only 4 results |

---

## Link Type Field Values

| Type Value | Description | Source |
|---|---|---|
| `"platform"` | Main streaming platforms (YouTube, Twitch, Kick, Rumble) | Platform IDs 1-4 |
| `"additional_link"` | Additional platform links (Patreon, Discord, etc.) | Platform IDs 5+ |
| `"custom_link"` | Creator-defined custom links | profile_custom_links table |

---

## Behaviour Notes

| Rule | Detail |
|------|--------|
| No keyword | All active profiles returned (paginated), ordered by `created_at DESC` |
| Keyword provided | Matches on `profile_name` via ILIKE **and** `word_similarity > 0.3` (fuzzy) |
| Keyword ordering | Results ordered by best fuzzy match score DESC, then `created_at DESC` |
| Typo tolerance | `word_similarity` threshold 0.3 — catches partial matches and common typos |
| `followers` | Respects `show_followers` flag — returns count if `true`, `null` if `false` |
| `platforms` | Array of main streaming platforms (IDs 1-4) ordered by user preferences, always `[]` minimum |
| `additional_links` | Array of additional platform links (IDs 5+) ordered by user preferences, always `[]` minimum |
| `custom_links` | Array of creator-defined custom links ordered by user preferences, always `[]` minimum |
| `p_limit` max | Clamped to 100 — requests above 100 automatically use 100 |

---

## Difference vs `search_profiles`

| | `get_profiles` | `search_profiles` |
|---|---|---|
| Keyword required | No — optional | Yes — min 2 chars |
| No keyword → | Returns all profiles | Error |
| Pagination | Yes (`total`, `limit`, `offset`) | No |
| Fuzzy matching | Yes — `word_similarity` (pg_trgm) | Yes — `word_similarity` (pg_trgm) |
| `match_score` | Not returned | Returned |
| Search scope | `profile_name` | `profile_name`, `bio` |
| Link groups | platforms, additional_links, custom_links | Same |
| Fields returned | profile_id, profile_name, avatar, followers, platforms, additional_links, custom_links, tags | profile_id, profile_name, avatar, bio, followers, platforms, additional_links, custom_links, match_score |
| Use case | Dashboard browse + search | Dedicated search screen |

---

## Logic Flow

1. Normalise `p_keyword` → trim + lowercase; treat empty string as NULL
2. Clamp `p_limit` to 1–100; default 20
3. Clamp `p_offset` to ≥ 0; default 0
4. COUNT matching active profiles → `v_total`
5. SELECT matching profiles with:
   - `platforms` (IDs 1-4) ordered by preferences, type="platform"
   - `additional_links` (IDs 5+) ordered by preferences, type="additional_link"
   - `custom_links` ordered by preferences, type="custom_link"
   - `tags` subquery
6. Order by fuzzy match score DESC (if keyword provided), then `created_at DESC`
7. Apply LIMIT/OFFSET for pagination
8. Return `total`, `limit`, `offset`, `profiles[]`

---

## Tables Read

| Table | How |
|-------|-----|
| `creator_profiles` | Main SELECT + COUNT |
| `follows` | COUNT for followers (when show_followers = true) |
| `creator_platform_accounts` | Subquery per profile |
| `profile_custom_links` | Subquery per profile |
| `platforms` | JOIN for platform logos |
| `profile_tags` | Subquery per profile |
| `tags` | JOIN for tag names |
| `profile_link_preferences` | Subquery for ordering |

---
