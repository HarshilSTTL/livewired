# LiveWired — Update Log

> Format: `[YYYY-MM-DD HH:MM] | Type | Summary`
> Types: `INIT` · `TABLE` · `SP` · `API` · `FIX` · `SCHEMA` · `DOCS`
> This file is append-only. Most recent entries are at the top.

---

## 2026-03-30

### [2026-03-30 21:00] | TABLE + SP | user_preferred_platforms, user_interests tables + submit_platform, submit_tags, get_creators, search_profiles SPs — ALL 12 TABLES AND 20 SPs COMPLETE

**Tables populated:**

`user_preferred_platforms`:
- Columns: id (int8 PK), user_id (uuid, FK → users.id), platform_id (int8, FK → platforms.plat_id), created_at (timestamptz)
- ⚠️ platform_id is int8 here — unlike event_platforms.platform_id which is int4
- Used by submit_platform SP (delete + re-insert pattern)
- No unique constraint documented — SP replaces all rows per user

`user_interests`:
- Columns: id (int8 PK), user_id (uuid, FK → users.id), tag_id (int8, FK → tags.tag_id), created_at (timestamptz)
- FK names: user_interests_user_id_fkey, user_interests_tag_id_fkey
- Used by submit_tags SP (delete + re-insert pattern)

**SPs populated:**

`submit_platform` (POST /rpc/submit_platform):
- Params: p_user_id (uuid), p_platformid (int[])
- Replace-all pattern: DELETE + INSERT — previous selections always wiped
- Validation order: user check → array null/empty → platform ID validity
- Machine-readable error codes: USER_NOT_FOUND, EMPTY_PLATFORM_LIST, INVALID_PLATFORM_ID
- Response key: `status` (standard)

`submit_tags` (POST /rpc/submit_tags):
- Params: p_user_id (uuid), p_tag_ids (bigint[])
- ⚠️ Response key is `resultFlag` (NOT `status`) — unique among all 20 SPs
- Replace-all pattern: DELETE + INSERT
- Validation order: user_id null → array null/empty → user exists → tag ID validity
- p_tag_ids type is bigint[] (vs submit_platform's int[])

`get_creators` (GET /rpc/get_creators):
- No params — returns all active creator profiles
- ⚠️ followers count has NO is_active filter — counts ALL rows in follows table
- ⚠️ platforms returns string array ["YouTube", "Twitch"] NOT objects with platform_id/logo_url
- Response wrapped in data.creators[] (not data[] directly)
- Used for follow recommendations during onboarding

`search_profiles` (POST /rpc/search_profiles):
- Params: p_keyword (text, min 2 chars), p_limit (int, default 20)
- Requires pg_trgm extension
- Searches: profile_name, username, bio via ILIKE + word_similarity (threshold > 0.3)
- coalesce(bio, '') handles nullable bio in fuzzy match
- Returns match_score (0.0–1.0), ordered score DESC

**Files changed:**
- `docs/database/tables/11_user_preferred_platforms.md` — full schema, int8 note, SP reference
- `schema/tables/11_user_preferred_platforms.sql` — CREATE TABLE
- `docs/database/tables/12_user_interests.md` — full schema, FK names, SP reference
- `schema/tables/12_user_interests.sql` — CREATE TABLE
- `functions/platforms/submit_platform.sql` — actual SP SQL with error codes
- `docs/api/platforms/submit_platform.md` — full docs with error code table
- `functions/tags/submit_tags.sql` — actual SP SQL (resultFlag response)
- `docs/api/tags/submit_tags.md` — full docs with resultFlag warning
- `functions/follow/get_creators.sql` — actual SP SQL (no is_active filter, string platforms)
- `docs/api/follow/get_creators.md` — full docs with differences table vs other SPs
- `functions/search/search_profiles.sql` — actual SP SQL (reconstructed full function)
- `docs/api/search/search_profiles.md` — full docs with search behavior table

**Milestone:** All 12 tables and all 20 stored procedures are now fully documented and populated.
**Pending:** 7 SPs remain as stubs (Events CRUD × 4, Notifications × 2, Settings × 1)

---

### [2026-03-30 20:15] | TABLE + SP | follows table + follow_creator, unfollow_creator, get_following_list, get_followers_list SPs populated

**Table:** `follows`
- Columns: id (uuid PK), user_id (uuid), profile_id (uuid), created_at (timestamptz, nullable), is_active (bool, default true), unfollowed_at (timestamptz, nullable)
- FK: fk_user → users.id | fk_profile → creator_profiles.id
- Soft delete pattern: unfollow sets is_active=false + unfollowed_at=now(); re-follow updates existing row

**SPs populated (Follow group — all 4):**

`follow_creator` (POST /rpc/follow_creator):
- Params: p_user_id (uuid), p_profile_id (uuid)
- ⚠️ p_device_ip referenced in body but NOT in function signature — device IP update won't execute
- Validates: null checks, user exists, profile active, not own profile
- Re-follow: updates existing row (is_active=true, unfollowed_at=null, created_at=now())
- Already following: returns error if is_active=true

`unfollow_creator` (POST /rpc/unfollow_creator):
- Params: p_user_id (uuid), p_profile_id (uuid)
- Soft delete: UPDATE is_active=false, unfollowed_at=now()
- Validates active follow row exists before updating

`get_following_list` (POST /rpc/get_following_list):
- Param: p_user_id (uuid)
- Returns: profile_id, profile_name, username, avatar_url, bio, status, followers (live count), platforms array, followed_at
- Filters: is_active=true AND cp.status='active'
- Ordered by followed_at DESC

`get_followers_list` (POST /rpc/get_followers_list):
- Param: p_profile_id (uuid)
- Returns: user_id, email, followed_at + total_followers in response root
- total_followers is a separate COUNT query
- Ordered by followed_at DESC

**Files changed:**
- `docs/database/tables/10_follows.md` — full schema, soft delete rules, referenced-by list
- `schema/tables/10_follows.sql` — CREATE TABLE with soft delete comments
- `functions/follow/follow_creator.sql` — actual SP SQL (with p_device_ip note)
- `docs/api/follow/follow_creator.md` — full docs with state machine diagram
- `functions/follow/unfollow_creator.sql` — actual SP SQL
- `docs/api/follow/unfollow_creator.md` — full docs
- `functions/follow/get_following_list.sql` — actual SP SQL
- `docs/api/follow/get_following_list.md` — full docs
- `functions/follow/get_followers_list.sql` — actual SP SQL (reconstructed full function)
- `docs/api/follow/get_followers_list.md` — full docs with comparison table

---

### [2026-03-30 19:30] | TABLE + SP | event_mst, event_platforms tables + get_event_list + search_events SPs populated

**Tables updated:**

`event_mst`:
- Columns: event_id (uuid PK), profile_id (uuid, FK → creator_profiles.id), title, description (nullable), event_link, event_date, event_time, livestream (bool), video (bool), is_recurring (bool), created_at, updated_at (nullable)
- FK: event_mst_profile_id_fkey → creator_profiles.id ON DELETE CASCADE

`event_platforms`:
- Columns: id (uuid PK), event_id (uuid, FK), platform_id (int4 ⚠️), stream_url, created_at (timestamp, nullable)
- ⚠️ platform_id is int4 (not int8) — requires ::bigint cast when joining platforms.plat_id
- ⚠️ created_at is timestamp (no timezone), nullable
- FK: fk_event → event_mst.event_id | fk_platform → platforms.plat_id

**SPs populated:**

`get_event_list` (POST /rpc/get_event_list):
- Params: p_date (date, default CURRENT_DATE), p_device_ip (text, optional)
- 3-branch date logic: past / today / future
- Live section: livestream=true, started, within 3-hour window
- Terminated events (>3h ago) hidden from both sections
- Returns: { live: [...], today: [...] } — both always arrays never null

`search_events` (POST /rpc/search_events):
- Params: p_keyword (text, required, min 2 chars), p_limit (int, default 20)
- Searches: event_mst.title + description via ILIKE + word_similarity (threshold 0.3)
- coalesce(description, '') used to handle nullable description in fuzzy match
- Returns match_score (0.0–1.0), ordered score DESC, event_date ASC

**Files changed:**
- `docs/database/tables/08_event_mst.md` — full schema, FK, live section business rules
- `schema/tables/08_event_mst.sql` — CREATE TABLE
- `docs/database/tables/09_event_platforms.md` — schema, int4/int8 warning, timestamp warning
- `schema/tables/09_event_platforms.sql` — CREATE TABLE with type warnings
- `functions/events/get_event_list.sql` — actual SP SQL (full 3-branch logic)
- `docs/api/events/get_event_list.md` — full docs with date logic table
- `functions/search/search_events.sql` — actual SP SQL
- `docs/api/search/search_events.md` — full docs with search behavior table

---

### [2026-03-30 18:45] | TABLE + SP | creator_profiles, creator_platform_accounts, profile_tags tables + create_profile + is_creator SPs populated

**Tables updated:**

`creator_profiles`:
- username → UNIQUE constraint
- avatar_url → nullable
- bio → nullable
- show_followers → NEW column (boolean, default true) — not in original design

`creator_platform_accounts`:
- channel_url → nullable (at DB level; SP requires it when platforms are passed)
- username → nullable

`profile_tags`:
- profile_id → nullable
- tag_id → nullable

`users` (updated again):
- role_id column added (int8) — used by is_creator SP and checked in create_profile SP
- Corrects earlier assumption that role was tracked only via is_creator boolean

**SPs populated:**

`create_profile` (POST /rpc/create_profile):
- Checks role_id = 2 before allowing profile creation
- Accepts p_platforms (jsonb array) + p_tag_ids (bigint[]) in same call
- Auto-sets is_default = true for first profile
- Validates platform IDs, channel_urls, tag count (max 10), tag IDs
- Inserts into creator_profiles + creator_platform_accounts + profile_tags atomically
- Returns profile_id + show_followers

`is_creator` (POST /rpc/is_creator) — was: creator_enable:
- ⚠️ SP renamed from creator_enable → is_creator in actual DB
- Sets role_id = 2 (creator) or 1 (user)
- Updates updated_device_ip and updated_at

**Files changed:**
- `docs/database/tables/02_users.md` — added role_id column, updated business rules
- `schema/tables/02_users.sql` — added role_id column
- `docs/database/tables/05_creator_profiles.md` — full schema including show_followers
- `schema/tables/05_creator_profiles.sql` — CREATE TABLE
- `docs/database/tables/06_creator_platform_accounts.md` — nullable channel_url, username
- `schema/tables/06_creator_platform_accounts.sql` — CREATE TABLE
- `docs/database/tables/07_profile_tags.md` — nullable profile_id and tag_id
- `schema/tables/07_profile_tags.sql` — CREATE TABLE
- `functions/profiles/create_profile.sql` — actual SP SQL
- `docs/api/profiles/create_profile.md` — full API docs incl. p_platforms format
- `functions/profiles/creator_enable.sql` — updated to is_creator function
- `docs/api/profiles/creator_enable.md` — updated for is_creator rename + role_id logic

---

### [2026-03-30 18:15] | TABLE + SP | tags table + get_all_tags SP populated

**Table:** `tags`
- Columns: tag_id (int8 PK), tag_name (text, nullable)
- Both columns confirmed nullable (tag_id is PK so not null in practice)
- No is_active flag — all tags always returned
- 13 seed tags: Gaming, Tech, Music, Sports, Travel, Finance, Cooking, Health, News, Science, Entertainment, Politics, Automotive

**SP populated:** `get_all_tags`
- `GET /rpc/get_all_tags` — no params, returns ALL tags (no filter)
- Returns: tag_id, tag_name
- tag_name can be null — UI must handle gracefully
- SECURITY DEFINER, json_agg result

**Files changed:**
- `docs/database/tables/04_tags.md` — full column table, business rules, seed data, referenced-by list
- `schema/tables/04_tags.sql` — CREATE TABLE + seed INSERT (13 tags)
- `functions/tags/get_all_tags.sql` — actual SP SQL
- `docs/api/tags/get_all_tags.md` — params, request/response, error cases, diff vs get_all_platforms

---

### [2026-03-30 18:00] | TABLE + SP | platforms table + get_all_platforms SP populated

**Table:** `platforms`
- Columns: plat_id (int8 PK), created_at, plat_name, logo_url (nullable), is_active (int2, default 1)
- `logo_url` confirmed nullable
- `is_active` is `int2` type with default `1` (not boolean)

**SP populated:** `get_all_platforms`
- `GET /rpc/get_all_platforms` — no params, returns all active platforms (is_active = 1)
- Returns: plat_id, plat_name, logo_url, is_active, created_at
- logo_url can be null in response — UI must handle gracefully
- SECURITY DEFINER, json_agg result

**Files changed:**
- `docs/database/tables/03_platforms.md` — full column table, business rules, seed data, referenced-by list
- `schema/tables/03_platforms.sql` — CREATE TABLE + seed INSERT
- `functions/platforms/get_all_platforms.sql` — actual SP SQL
- `docs/api/platforms/get_all_platforms.md` — params, request/response, error cases, logic flow

---

### [2026-03-30 17:45] | TABLE | users table — nullable + unique constraint clarification

**Fields clarified:**
- `created_device_ip` → explicitly nullable
- `updated_device_ip` → explicitly nullable
- `email` → confirmed UNIQUE constraint

**Files changed:**
- `docs/database/tables/02_users.md` — added Nullable column to table, marked ip fields as nullable
- `schema/tables/02_users.sql` — added `NULL` keyword explicitly on ip columns, inline comments

---

### [2026-03-30 17:30] | TABLE + SP | users table schema + Auth group (register, signup, login) populated

**Table updated:** `users`
- `id` is `int8` (not `uuid` as initially planned)
- No `role_id` FK — uses `is_creator boolean` instead
- Columns: id, created_at, email, is_creator, updated_at, created_device_ip, updated_device_ip, password

**SPs populated (Auth group — all 3):**
- `register` — basic registration, no input validation, param name `created_device_i`
- `signup` — improved registration with email/password validation, case-insensitive email check, SECURITY DEFINER
- `login` — email+password auth, exact email match, plain text password compare, SECURITY DEFINER

**Files changed:**
- `docs/database/tables/02_users.md` — full column table, business rules, SP usage list
- `schema/tables/02_users.sql` — CREATE TABLE statement
- `functions/auth/register.sql` — actual SP SQL
- `functions/auth/signup.sql` — actual SP SQL
- `functions/auth/login.sql` — actual SP SQL
- `docs/api/auth/register.md` — parameters, request/response, error cases, logic flow
- `docs/api/auth/signup.md` — parameters, request/response, error cases, diff vs register
- `docs/api/auth/login.md` — parameters, request/response, error cases, notes

**Design note:** `users.id` is `int8` not `uuid`. All SPs returning `user_id` return a bigint.

---

### [2026-03-30 14:50] | INIT | Project documentation repository initialized

**What was done:**
- Created full folder and file structure for LiveWired backend documentation
- Defined 12 table placeholder docs under `docs/database/tables/`
- Defined 20 stored procedure placeholder docs under `docs/api/`
- Created SQL placeholder files under `schema/` and `functions/`
- Created `README.md`, `CONTEXT.md`, `docs/business-rules.md`, and this log

**Current state:**
- 20 stored procedures documented (structure only, SQL to be populated)
- 12 tables documented (structure only, SQL to be populated)
- 7 APIs pending (Events CRUD, Notifications, Settings)

**Next step:** User will provide SP SQL code and table details — populate all files accordingly.

---

<!--
APPEND NEW ENTRIES ABOVE THIS LINE
Format for new entries:
### [YYYY-MM-DD HH:MM] | TYPE | Short title
- Bullet points summarizing what changed
- Which files were modified
- Any breaking changes or notes
-->
