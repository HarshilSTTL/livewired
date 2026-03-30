# SP: `search_events`

**Endpoint:** `POST /rpc/search_events`
**Group:** Search
**Requires:** `pg_trgm` extension
**Description:** Elastic/fuzzy search on events. Matches against `title` and `description` using both ILIKE partial matching and `word_similarity` fuzzy matching. Results ranked by match score. Uses `SECURITY DEFINER`.

---

## Parameters

| Param | Type | Required | Default | Notes |
|-------|------|----------|---------|-------|
| p_keyword | text | Yes | — | Search keyword (min 2 characters) |
| p_limit | int | No | 20 | Max results to return |

### Request Example
```json
{
  "p_keyword": "yoga",
  "p_limit": 100
}
```

---

## Search Behavior

| Technique | Applied To | Detail |
|-----------|-----------|--------|
| ILIKE | title, description | `'%keyword%'` partial match |
| word_similarity | title, description | Fuzzy match threshold `> 0.3` |

- `description` is wrapped in `coalesce(e.description, '')` to handle nulls safely
- Results ranked by `GREATEST(word_similarity(keyword, title), word_similarity(keyword, description)) DESC`
- Secondary sort: `event_date ASC`
- Only events from active creator profiles (`cp.status = 'active'`) are searched

---

## Response

### Success
```json
{
  "status": true,
  "message": "Events fetched successfully",
  "data": [
    {
      "event_id": "uuid",
      "event_title": "Morning Yoga Session",
      "description": "Daily yoga for beginners",
      "event_date": "2026-04-01",
      "event_time": "07:00:00",
      "livestream": true,
      "is_recurring": true,
      "profile_name": "Yoga With Priya",
      "username": "yogapriya",
      "avatar_url": "url or null",
      "followers": 320,
      "streaming": [
        {
          "platform_id": 1,
          "platform_name": "YouTube",
          "logo_url": "url or null",
          "streaming_url": "https://youtube.com/live/..."
        }
      ],
      "match_score": 0.85
    }
  ]
}
```

### Success — No results found
```json
{
  "status": true,
  "message": "No events found",
  "data": []
}
```

### Fail — Keyword missing
```json
{
  "status": false,
  "message": "Search keyword is required"
}
```

### Fail — Keyword too short
```json
{
  "status": false,
  "message": "Search keyword must be at least 2 characters"
}
```

### Fail — Server error
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
| p_keyword null or empty | `"Search keyword is required"` |
| p_keyword length < 2 | `"Search keyword must be at least 2 characters"` |
| No matching events | `status: true, "No events found", data: []` |
| DB/runtime exception | `"Something went wrong"` + sqlerrm |

> ℹ️ "No events found" returns `status: true` — it's a valid empty result, not an error.

---

## Logic Flow

1. Validate keyword not null/empty
2. Validate keyword length ≥ 2
3. `v_keyword := trim(p_keyword)`
4. SELECT with scoring: `GREATEST(word_similarity(keyword, title), word_similarity(keyword, description))`
5. WHERE: ILIKE OR word_similarity > 0.3 on title/description
6. JOIN `creator_profiles` (active only) + subquery for streaming platforms
7. ORDER BY score DESC, event_date ASC — LIMIT p_limit
8. If NULL result → return empty array
9. Return results

---

## Notes

- `match_score` is `0.0 – 1.0` — higher = better match
- `description` nullable — handled with `coalesce(e.description, '')` in fuzzy match
- `streaming` always an array (never null) via `coalesce(..., '[]'::json)`
- `ep.platform_id::bigint` cast required due to int4/int8 type mismatch
- `pg_trgm` extension must be enabled: see `schema/extensions/pg_trgm.sql`
- Trigram indexes on `event_mst.title` and `event_mst.description` improve performance: see `schema/indexes/trigram_indexes.sql`

---

## SQL Reference

See [`functions/search/search_events.sql`](../../../functions/search/search_events.sql)
