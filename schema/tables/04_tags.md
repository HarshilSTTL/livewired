# `04_tags`

```sql
-- Table: tags
-- Purpose: Interest/category tags for user personalisation and creator profiles
-- Doc: docs/database/tables/04_tags.md

CREATE TABLE IF NOT EXISTS public.tags (
    tag_id   int8 PRIMARY KEY,
    tag_name text NULL   -- nullable
);

-- Seed data
INSERT INTO public.tags (tag_id, tag_name) VALUES
    (1,  'Gaming'),
    (2,  'Tech'),
    (3,  'Music'),
    (4,  'Sports'),
    (5,  'Travel'),
    (6,  'Finance'),
    (7,  'Cooking'),
    (8,  'Health'),
    (9,  'News'),
    (10, 'Science'),
    (11, 'Entertainment'),
    (12, 'Politics'),
    (13, 'Automotive')
ON CONFLICT (tag_id) DO NOTHING;
```
