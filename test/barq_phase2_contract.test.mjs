import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const testConfig = await readFile(new URL("../wrangler.test.toml", import.meta.url), "utf8");
const productionConfig = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");

function hasPath(path) {
  return worker.includes('path === "' + path + '"') ||
    worker.includes("path === '" + path + "'");
}

test("health probes and read-only readiness query are present", () => {
  assert.ok(hasPath("/health/live"));
  assert.ok(hasPath("/health/ready"));
  assert.ok(worker.includes("SELECT 1 AS ok"));
});

test("phase 2 core API route paths remain present", () => {
  const paths = [
    "/api/register", "/api/login", "/api/password/recover",
    "/api/profile", "/api/me", "/api/privacy",
    "/api/notification-settings", "/api/friends", "/api/contacts",
    "/api/contacts/match", "/api/messages", "/api/statuses", "/api/groups"
  ];
  for (const path of paths) {
    assert.ok(hasPath(path), "Missing route path " + path);
  }
});

test("isolated test D1 is not the production database", () => {
  const testId = testConfig.match(/database_id\s*=\s*"([^"]+)"/)?.[1];
  const productionId = productionConfig.match(/database_id\s*=\s*"([^"]+)"/)?.[1];
  assert.ok(testId, "test D1 database_id must be configured");
  assert.ok(productionId, "production D1 database_id must be configured");
  assert.notEqual(testId, productionId);
  assert.ok(testConfig.includes('database_name = "barq-phase2-test-'));
  assert.ok(!testConfig.includes("[vars]"));
  assert.ok(!testConfig.includes("[[routes]]"));
});

test("ephemeral messages stay private and start a ten-second expiry on first recipient read", () => {
  assert.ok(worker.includes('path === "/api/ephemeral-messages"'));
  assert.ok(worker.includes("CREATE TABLE IF NOT EXISTS ephemeral_messages"));
  assert.ok(worker.includes("SET read_at = unixepoch(), delete_at = unixepoch() + 10"));
  assert.ok(worker.includes("delete_at IS NULL OR delete_at > unixepoch()"));
  const start = worker.indexOf('path === "/api/ephemeral-messages"');
  const end = worker.indexOf("// Rotate the one-time recovery code", start);
  const route = worker.slice(start, end);
  assert.ok(route.includes("INSERT INTO ephemeral_messages"));
  assert.ok(!route.includes("sendSirajPush"), "ephemeral content must not trigger Firebase push");
});

test("private invite codes are stable per account and do not add reward mechanics", () => {
  assert.ok(worker.includes('path === "/api/referrals"'));
  assert.ok(worker.includes("CREATE TABLE IF NOT EXISTS user_invite_codes"));
  assert.ok(worker.includes("SELECT invite_code FROM user_invite_codes WHERE user_id = ?"));
  assert.ok(!worker.includes("referral_count"));
  assert.ok(!worker.includes("invite_threshold"));
});

test("private invite codes are validated and attached to the registering account", () => {
  const start = worker.indexOf('path === "/api/register"');
  const end = worker.indexOf("// Recover an account", start);
  const route = worker.slice(start, end);
  assert.ok(route.includes('body.inviteCode'));
  assert.ok(route.includes('SELECT user_id FROM user_invite_codes WHERE invite_code = ?'));
  assert.ok(route.includes("CREATE TABLE IF NOT EXISTS user_invites"));
  assert.ok(route.includes("INSERT INTO user_invites (invitee_user_id, inviter_user_id)"));
  assert.ok(route.includes("registrationStatements.push"));
  assert.ok(!route.includes("referral_count"));
  assert.ok(!route.includes("invite_threshold"));
});
