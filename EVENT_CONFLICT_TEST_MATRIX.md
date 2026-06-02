# Event Conflict Detection — Test Matrix & Bug Analysis

## Current Logic (BUGGY)

```sql
existing_start < v_new_end AND existing_end > v_new_start
```

---

## Test Cases Analysis

### ❌ **FAILING CASES** (Current logic doesn't detect these)

| # | New Event | Existing | Logic Test | Expected | Actual | Issue |
|---|-----------|----------|-----------|----------|--------|-------|
| 1 | 1:00 PM (no end) | 1:00-6:00 PM | `1:00 < 1:00 AND 6:00 > 1:00` | ✅ YES | ❌ NO | `<` should be `<=` |
| 2 | 1:00-6:00 PM | 1:00-6:00 PM | `1:00 < 6:00 AND 6:00 > 1:00` | ✅ YES | ✅ YES | Works |
| 3 | 1:00 PM (no end) | 1:00-1:00 PM | `1:00 < 1:00 AND 1:00 > 1:00` | ✅ YES | ❌ NO | `<` should be `<=` |
| 4 | 6:00 PM (no end) | 1:00-6:00 PM | `1:00 < 6:00 AND 6:00 > 6:00` | ❌ NO | ❌ NO | Edge case (boundary) |
| 5 | 1:00 PM (no end) | 12:00-1:00 PM | `12:00 < 1:00 AND 1:00 > 1:00` | ✅ YES | ❌ NO | `>` should be `>=` |

---

## The Bug

**Line 99-100 in function:**
```sql
AND (event_date || ' ' || event_time)::timestamp < v_new_end      -- ❌ STRICT <
AND (event_date || ' ' || event_end_time)::timestamp > v_new_start -- ❌ STRICT >
```

**Problem:** When times are exactly equal, strict comparison fails!

**Example:**
- New: 1:00 PM (no end) → v_new_end = 1:00 PM
- Existing: 1:00-6:00 PM → existing_start = 1:00 PM
- Check: `1:00 < 1:00` = **FALSE** ❌ (should be TRUE)

---

## Fix Required

Change from:
```sql
AND (event_date || ' ' || event_time)::timestamp < v_new_end
AND (event_date || ' ' || event_end_time)::timestamp > v_new_start
```

To:
```sql
AND (event_date || ' ' || event_time)::timestamp <= v_new_end      -- ✅ Use <=
AND (event_date || ' ' || event_end_time)::timestamp >= v_new_start -- ✅ Use >=
```

---

## All Scenarios (After Fix)

### ✅ **SHOULD CONFLICT (YES)**

| # | New Event | Existing | Reason |
|---|-----------|----------|--------|
| 1 | 1:00 PM (no end) | 1:00-6:00 PM | Same start time |
| 2 | 1:00-6:00 PM | 1:00-6:00 PM | Exact same time |
| 3 | 2:00-3:00 PM | 1:00-6:00 PM | Inside existing |
| 4 | 12:00-2:00 PM | 1:00-6:00 PM | Overlaps start |
| 5 | 5:00-7:00 PM | 1:00-6:00 PM | Overlaps end |
| 6 | 12:00-7:00 PM | 1:00-6:00 PM | Covers existing |
| 7 | 6:00 PM (no end) | 1:00-6:00 PM | Boundary (same as end) |

### ❌ **SHOULD NOT CONFLICT (NO)**

| # | New Event | Existing | Reason |
|---|-----------|----------|--------|
| 1 | 6:01 PM (no end) | 1:00-6:00 PM | After existing ends |
| 2 | 12:59 PM (no end) | 1:00-6:00 PM | Before existing starts |
| 3 | 6:00-7:00 PM | 1:00-6:00 PM | Adjacent (not overlapping) |
| 4 | 12:00-1:00 PM | 1:00-6:00 PM | Adjacent (not overlapping) |
| 5 | 2:00 PM | Different date | Different day |

---

## Summary

**Root Cause:** Strict comparison operators (`<`, `>`) don't handle boundary cases

**Impact:** Events with same start/end times aren't detected as conflicts

**Fix:** Change to inclusive operators (`<=`, `>=`)

**Files to Update:**
- `functions/events/check_event_conflict.md` (lines 99-100, 116-117)

---
