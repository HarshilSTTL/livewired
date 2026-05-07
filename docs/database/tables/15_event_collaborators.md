# Table: `event_collaborators`

> Tracks collaborator invites for collaborative events. The event owner invites other active creator profiles. Each invite moves through `pending → accepted | declined`. Soft delete lets the owner remove and later re-invite the same profile.

## Columns

| Column       | Type        | Default           | Nullable | Notes                                                       |
|--------------|-------------|-------------------|----------|-------------------------------------------------------------|
| id           | uuid        | gen_random_uuid() | No       | PRIMARY KEY                                                 |
| event_id     | uuid        | —                 | No       | FK → event_mst.event_id ON DELETE CASCADE                   |
| profile_id   | uuid        | —                 | No       | FK → creator_profiles.id — the invited collaborator         |
| invited_by   | uuid        | —                 | No       | FK → creator_profiles.id — the owner who sent the invite    |
| status       | text        | `'pending'`       | No       | `'pending'` · `'accepted'` · `'declined'`                   |
| invited_at   | timestamptz | now()             | Yes      | When the invite was sent (or re-sent after removal)         |
| responded_at | timestamptz | NULL              | Yes      | Set when collaborator calls `respond_collaborator_invite`   |
| updated_at   | timestamptz | now()             | Yes      | Updated on any status change or soft delete                 |
| is_deleted   | boolean     | false             | No       | Soft delete flag — set by `remove_collaborator`             |
| deleted_at   | timestamptz | NULL              | Yes      | Timestamp of soft delete                                    |

## Indexes

| Index | Columns | Condition | Purpose |
|-------|---------|-----------|---------|
| `uq_event_collaborators_active` | `(event_id, profile_id)` | `WHERE is_deleted = false` | Prevents duplicate active invites. Soft-deleted rows excluded so re-inviting works. |

## Foreign Keys

| Constraint | Column | References | On Delete |
|------------|--------|------------|-----------|
| event_collaborators_event_id_fkey | event_id | `event_mst.event_id` | CASCADE |
| event_collaborators_profile_id_fkey | profile_id | `creator_profiles.id` | CASCADE |
| event_collaborators_invited_by_fkey | invited_by | `creator_profiles.id` | CASCADE |

## Status Flow

```
invite_collaborator        → status = 'pending'
respond_collaborator_invite → status = 'accepted' | 'declined'
remove_collaborator         → is_deleted = true (soft delete)
invite_collaborator (again) → reactivates the soft-deleted row back to 'pending'
```

## Business Rules

- Only applies to events where `event_mst.is_collaborative = true`
- Maximum **5 accepted** (non-deleted) collaborators per event. The owner is not counted.
- The owner cannot invite themselves
- Only active creator profiles (`creator_profiles.status = 'active'`) can be invited
- Any active creator on the platform is eligible — no follow relationship required
- Collaborators have **read-only** visibility — they can see the event on their profile but cannot update, delete, or postpone it. Only the event owner has those permissions.
- For recurring events, collaborators are stored on the **parent event** and resolve to all child occurrences via `COALESCE(parent_event_id, event_id)`

## Referenced By

| SP | How |
|----|-----|
| `invite_collaborator` | INSERT / reactivate row |
| `respond_collaborator_invite` | UPDATE status |
| `remove_collaborator` | Soft delete |
| `update_event` | Owner-only — collaborators cannot update |
| `delete_event` | Owner-only — collaborators cannot delete |
| `get_event_list` | Collaborator filter in visibility check |
| `get_profile_events` | Includes events where profile is a collaborator |
| `get_event_by_id` | Returns collaborators array |

## SQL Reference

See [`schema/tables/15_event_collaborators.md`](../../../schema/tables/15_event_collaborators.md)
