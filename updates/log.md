# LiveWired — Update Log Index

> Daily update files are stored separately. This file is the index.
> To add a new entry, append to the relevant daily file (or create a new one for today's date).

---

## Daily Files

| Date | File | Summary |
|------|------|---------|
| 2026-03-30 | [2026-03-30.md](2026-03-30.md) | Project init · users + auth SPs · platforms · tags · creator profiles · events · follows · all 12 tables + 20 SPs complete |
| 2026-03-31 | [2026-03-31.md](2026-03-31.md) | update_profile · create_event · roles table · SQL→MD conversion · event_recurring · event_link removed · profile read SPs · get_profile_events · API_INDEX |
| 2026-04-01 | [2026-04-01.md](2026-04-01.md) | get_profile_events recurring fix → pre-generation model · avatar_url→avatar rename · google_auth SP · create_profile role gate removed |
| 2026-04-02 | [2026-04-02.md](2026-04-02.md) | get_profile_events input revert · follow_creator dead code fix · register/login p_ prefix fix · uuid type fix · password NOT NULL migration · log restructure |

---

## Entry Format

```
### [YYYY-MM-DD HH:MM] | TYPE | Short title

Details...

**Files changed:**
- path/to/file.md — what changed
```

**Types:** `INIT` · `TABLE` · `SP` · `API` · `FIX` · `SCHEMA` · `DOCS`
