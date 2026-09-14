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

-- Additional link icons (curated, non-streaming), appended after existing max plat_id
INSERT INTO public.platforms (plat_id, plat_name, logo_url)
SELECT (SELECT COALESCE(MAX(plat_id), 0) FROM public.platforms) + 1,
       'Fourthwall',
       'https://vzieacbdhrandechlljw.supabase.co/storage/v1/object/public/website_logos/fourthwall.png'
WHERE NOT EXISTS (SELECT 1 FROM public.platforms WHERE plat_name = 'Fourthwall');

INSERT INTO public.platforms (plat_id, plat_name, logo_url)
SELECT (SELECT COALESCE(MAX(plat_id), 0) FROM public.platforms) + 1,
       'MetaGamerScore',
       'https://vzieacbdhrandechlljw.supabase.co/storage/v1/object/public/website_logos/mgs.png'
WHERE NOT EXISTS (SELECT 1 FROM public.platforms WHERE plat_name = 'MetaGamerScore');
```
