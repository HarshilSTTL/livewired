# SP: `get_profiles`

**Endpoint:** `POST /rpc/get_profiles`
**Group:** Profile
**Description:** Dashboard profile browser with optional search, fuzzy matching, and pagination. Returns all active creator profiles by default. When a keyword is provided, results are filtered by profile name or username using both ILIKE and `word_similarity` (fuzzy match), ordered by relevance. Designed for the dashboard search screen — distinct from `search_profiles` which requires a keyword.
**Requires:** `pg_trgm` extension

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| p_keyword | text | No | null | Filter by profile name or username — if null or empty, all profiles returned |
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

### Success
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
        "user_id": "uuid...",
        "profile_name": "Harshil Gaming",
        "username": "harshil_gaming",
        "avatar": "base64...",
        "bio": "I stream games daily",
        "status": "active",
        "show_followers": true,
        "followers": 1240,
        "platforms": [
          {
            "platform_id": 1,
            "logo_url": "https://..."
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

## Behaviour Notes

| Rule | Detail |
|------|--------|
| No keyword | All active profiles returned (paginated), ordered by `created_at DESC` |
| Keyword provided | Matches on `profile_name` and `username` via ILIKE **and** `word_similarity > 0.3` (fuzzy) |
| Keyword ordering | Results ordered by best fuzzy match score DESC, then `created_at DESC` |
| Typo tolerance | `word_similarity` threshold 0.3 — catches partial matches and common typos |
| `followers` | Always returned as a live count — no `show_followers` restriction |
| `platforms` | Always an array — `[]` if no platforms linked |
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
| Search scope | `profile_name`, `username` | `profile_name`, `username`, `bio` |
| Fields returned | profile_id, profile_name, avatar, followers, platforms | profile_id, profile_name, username, avatar, bio, followers, platforms, match_score |
| Use case | Dashboard browse + search | Dedicated search screen |

---

## Logic Flow

1. Normalise `p_keyword` → trim + lowercase; treat empty string as NULL
2. Clamp `p_limit` to 1–100; default 20
3. Clamp `p_offset` to ≥ 0; default 0
4. COUNT matching active profiles → `v_total`
5. SELECT matching profiles with platforms + tags subqueries, ordered by `created_at DESC`, with LIMIT/OFFSET
6. Return `total`, `limit`, `offset`, `profiles[]`

---

## Tables Read

| Table | How |
|-------|-----|
| `creator_profiles` | Main SELECT + COUNT |
| `follows` | COUNT for followers (when show_followers = true) |
| `creator_platform_accounts` | Subquery per profile |
| `platforms` | JOIN for platform_name + logo_url |
| `profile_tags` | Subquery per profile |
| `tags` | JOIN for tag_name |

---

## SQL Reference

See [`functions/profiles/get_profiles.md`](../../../functions/profiles/get_profiles.md)
