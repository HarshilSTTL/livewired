# SP: `search_profiles`

**Endpoint:** `POST /rpc/search_profiles`
**Group:** Search
**Requires:** `pg_trgm` extension
**Description:** Elastic/fuzzy search on creator profiles. Matches against `profile_name`, `username`, and `bio` using both ILIKE partial matching and `word_similarity` fuzzy matching. Results ranked by match score. Uses `SECURITY DEFINER`.

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
| ILIKE | profile_name, username, bio | `'%keyword%'` partial match |
| word_similarity | profile_name, username, bio | Fuzzy match threshold `> 0.3` |

- `bio` is wrapped in `coalesce(cp.bio, '')` to handle nulls safely
- Results ranked by `GREATEST(word_similarity(keyword, profile_name), word_similarity(keyword, username), word_similarity(keyword, bio)) DESC`
- Only active creator profiles (`cp.status = 'active'`) are searched

---

## Response

### Success
```json
{
  "status": true,
  "message": "Profiles fetched successfully",
  "data": [
    {
      "profile_id": "uuid",
      "profile_name": "Radhe Gaming",
      "username": "radhe_gaming",
      "avatar": null,
      "bio": "I stream daily",
      "followers": 320,
      "platforms": [
        { "platform_id": 1, "platform_name": "YouTube", "logo_url": "url or null" }
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
4. SELECT with scoring: `GREATEST(word_similarity(keyword, profile_name), word_similarity(keyword, username), word_similarity(keyword, bio))`
5. WHERE: ILIKE OR word_similarity > 0.3 on all three fields
6. Subquery for live `followers` (is_active=true) + `platforms` array per profile
7. ORDER BY score DESC — LIMIT p_limit
8. If NULL → return empty array
9. Return results

---

## Differences vs `search_events`

| Feature | `search_profiles` | `search_events` |
|---------|------------------|----------------|
| Searches on | profile_name, username, bio | title, description |
| Platforms format | `{platform_id, platform_name, logo_url}` objects | Same |
| Secondary sort | score DESC only | score DESC, event_date ASC |
| `bio` null handling | `coalesce(bio, '')` | n/a |

---

## Notes

- `match_score` is `0.0 – 1.0` — higher = better match
- `avatar` and `bio` are nullable — handle in UI
- `platforms` always an array (never null) via `coalesce(..., '[]'::json)`
- `pg_trgm` extension must be enabled: see `schema/extensions/pg_trgm.md`
- Trigram indexes on `creator_profiles.profile_name`, `.username`, `.bio` improve performance: see `schema/indexes/trigram_indexes.md`

---

## SQL Reference

See [`functions/search/search_profiles.md`](../../../functions/search/search_profiles.md)
