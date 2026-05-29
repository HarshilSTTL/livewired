# SP: `search_profiles` (v1, v2, v2.1)

**Latest Endpoint:** `POST /rpc/search_profiles_v2_1`
**Previous Endpoint:** `POST /rpc/search_profiles_v2`
**Deprecated Endpoint:** `POST /rpc/search_profiles`
**Group:** Search
**Requires:** `pg_trgm` extension
**Description:** Elastic/fuzzy search on creator profiles. Matches against `profile_name` and `bio` using both ILIKE partial matching and `word_similarity` fuzzy matching. Results ranked by match score. Uses `SECURITY DEFINER`.

### Version Comparison

| Version | Endpoint | Ordering | Features |
|---------|----------|----------|----------|
| **v2.1** (Current) | `/rpc/search_profiles_v2_1` | User preferences | All 3 groups, preference ordering, type field |
| **v2** | `/rpc/search_profiles_v2` | ID-based (1-4) | Main platforms only (1-4) |
| **v1** (Deprecated) | `/rpc/search_profiles` | Database order | All platforms |

### What's New in v2.1?

- **All 3 link groups:** Returns platforms (1-4) → additional links (5+) → custom links separately
- **Type identifier:** Each link has `type` field: "platform", "additional_link", or "custom_link"
- **Respects user preferences:** Links ordered by `profile_link_preferences` table for each result
- **Separate fields:** Easier for UI to handle each group differently
- **Fallback ordering:** If no preferences set, falls back to platform ID ordering

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| p_keyword | text | Yes | — | Search keyword (min 2 characters) |
| p_limit | int | No | 20 | Max results to return |

---

## Request Example

```json
{
  "p_keyword": "radhe",
  "p_limit": 100
}
```

---

## Search Behavior

| Technique | Applied To | Detail |
|-----------|-----------|--------|
| ILIKE | profile_name, bio | `'%keyword%'` partial match |
| word_similarity | profile_name, bio | Fuzzy match threshold `> 0.3` |

- `bio` is wrapped in `coalesce(cp.bio, '')` to handle nulls safely
- Results ranked by `GREATEST(word_similarity(keyword, profile_name), word_similarity(keyword, bio)) DESC`
- Only active creator profiles (`cp.status = 'active'`) are searched
- All 3 link groups are returned (platforms 1-4, additional links 5+, custom links)

---

## Response

### Success (v2.1)
```json
{
  "status": true,
  "message": "Profiles fetched successfully",
  "data": [
    {
      "profile_id": "uuid",
      "profile_name": "Radhe Gaming",
      "avatar": null,
      "bio": "I stream daily",
      "followers": 320,
      "platforms": [
        { "platform_id": 1, "type": "platform", "platform_name": "YouTube", "logo_url": "url or null" },
        { "platform_id": 2, "type": "platform", "platform_name": "Twitch", "logo_url": "url or null" }
      ],
      "additional_links": [
        { "platform_id": 5, "type": "additional_link", "platform_name": "Patreon", "logo_url": "url or null" }
      ],
      "custom_links": [
        { "platform_id": null, "type": "custom_link", "platform_name": "My Website", "logo_url": null }
      ],
      "match_score": 0.9
    }
  ]
}
```

### Success — No results
```json
{ "status": true, "message": "No profiles found", "data": [] }
```

### Fail — Keyword missing
```json
{ "status": false, "message": "Search keyword is required" }
```

### Fail — Keyword too short
```json
{ "status": false, "message": "Search keyword must be at least 2 characters" }
```

### Fail — Server error
```json
{ "status": false, "message": "Something went wrong", "error": "<sqlerrm>" }
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| p_keyword null or empty | `"Search keyword is required"` |
| p_keyword length < 2 | `"Search keyword must be at least 2 characters"` |
| No matching profiles | `status: true, "No profiles found", data: []` |
| DB/runtime exception | `"Something went wrong"` + sqlerrm |

---

## Logic Flow

1. Validate keyword not null/empty
2. Validate keyword length ≥ 2
3. `v_keyword := trim(p_keyword)`
4. SELECT with scoring: `GREATEST(word_similarity(keyword, profile_name), word_similarity(keyword, bio))`
5. WHERE: ILIKE OR word_similarity > 0.3 on profile_name and bio
6. Subquery for `followers`: CASE WHEN show_followers = true → COUNT(is_active=true) ELSE null END
7. Subqueries for `platforms`, `additional_links`, `custom_links` — each group ordered by preferences with fallback to ID order
8. Add `type` field to each link: "platform", "additional_link", or "custom_link"
9. ORDER BY score DESC — LIMIT p_limit
10. If NULL → return empty array
11. Return results

---

## Link Type Field Values

| Type Value | Description | Source |
|---|---|---|
| `"platform"` | Main streaming platforms (YouTube, Twitch, Kick, Rumble) | Platform IDs 1-4 |
| `"additional_link"` | Additional platform links (Patreon, Discord, etc.) | Platform IDs 5+ |
| `"custom_link"` | Creator-defined custom links | profile_custom_links table |

---

## Differences vs `search_events`

| Feature | `search_profiles` | `search_events` |
|---------|------------------|----------------|
| Searches on | profile_name, bio | title, description |
| Link groups | platforms, additional_links, custom_links | n/a |
| Secondary sort | score DESC only | score DESC, event_date ASC |
| `bio` null handling | `coalesce(bio, '')` | n/a |

---

## Notes

- `match_score` is `0.0 – 1.0` — higher = better match
- `avatar` and `bio` are nullable — handle in UI
- `platforms` always an array (never null) via `coalesce(..., '[]'::json)`
  - Returns main streaming platforms (IDs 1-4: YouTube, Twitch, Kick, Rumble) ordered by user preferences
  - Type field = "platform"
- `additional_links` always an array (never null)
  - Returns additional platform links (IDs 5+: Patreon, Discord, etc.) ordered by user preferences
  - Type field = "additional_link"
- `custom_links` always an array (never null)
  - Returns creator-defined custom links ordered by user preferences
  - Type field = "custom_link"
- `followers` is `null` when the creator has `show_followers = false` — handle in UI
- `pg_trgm` extension must be enabled: see `schema/extensions/pg_trgm.md`
- Trigram indexes on `creator_profiles.profile_name`, `.bio` improve performance: see `schema/indexes/trigram_indexes.md`

---

## SQL Reference

See [`functions/search/search_profiles.md`](../../../functions/search/search_profiles.md)
