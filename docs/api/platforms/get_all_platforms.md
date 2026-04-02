# SP: `get_all_platforms`

**Endpoint:** `GET /rpc/get_all_platforms`
**Group:** Platform
**Description:** Returns all active streaming platforms. Called during onboarding so the user can select which platforms they use. Uses `SECURITY DEFINER`.

## App Screen

![Choose Platforms Screen](../../assets/screenshots/onboarding_platforms.png)

> Onboarding step: user selects which platforms they use. Each card shows the platform logo (logo_url). Selection is submitted via `submit_platform`.
> Save screenshot as: `docs/assets/screenshots/onboarding_platforms.png`

---

## Parameters

None — no input required.

---

## Request Example

```http
GET /rest/v1/rpc/get_all_platforms
apikey: <your-api-key>
Authorization: Bearer <token>
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Platforms fetched successfully",
  "data": [
    {
      "plat_id": 1,
      "plat_name": "YouTube",
      "logo_url": "https://...",
      "is_active": 1,
      "created_at": "2026-01-01T00:00:00+00:00"
    },
    {
      "plat_id": 2,
      "plat_name": "Twitch",
      "logo_url": null,
      "is_active": 1,
      "created_at": "2026-01-01T00:00:00+00:00"
    }
  ]
}
```

> ℹ️ `logo_url` can be `null` — handle gracefully in the UI.

### Fail — No active platforms in DB
```json
{
  "status": false,
  "message": "No platforms found",
  "data": []
}
```

### Fail — Server error
```json
{
  "status": false,
  "message": "Something went wrong while fetching platforms",
  "error": "<sqlerrm>"
}
```

---

## Error Cases

| Scenario | Response |
|----------|----------|
| No rows with `is_active = 1` | `status: false, "No platforms found"` |
| DB/runtime exception | `status: false` + sqlerrm |

---

## Logic Flow

1. `SELECT json_agg(...)` FROM `platforms` WHERE `is_active = 1`
2. If result is NULL (no active platforms) → return error with empty array
3. Return aggregated JSON array on success
4. EXCEPTION block catches all other errors

---

## Notes

- Filters by `is_active = 1` — inactive platforms (`is_active = 0`) are excluded
- `logo_url` is **nullable** — UI must handle `null` value
- No pagination — returns all active platforms in one call
- Used in onboarding flow before `submit_platform`

---

## SQL Reference

See [`functions/platforms/get_all_platforms.md`](../../../functions/platforms/get_all_platforms.md)
