-- Owner-controlled reusable device activation code. Only SHA-256 hashes are stored.
-- Shared runtime: apply to BARQ D1 only after explicit owner approval; Preview may use its isolated Admin D1.
CREATE TABLE IF NOT EXISTS admin_owner_activation_codes (
  owner_subject TEXT PRIMARY KEY,
  code_hash TEXT NOT NULL UNIQUE,
  created_by_device TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  revoked_at TEXT
);
CREATE INDEX IF NOT EXISTS idx_admin_owner_activation_codes_active
  ON admin_owner_activation_codes(owner_subject, revoked_at);
