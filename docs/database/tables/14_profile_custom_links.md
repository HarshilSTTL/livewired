# Table: `profile_custom_links`

**Purpose:** Stores creator-defined custom platform links (name + URL) per profile. Each entry belongs to a specific creator profile and is visible only to that profile owner — returned alongside global platforms when `get_all_platforms` is called with `p_profile_id`.

**Schema:** [`schema/tables/14_profile_custom_links.md`](../../../schema/tables/14_profile_custom_links.md)

---

## Columns

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| `id` | uuid | NOT NULL | `gen_random_uuid()` | Primary key |
| `profile_id` | uuid | NOT NULL | — | FK → `creator_profiles.id` — owner of this custom link |
| `profile_name` | text | NOT NULL | — | User-defined platform name e.g. `"Amazon"`, `"Cashapp"`, `"Patreon"` |
| `profile_url` | text | NOT NULL | — | Full URL for the link |
| `is_deleted` | boolean | NOT NULL | `false` | Soft delete flag — `true` = deleted |
| `deleted_at` | timestamp | NULL | — | Set to `now()` when `is_deleted` is set to `true` |
| `created_at` | timestamp | NULL | `now()` | Row creation timestamp |
| `updated_at` | timestamp | NULL | `now()` | Last updated timestamp — set on every edit |

---

## Constraints

| Type | Column | References |
|---|---|---|
| PRIMARY KEY | `id` | — |
| FOREIGN KEY (`fk_profile`) | `profile_id` | `public.creator_profiles(id)` ON DELETE CASCADE |

---

## Behaviour Notes

- **Profile-scoped:** Each row belongs to one creator profile (`profile_id`). Different profiles of the same user have independent custom link lists.
- **Soft delete only:** Rows are never hard-deleted. When a user removes a custom link, `is_deleted = true` and `deleted_at = now()`.
- **Visible in `get_all_platforms`:** When `get_all_platforms` is called with `p_profile_id`, active (`is_deleted = false`) rows are returned merged with global platforms. Custom links are identified by `is_custom = true` in the response.
- **No logo:** Custom links have no logo. Frontend should render `profile_name` as text instead of a platform icon.
- **Cascade delete:** If the creator profile is deleted, all its custom links are automatically removed.
- **`updated_at`** must be set to `now()` in any SP that updates a row.

---

## Response shape (in `get_all_platforms`)

```json
{
  "plat_id":      null,
  "custom_id":    "uuid",
  "plat_name":    "Amazon",
  "logo_url":     null,
  "platform_url": "https://amazon.com/storefront/creator",
  "is_custom":    true
}
```

---

## Related

- [`creator_profiles` table](05_creator_profiles.md) — parent table via `profile_id` FK
- `get_all_platforms` SP — returns global platforms + this profile's custom links when `p_profile_id` is passed
- `manage_custom_links` SP *(planned)* — add / edit / soft-delete custom links for a profile
