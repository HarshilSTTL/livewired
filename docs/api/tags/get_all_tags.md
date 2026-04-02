# SP: `get_all_tags`

**Endpoint:** `GET /rpc/get_all_tags`
**Group:** Tags
**Description:** Returns all interest/category tags. Called during onboarding so the user can select their interests. Uses `SECURITY DEFINER`.

## App Screen

![Interests Screen](../../assets/screenshots/onboarding_interests.png)

> Onboarding step: "What are you into?" — user picks interest categories (Gaming, Tech, Sports, etc.). Each button is a tag_name. Selected tags shown with blue border. Selection submitted via `submit_tags`.
> Save screenshot as: `docs/assets/screenshots/onboarding_interests.png`

---

## Parameters

None — no input required.

---

## Request Example

```http
GET /rest/v1/rpc/get_all_tags
apikey: <your-api-key>
Authorization: Bearer <token>
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Tags fetched successfully",
  "data": [
    { "tag_id": 1, "tag_name": "Gaming" },
    { "tag_id": 2, "tag_name": "Tech" },
    { "tag_id": 3, "tag_name": "Music" },
    { "tag_id": 4, "tag_name": "Sports" },
    { "tag_id": 5, "tag_name": "Travel" },
    { "tag_id": 6, "tag_name": "Finance" },
    { "tag_id": 7, "tag_name": "Cooking" },
    { "tag_id": 8, "tag_name": "Health" },
    { "tag_id": 9, "tag_name": "News" },
    { "tag_id": 10, "tag_name": "Science" },
    { "tag_id": 11, "tag_name": "Entertainment" },
    { "tag_id": 12, "tag_name": "Politics" },
    { "tag_id": 13, "tag_name": "Automotive" }
  ]
}
```

> ℹ️ `tag_name` can be `null` — handle gracefully in the UI.

### Fail — No tags in DB
```json
{
  "status": false,
  "message": "No tags found",
  "data": []
}
```

### Fail — Server error
```json
{
  "status": false,
  "message": "Something went wrong while fetching tags",
  "error": "<sqlerrm>"
}
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| Tags table is empty | `status: false, "No tags found"` |
| DB/runtime exception | `status: false` + sqlerrm |

---

## Logic Flow

1. `SELECT json_agg(...)` FROM `tags` — no filter (returns ALL tags)
2. If result is NULL (table empty) → return error with empty array
3. Return aggregated JSON array on success
4. EXCEPTION block catches all other errors

---

## Differences vs `get_all_platforms`

| Feature         | `get_all_platforms`                                 | `get_all_tags`          |
| --------------- | --------------------------------------------------- | ----------------------- |
| Filter          | `WHERE is_active = 1`                               | No filter — returns all |
| Fields returned | plat_id, plat_name, logo_url, is_active, created_at | tag_id, tag_name only   |
| Nullable field  | logo_url                                            | tag_name                |

---

## Notes

- No filter applied — **all tags** are returned regardless of any status
- No pagination — returns all 13 tags in one call
- `tag_name` is **nullable** — UI must handle `null` value
- Used in onboarding flow before `submit_tags`

---

## SQL Reference

See [`functions/tags/get_all_tags.md`](../../../functions/tags/get_all_tags.md)
