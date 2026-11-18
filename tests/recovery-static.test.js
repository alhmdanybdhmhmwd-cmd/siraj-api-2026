import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const migration = await readFile(new URL("../migrations/0001_recovery_codes.sql", import.meta.url), "utf8");
const config = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");

test("recovery migration creates only additive recovery tables", () => {
  assert.match(migration, /CREATE TABLE IF NOT EXISTS recovery_codes/i);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS recovery_rate_limits/i);
  assert.match(migration, /CREATE INDEX IF NOT EXISTS idx_recovery_rate_limits_window/i);
  assert.doesNotMatch(migration, /\b(DROP|DELETE|UPDATE|ALTER)\s+(TABLE|FROM|users|messages|friendships)\b/i);
  assert.match(migration, /FOREIGN KEY \(user_id\) REFERENCES users\(id\) ON DELETE CASCADE/i);
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
});

test("recovery attempts are rate limited by edge IP, identifier, and account, and codes are consumed", () => {
  assert.match(worker, /request\.headers\.get\("CF-Connecting-IP"\)/);
  assert.match(worker, /consumeRecoveryAttempt\(env, "ip", clientIp, 20\)/);
  assert.match(worker, /consumeRecoveryAttempt\(env, "identifier", identifier\)/);
  assert.match(worker, /consumeRecoveryAttempt\(env, "account", user\.id\)/);
  assert.match(worker, /UPDATE recovery_codes SET consumed_at = \?/);
});

test("production D1 binding and migrations directory remain configured", () => {
  assert.match(config, /binding\s*=\s*"DB"/);
  assert.match(config, /database_name\s*=\s*"siraj-db"/);
  assert.match(config, /migrations_dir\s*=\s*"migrations"/);
});
