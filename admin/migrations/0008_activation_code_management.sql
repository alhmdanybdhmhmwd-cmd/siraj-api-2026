-- Server-side activation code configuration. Store only a hash and authenticated ciphertext.
-- Apply to an isolated Admin Preview database for validation; shared production changes require owner approval.
CREATE TABLE IF NOT EXISTS admin_activation_config (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  code_hash TEXT,
  encrypted_code TEXT,
  disabled INTEGER NOT NULL DEFAULT 0 CHECK (disabled IN (0, 1)),
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (
    (disabled = 1 AND code_hash IS NULL AND encrypted_code IS NULL) OR
    (disabled = 0 AND code_hash IS NOT NULL AND encrypted_code IS NOT NULL)
  )
);
