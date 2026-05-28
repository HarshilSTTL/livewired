# Migration: Create `profile_link_preferences` Table

**Date:** 2026-05-28
**Purpose:** Store drag-drop reordering for platforms, additional links, and custom links per profile

## SQL

```sql
-- Create profile_link_preferences table
CREATE TABLE IF NOT EXISTS public.profile_link_preferences (
    id                        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id                uuid UNIQUE NOT NULL REFERENCES public.creator_profiles(id) ON DELETE CASCADE,
    platform_ids_order        int[] DEFAULT ARRAY[]::int[],      -- [3, 4, 2, 1]
    additional_ids_order      int[] DEFAULT ARRAY[]::int[],      -- [7, 5, 6, 8, 9]
    custom_ids_order          uuid[] DEFAULT ARRAY[]::uuid[]     -- [10, 8, 9]
);

-- Create index for fast lookup
CREATE INDEX IF NOT EXISTS idx_profile_link_prefs ON public.profile_link_preferences(profile_id);
```

## Rollback

```sql
DROP INDEX IF EXISTS public.idx_profile_link_prefs;
DROP TABLE IF EXISTS public.profile_link_preferences;
```

## Example Data

```json
{
  "id": "pref-001",
  "profile_id": "abc-123-def",
  "platform_ids_order": [3, 4, 2, 1],
  "additional_ids_order": [7, 5, 6, 8],
  "custom_ids_order": ["uuid-10", "uuid-8", "uuid-9"]
}
```

## Notes

- Each profile has ONE row
- Arrays store IDs in desired display order
- Empty arrays = no links of that type
- On DELETE cascade: if profile is deleted, preferences are deleted too
