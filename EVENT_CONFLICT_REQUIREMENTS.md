# Event Conflict Detection — User Requirements

## Your Desired Behavior

**Adjacent events (end-to-end) = NO CONFLICT** ✅  
**Overlapping events = CONFLICT** ✅

---

## Correct Scenarios

| # | New Event | Existing | Expected | Reason |
|---|-----------|----------|----------|--------|
| 1 | 1:00 PM (no end) | 1:00-6:00 PM | ✅ CONFLICT | Same start time = overlap |
| 2 | 1:00-6:00 PM | 1:00-6:00 PM | ✅ CONFLICT | Exact same = overlap |
| 3 | 2:30 PM (no end) | 1:00-6:00 PM | ✅ CONFLICT | During existing = overlap |
| 4 | 2:00-3:00 PM | 1:00-6:00 PM | ✅ CONFLICT | Inside existing = overlap |
| 5 | 12:00-2:00 PM | 1:00-6:00 PM | ✅ CONFLICT | Overlaps start = overlap |
| 6 | 5:00-7:00 PM | 1:00-6:00 PM | ✅ CONFLICT | Overlaps end = overlap |
| 7 | **6:00 PM (no end)** | **1:00-6:00 PM** | **❌ NO CONFLICT** | **Adjacent (not overlapping)** |
| 8 | 6:01 PM (no end) | 1:00-6:00 PM | ❌ NO CONFLICT | After existing = no overlap |
| 9 | 12:59 PM (no end) | 1:00-6:00 PM | ❌ NO CONFLICT | Before existing = no overlap |
| 10 | 6:00-7:00 PM | 1:00-6:00 PM | ❌ NO CONFLICT | Adjacent (not overlapping) |
| 11 | 12:00-1:00 PM | 1:00-6:00 PM | ❌ NO CONFLICT | Adjacent (not overlapping) |

---

## The Correct Logic

```sql
-- CORRECT (mixed operators)
existing_start <= new_end AND existing_end > new_start

-- Explanation:
-- - existing_start <= new_end   (includes same start time)
-- - existing_end > new_start    (excludes same end time - allows adjacency)
```

### Why This Works:

**Case 1: 2:30 PM (no end) vs 1:00-6:00 PM**
- v_new_start = 2:30, v_new_end = 2:30
- Check: `1:00 <= 2:30 AND 6:00 > 2:30` = TRUE AND TRUE = **CONFLICT** ✅

**Case 2: 6:00 PM (no end) vs 1:00-6:00 PM**
- v_new_start = 6:00, v_new_end = 6:00
- Check: `1:00 <= 6:00 AND 6:00 > 6:00` = TRUE AND FALSE = **NO CONFLICT** ✅

**Case 3: 1:00 PM (no end) vs 1:00-6:00 PM**
- v_new_start = 1:00, v_new_end = 1:00
- Check: `1:00 <= 1:00 AND 6:00 > 1:00` = TRUE AND TRUE = **CONFLICT** ✅

**Case 4: 12:00-1:00 PM vs 1:00-6:00 PM (adjacent)**
- v_new_start = 12:00, v_new_end = 1:00
- Check: `1:00 <= 1:00 AND 6:00 > 12:00` = TRUE AND TRUE = **CONFLICT** ❌
- Wait, this shows conflict but should be no conflict!

---

## Better Logic

For true adjacency (no overlap):
```sql
existing_start < new_end AND existing_end > new_start
```

But this doesn't catch "1:00 PM (no end) vs 1:00-6:00 PM"

**Solution: Use CASE logic**

```sql
CASE 
    WHEN p_event_end_time IS NULL THEN
        -- Point-in-time: check if start_time is DURING (not at boundary) existing event
        (event_date || ' ' || event_time)::timestamp < v_new_end
        AND (event_date || ' ' || event_end_time)::timestamp > v_new_start
    ELSE
        -- Range: use strict comparison (no adjacency)
        (event_date || ' ' || event_time)::timestamp < v_new_end
        AND (event_date || ' ' || event_end_time)::timestamp > v_new_start
END
```

Actually, we need special handling for point-in-time:

```sql
-- If no end_time (point-in-time check)
IF p_event_end_time IS NULL THEN
    -- v_new_start = v_new_end = the single point in time
    -- Check if this point is DURING (inclusive) existing event
    -- existing_start <= point <= existing_end becomes:
    -- existing_start <= point AND existing_end >= point
    THEN use: existing_start <= new_point AND existing_end >= new_point

-- If has end_time (range check)
ELSE
    -- Check if ranges overlap (exclusive of boundaries)
    -- existing_start < new_end AND existing_end > new_start
    THEN use: existing_start < new_end AND existing_end > new_start
END
```

---

## Summary

**Point-in-time (no end_time):** `existing_start <= point AND existing_end >= point`
- Includes boundaries (same as start or end = conflict)

**Range (with end_time):** `existing_start < new_end AND existing_end > new_start`
- Excludes boundaries (adjacent = no conflict)

---
