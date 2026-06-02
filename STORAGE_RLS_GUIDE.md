# Supabase Storage RLS Fix — Profile Image Upload

## Problem

**Error:** `StorageException(message: new row violates row-level security policy, statusCode: 403, error: Unauthorized)`

**When:** Google login → Try to upload profile image

**Why:** The storage bucket has RLS (Row-Level Security) policies enabled, but the authenticated user doesn't have permission to upload.

---

## Root Cause

1. ✅ Google login works (user created in `public.users` table)
2. ✅ Auth session is valid (`auth.uid()` is set)
3. ❌ Storage bucket RLS policy doesn't allow the upload
   - Policy might require a specific path pattern
   - Policy might check a condition that isn't met for Google users
   - Policy might be disabled/misconfigured

---

## Solution (Choose One)

### **Option A: Disable RLS for avatars bucket (Recommended for Public Images)**

If profile avatars should be **public and readable by everyone** (recommended):

1. **Open Supabase Dashboard**
   ```
   https://app.supabase.com/project/[YOUR_PROJECT_ID]/storage/buckets
   ```

2. **Find the avatars/profile bucket** (probably named `avatars`, `profile_images`, or `profiles`)

3. **Click the bucket → Settings → Disable RLS**
   - Toggle RLS OFF
   - Save

4. **Update RLS Policy to:**
   ```sql
   -- No RLS policy needed (bucket RLS disabled)
   -- OR just allow authenticated users to read
   ```

5. **Test:** Try uploading again → Should work ✅

---

### **Option B: Fix RLS Policy (If You Need Permission Control)**

If avatars should have **specific access control**:

1. **Open Supabase Dashboard → Storage Buckets**

2. **Click bucket → Policies tab**

3. **Create or Update Upload Policy:**

```sql
-- Allow authenticated users to upload their own avatar
CREATE POLICY "authenticated_upload_avatar"
ON storage.objects
FOR INSERT
WITH CHECK (
    bucket_id = 'avatars'  -- replace with your bucket name
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
);

-- Allow public read (optional)
CREATE POLICY "public_read_avatar"
ON storage.objects
FOR SELECT
USING (bucket_id = 'avatars');
```

4. **Test upload** → Should work ✅

---

### **Option C: Allow All Authenticated Users (Simplest)**

If any authenticated user can upload to any path:

```sql
-- Allow any authenticated user to upload
CREATE POLICY "authenticated_can_upload"
ON storage.objects
FOR INSERT
WITH CHECK (
    bucket_id = 'avatars'
    AND auth.role() = 'authenticated'
);

-- Allow anyone to read
CREATE POLICY "public_read"
ON storage.objects  
FOR SELECT
USING (bucket_id = 'avatars');
```

---

## Current Status Check

To see what's currently configured:

1. **Supabase Dashboard → Storage → [Your Bucket]**
2. **Policies tab**
3. **Check if RLS is enabled**
4. **Review all upload/insert policies**

---

## Expected Path for Avatar Upload

Users should upload to:
```
avatars/{user_id}/profile.jpg
```

Or your app might use:
```
profile_images/{user_id}/avatar.png
avatars/{profile_id}/image.jpg
```

**Check what path your app is using in the upload code.**

---

## Testing

After fixing:

```bash
# Test Google login
1. Login with Google
2. Try to upload profile image
3. Should succeed → 200 OK

# Expected Response
{
  "status": "success",
  "path": "avatars/{user_id}/profile.jpg",
  "url": "https://[project].supabase.co/storage/v1/object/public/avatars/..."
}
```

---

## Files Related

- **Auth:** [[functions/auth/google_auth.md]]
- **Documentation:** [[docs/api/auth/google_auth.md]]
- **Users Table:** [[schema/tables/02_users.md]]

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `403 Unauthorized` | RLS policy denies upload | Disable RLS or update policy |
| `Bucket not found` | Wrong bucket name | Check actual bucket name in Supabase |
| `Invalid path` | Path doesn't match policy | Upload to `{user_id}/filename` path |
| `User not authenticated` | Auth session invalid | Re-login with Google |

---

## Next Steps

1. ✅ Determine which bucket name is used (avatars, profiles, etc.)
2. ✅ Check RLS policies in Supabase
3. ✅ Apply the appropriate fix (A, B, or C)
4. ✅ Test upload after Google login
5. ✅ Verify image URL is returned correctly

---
