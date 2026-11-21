-- Persist transport-chunk and multipart-part checksums across retries.
-- Nullable values preserve compatibility with uploads created before this migration.
ALTER TABLE media_upload_chunks ADD COLUMN sha256 TEXT
  CHECK (sha256 IS NULL OR length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*');

ALTER TABLE media_upload_parts ADD COLUMN sha256 TEXT
  CHECK (sha256 IS NULL OR length(sha256) = 64 AND sha256 NOT GLOB '*[^0-9a-f]*');
