import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../migrations/0001_recovery_codes.sql", import.meta.url), "utf8");
const sessionMigration = await readFile(new URL("../migrations/0002_recovery_token_revocations.sql", import.meta.url), "utf8");
const config = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");

test("recovery migration creates only additive recovery tables", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS recovery_codes/i);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS recovery_rate_limits/i);
  assert.match(migration, /CREATE INDEX IF NOT EXISTS idx_recovery_rate_limits_window/i);
  assert.doesNotMatch(migration, /\b(DROP|DELETE|UPDATE|ALTER)\s+(TABLE|FROM|users|messages|friendships)\b/i);
  assert.match(migration, /FOREIGN KEY \(user_id\) REFERENCES users\(id\) ON DELETE CASCADE/i);
});

test("session revocation uses a separate additive migration", () => {
  assert.match(sessionMigration, /CREATE TABLE IF NOT EXISTS recovery_token_revocations/i);
  assert.match(sessionMigration, /FOREIGN KEY \(user_id\) REFERENCES users\(id\) ON DELETE CASCADE/i);
});

test("recovery endpoint validates a 160-bit hexadecimal code and password length", () => {
  assert.match(worker, /path === "\/api\/password\/recover"/);
  assert.match(worker, /\^\[A-F0-9\]\{40\}\$/);
  assert.match(worker, /newPassword\.length < 8/);
  assert.match(worker, /newPassword\.length > 128/);
});

test("recovery codes are generated with cryptographic randomness, salted hashes, and 90-day expiry", () => {
  assert.match(worker, /RECOVERY_CODE_TTL_SECONDS = 90 \* 24 \* 60 \* 60/);
  assert.match(worker, /now \+ RECOVERY_CODE_TTL_SECONDS/);
  assert.match(worker, /createdAt \+ RECOVERY_CODE_TTL_SECONDS/);
  assert.match(worker, /crypto\.getRandomValues\(new Uint8Array\(byteLength\)\)/);
  assert.match(worker, /crypto\.subtle\.digest\("SHA-256"/);
  assert.match(worker, /code_hash/);
  assert.match(worker, /code_salt/);
  assert.match(worker, /constantTimeHexEqual/);
  assert.match(worker, /iat_ms: Date\.now\(\)/);
  assert.match(worker, /recovery_token_revocations/);
  assert.match(worker, /revoked_at_ms/);
});

test("recovery attempts are rate limited by normalized identifier and account, and codes are consumed", () => {
  assert.match(worker, /consumeRecoveryAttempt\(env, "identifier", identifier\)/);
  assert.match(worker, /consumeRecoveryAttempt\(env, "account", user\.id\)/);
  assert.match(worker, /UPDATE recovery_codes SET consumed_at = \?/);
});

test("production D1 binding and migrations directory remain configured", () => {
  assert.match(config, /binding\s*=\s*"DB"/);
  assert.match(config, /database_name\s*=\s*"siraj-db"/);
  assert.match(config, /migrations_dir\s*=\s*"migrations"/);
});

test("password recovery performs the password update, one-time consume, and session revocation in one D1 batch", () => {
  const start = worker.indexOf('if (method === "POST" && path === "/api/password/recover")');
  const end = worker.indexOf('// Login', start);
  assert.ok(start >= 0 && end > start, "recovery endpoint block exists");
  const endpoint = worker.slice(start, end);
  assert.match(endpoint, /env\.DB\.batch\(\[/);
  assert.match(endpoint, /UPDATE users SET password_hash = \?, password_salt = \? WHERE id = \? AND EXISTS/);
  assert.match(endpoint, /UPDATE recovery_codes SET consumed_at = \? WHERE user_id = \? AND code_hash = \? AND consumed_at IS NULL/);
  assert.match(endpoint, /INSERT INTO recovery_token_revocations/);
  assert.match(endpoint, /results\?\.\[0\]\?\.meta\?\.changes/);
  assert.match(endpoint, /results\?\.\[1\]\?\.meta\?\.changes/);
});

test("authenticated requests reject sessions issued before or at the password-reset revocation time", () => {
  const start = worker.indexOf("async function authenticate(");
  const end = worker.indexOf("\nfunction cleanUser", start);
  assert.ok(start >= 0 && end > start, "authenticate function exists");
  const auth = worker.slice(start, end);
  assert.match(auth, /SELECT revoked_at_ms FROM recovery_token_revocations WHERE user_id = \?/);
  assert.match(auth, /payload\.iat_ms\s*\|\|\s*0\)\s*<=\s*Number\(revocation\.revoked_at_ms/);
});

test("recovery-code rotation replaces the previous code only after password confirmation", () => {
  const start = worker.indexOf('if (method === "POST" && path === "/api/recovery-code")');
  const end = worker.indexOf("// Update current user's editable profile fields", start);
  assert.ok(start >= 0 && end > start, "recovery-code rotation endpoint exists");
  const endpoint = worker.slice(start, end);
  assert.match(endpoint, /hashPassword\(password, user\.password_salt\)/);
  assert.match(endpoint, /saveRecoveryCode\(env, currentUser\.sub, recovery\)/);
  assert.match(worker, /ON CONFLICT\(user_id\) DO UPDATE SET code_hash = excluded\.code_hash/);
});
