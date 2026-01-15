-- Set search path to tmschema
SET search_path TO tmschema;

-- Add index for S3 file uploads to speed up lookups by bucket and key
CREATE INDEX IF NOT EXISTS idx_s3_file_uploads_bucket_key ON s3_file_uploads(bucket_name, object_key);

-- Add index for direct messages received_at for potential time-based queries
CREATE INDEX IF NOT EXISTS idx_direct_messages_received_at ON direct_messages(received_at);
