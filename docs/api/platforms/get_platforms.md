# SP: `get_platforms`

**Endpoint:** `POST /rpc/get_platforms`
**Group:** Platforms
**SQL:** [`functions/platforms/get_platforms.md`](../../../functions/platforms/get_platforms.md)

---

## Overview

Returns list of all available platforms (YouTube, Twitch, Kick, Rumble) with platform ID, name, and logo URL. Used for platform selection in UI, profile setup, and event creation.

---

## Parameters

None — this is a simple fetch with no parameters.

---

## Request Example

```json
{}
```

---

## Response

### Success
```json
{
  "status": true,
  "message": "Platforms fetched successfully",
  "data": {
    "platforms": [
      {
        "plat_id": 1,
        "plat_name": "YouTube",
        "logo_url": "https://vzieacbdhrandechlljw.supabase.co/storage/v1/object/public/website_logos/youtube.png"
      },
      {
        "plat_id": 2,
        "plat_name": "Twitch",
        "logo_url": "https://vzieacbdhrandechlljw.supabase.co/storage/v1/object/public/website_logos/twitch.png"
      },
      {
        "plat_id": 3,
        "plat_name": "Kick",
        "logo_url": "https://vzieacbdhrandechlljw.supabase.co/storage/v1/object/public/website_logos/kick.png"
      },
      {
        "plat_id": 4,
        "plat_name": "Rumble",
        "logo_url": "https://vzieacbdhrandechlljw.supabase.co/storage/v1/object/public/website_logos/rumble.png"
      }
    ]
  }
}
```

### Error
```json
{
  "status": false,
  "message": "Something went wrong",
  "error": "<sqlerrm>"
}
```

---

## Response Fields

| Field | Notes |
|---|---|
| `platforms` | Array of platform objects, sorted by plat_id (always array, never null) |
| `plat_id` | Platform ID (1=YouTube, 2=Twitch, 3=Kick, 4=Rumble) |
| `plat_name` | Platform display name |
| `logo_url` | URL to platform logo image from Supabase storage |

---

## UI Usage

**Platform Selector Dropdown:**
```
Call get_platforms() on screen load
Display each platform as an option:
  - Icon: logo_url image
  - Label: plat_name
  - Value: plat_id
```

**Profile Platform Setup:**
```
User selects platform from list returned by get_platforms()
Pass selected plat_id to event creation or profile setup APIs
```

---

## Related

- [`platforms` table](../../database/tables/05_platforms.md)
- [`create_event`](../events/create_event.md) — uses platform selection
- [`update_profile`](../profiles/update_profile.md) — links platforms to profile
