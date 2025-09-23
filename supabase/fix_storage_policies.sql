-- Fix Storage policies for Basketball Coach app
-- This script creates the necessary storage bucket and policies for anonymous uploads

-- First, create the 'clips' bucket if it doesn't exist
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'clips',
  'clips', 
  false, 
  52428800, -- 50MB limit
  ARRAY['video/mp4', 'video/quicktime', 'video/x-msvideo']::text[]
)
ON CONFLICT (id) DO NOTHING;

-- Drop existing storage policies if they exist
DROP POLICY IF EXISTS "Allow anonymous uploads to clips bucket" ON storage.objects;
DROP POLICY IF EXISTS "Allow anonymous reads from clips bucket" ON storage.objects;
DROP POLICY IF EXISTS "Allow anonymous updates to clips bucket" ON storage.objects;
DROP POLICY IF EXISTS "Allow anonymous deletes from clips bucket" ON storage.objects;

-- Create comprehensive storage policies for the clips bucket
CREATE POLICY "Allow anonymous uploads to clips bucket"
  ON storage.objects
  FOR INSERT
  TO anon
  WITH CHECK (bucket_id = 'clips');

CREATE POLICY "Allow anonymous reads from clips bucket"
  ON storage.objects
  FOR SELECT
  TO anon
  USING (bucket_id = 'clips');

CREATE POLICY "Allow anonymous updates to clips bucket"
  ON storage.objects
  FOR UPDATE
  TO anon
  USING (bucket_id = 'clips')
  WITH CHECK (bucket_id = 'clips');

CREATE POLICY "Allow anonymous deletes from clips bucket"
  ON storage.objects
  FOR DELETE
  TO anon
  USING (bucket_id = 'clips');

-- Also allow authenticated users (for future use)
CREATE POLICY "Allow authenticated uploads to clips bucket"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'clips');

CREATE POLICY "Allow authenticated reads from clips bucket"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (bucket_id = 'clips');

CREATE POLICY "Allow authenticated updates to clips bucket"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (bucket_id = 'clips')
  WITH CHECK (bucket_id = 'clips');

CREATE POLICY "Allow authenticated deletes from clips bucket"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (bucket_id = 'clips');

-- Grant necessary permissions to anon role for storage
GRANT ALL ON storage.objects TO anon;
GRANT ALL ON storage.buckets TO anon;

-- Verify the bucket was created
SELECT id, name, public, file_size_limit, allowed_mime_types 
FROM storage.buckets 
WHERE id = 'clips';

-- Verify the policies were created
SELECT schemaname, tablename, policyname, roles, cmd 
FROM pg_policies 
WHERE schemaname = 'storage' 
AND tablename = 'objects'
AND policyname LIKE '%clips%';
