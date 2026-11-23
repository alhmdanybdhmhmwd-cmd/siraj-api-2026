-- Caption text belongs to the same attachment message and is preserved for resumable retries.
ALTER TABLE media_upload_sessions
  ADD COLUMN caption TEXT NOT NULL DEFAULT '';
