# `12_user_interests`

```sql
-- Table: user_interests
-- Purpose: User's selected interest/category tags from onboarding
-- Doc: docs/database/tables/12_user_interests.md

CREATE TABLE IF NOT EXISTS public.user_interests (
    id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid        REFERENCES public.users(id),
    tag_id     int8        REFERENCES public.tags(tag_id),
    created_at timestamptz DEFAULT now()
);

-- FK name: user_interests_user_id_fkey → user_id references public.users.id
-- FK name: user_interests_tag_id_fkey  → tag_id  references public.tags.tag_id

-- Note: submit_tags does DELETE + INSERT (replace-all), not append
```
