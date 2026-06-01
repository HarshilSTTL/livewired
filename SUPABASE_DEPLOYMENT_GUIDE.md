# Supabase Function Deployment Guide

## 🚀 How to Deploy Fixed Functions to Supabase

### **The Problem**
The error `"missing FROM-clause entry for table \"cpa\""` occurs because:
1. The SQL file has been fixed with LATERAL keywords
2. But Supabase hasn't deployed the updated function yet
3. The old function definition is still running in the database

### **The Solution: Deploy to Supabase**

## Method 1: Supabase SQL Editor (Easiest)

### Steps:

1. **Open Supabase Dashboard**
   ```
   https://app.supabase.com/project/[YOUR_PROJECT_ID]/sql/new
   ```

2. **Paste this SQL** (it drops old version then creates new):

```sql
-- Drop existing function to ensure clean update
DROP FUNCTION IF EXISTS get_profile_by_id_v2_1(uuid);

-- Create fresh function with all fixes
CREATE OR REPLACE FUNCTION get_profile_by_id_v2_1(
    p_profile_id uuid
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
-- [FULL SQL CODE HERE - see below]
$$;
```

3. **Click ▶️ RUN**
4. **Wait for green checkmark**
5. **Test endpoint** - Error should be gone!

---

## Method 2: Deploy Other Fixed Functions

### Also Deploy These (Same Process):

1. **search_profiles_v2_1**
2. **search_collaborator_profiles_v2_1**
3. **get_profile_by_userid_v2_1**
4. **get_profiles_v2_1**

---

## Method 3: Supabase CLI (For Automation)

```bash
# Login to Supabase
supabase login

# Link to your project
supabase link --project-id [YOUR_PROJECT_ID]

# Deploy all functions
supabase functions deploy

# Verify deployment
supabase functions list
```

---

## ✅ Verification Checklist

After deployment:

- [ ] Function created successfully (green checkmark in SQL editor)
- [ ] No errors in Supabase logs
- [ ] Test API endpoint: `POST /rest/v1/rpc/get_profile_by_id_v2_1`
- [ ] Returns success with `platforms`, `additional_links`, `custom_links`
- [ ] No "missing FROM-clause" error

---

## 🔧 Quick SQL to Test Function Exists

```sql
-- Check if function exists
SELECT proname, pronargs 
FROM pg_proc 
WHERE proname = 'get_profile_by_id_v2_1';

-- Should return: get_profile_by_id_v2_1 | 1
```

---

## 📝 Git Log for Reference

- **File**: `[[functions/profiles/get_profile_by_id.md]]`
- **Latest Commit**: `8c8da45`
- **Changes**: Added LATERAL keyword + uppercase COALESCE
- **Status**: Ready for Supabase deployment

