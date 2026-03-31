# `03_platforms`

```sql
-- Table: platforms
-- Purpose: Master list of all supported live streaming platforms
-- Doc: docs/database/tables/03_platforms.md

CREATE TABLE IF NOT EXISTS public.platforms (
    plat_id    int8        PRIMARY KEY,
    created_at timestamptz DEFAULT now(),
    plat_name  text,
    logo_url   text        NULL,   -- nullable: platform may not have a logo yet
    is_active  int2        DEFAULT 1  -- 1 = active, 0 = inactive
);

-- Seed data
INSERT INTO public.platforms (plat_id, plat_name) VALUES
    (1, 'YouTube'),
    (2, 'Twitch'),
    (3, 'Kick'),
    (4, 'Rumble')
ON CONFLICT (plat_id) DO NOTHING;
```
