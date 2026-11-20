import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const flutterApp = await readFile(new URL("../android/lib/main.dart", import.meta.url), "utf8");
const testConfig = await readFile(new URL("../wrangler.test.toml", import.meta.url), "utf8");
const productionConfig = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");
const replyMigration = await readFile(new URL("../migrations/0004_preview_message_replies.sql", import.meta.url), "utf8");

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

test("message deletion is authenticated and limited to the author in private and group chats", () => {
  const privateStart = worker.indexOf("privateMessageActionMatch");
  const privateEnd = worker.indexOf("// Get conversation messages", privateStart);
  const privateRoute = worker.slice(privateStart, privateEnd);
  assert.ok(privateRoute.includes('method === "DELETE"'));
  assert.ok(privateRoute.includes("sender_id = ?"));
  assert.ok(privateRoute.includes("currentUser.sub"));
  assert.ok(privateRoute.includes("DELETE FROM messages"));

  const groupStart = worker.indexOf("groupMessageActionMatch");
  const groupEnd = worker.indexOf("const groupMessagesMatch", groupStart);
  const groupRoute = worker.slice(groupStart, groupEnd);
  assert.ok(groupRoute.includes('method === "DELETE"'));
  assert.ok(groupRoute.includes("group_members"));
  assert.ok(groupRoute.includes("sender_id = ?"));
  assert.ok(groupRoute.includes("DELETE FROM group_messages"));

  assert.ok(flutterApp.includes("deletePrivateMessage"));
  assert.ok(flutterApp.includes("deleteGroupMessage"));
  assert.ok(flutterApp.includes("حذف الرسالة"));
  assert.ok(flutterApp.includes("canDelete: mine"));
});

test("private and group replies are scoped to the same conversation and retain a safe preview", () => {
  assert.ok(worker.includes('body.replyToId'));
  assert.ok(worker.includes("Reply target not found in this conversation"));
  assert.ok(worker.includes("Reply target not found in this group"));
  assert.ok(worker.includes("reply_to_body"));
  assert.ok(worker.includes("reply_to_sender_id"));
  assert.ok(worker.includes("WHERE id = ? AND group_id = ?"));
  assert.ok(worker.includes("(sender_id = ? AND receiver_id = ?)"));
  assert.ok(flutterApp.includes("الرد على الرسالة"));
  assert.ok(flutterApp.includes("replyToId:"));
  assert.ok(flutterApp.includes("messageReplyPreview"));
  assert.ok(flutterApp.includes("إلغاء الرد"));
  assert.ok(replyMigration.includes("ALTER TABLE messages ADD COLUMN reply_to_id TEXT"));
  assert.ok(replyMigration.includes("ALTER TABLE group_messages ADD COLUMN reply_to_id TEXT"));
});

test("isolated test D1 is not the production database", () => {
  const testId = testConfig.match(/database_id\s*=\s*"([^"]+)"/)?.[1];
  const productionId = productionConfig.match(/database_id\s*=\s*"([^"]+)"/)?.[1];
  assert.ok(testId, "test D1 database_id must be configured");
  assert.ok(productionId, "production D1 database_id must be configured");
  assert.notEqual(testId, productionId);
  assert.ok(testConfig.includes('database_name = "barq-phase2-test-'));
  assert.ok(testConfig.includes('name = "barq-api-phase2-test"'));
  assert.ok(testConfig.includes("workers_dev = true"));
  assert.ok(testConfig.includes('TIGRIS_BUCKET = "barq-preview-media"'));
  assert.ok(!testConfig.includes('TIGRIS_BUCKET = "siraj-media"'));
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

test("speech transcription requires authentication, validates audio, rate-limits, and uses Workers AI without persistence", () => {
  assert.ok(worker.includes('path === "/api/transcribe"'));
  const start = worker.indexOf('path === "/api/transcribe"');
  const end = worker.indexOf("// A single private invite code", start);
  const route = worker.slice(start, end);
  assert.ok(route.includes('env.AI.run("@cf/openai/whisper"'));
  assert.ok(route.includes("maxTranscriptionBytes = 2 * 1024 * 1024"));
  assert.ok(route.includes("transcription_rate_limits"));
  assert.ok(route.includes("attempts") && route.includes("> 10"));
  assert.ok(!route.includes("INSERT INTO messages"));
  assert.ok(!route.includes("sendSirajPush"));
  assert.ok(route.includes("return json({ text })"));
  assert.ok(productionConfig.includes("[ai]") && productionConfig.includes('binding = "AI"'));
  assert.ok(testConfig.includes("[ai]") && testConfig.includes('binding = "AI"'));
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

test("Flutter invite deep links reach the registration request", () => {
  assert.ok(flutterApp.includes("BarqInviteLinks.pendingCode"));
  assert.ok(flutterApp.includes("inviteCode: inviteCode.text.trim().isEmpty ? null : inviteCode.text.trim()"));
  assert.ok(flutterApp.includes("'inviteCode': inviteCode.trim().toUpperCase()"));
  assert.ok(worker.includes('body.inviteCode'));
});

test("Android API, media, and realtime origins are selectable for isolated preview builds", () => {
  assert.ok(flutterApp.includes("'BARQ_API_BASE'"));
  assert.ok(flutterApp.includes("'BARQ_MEDIA_BASE'"));
  assert.ok(flutterApp.includes("'BARQ_REALTIME_URL'"));
  assert.ok(flutterApp.includes("defaultValue: 'https://siraj-api-2026.vercel.app'"));
  assert.ok(flutterApp.includes("defaultValue: 'https://siraj-api.alhmdanybdhmhmwd.workers.dev'"));
  assert.ok(flutterApp.includes("defaultValue: 'wss://siraj-api.alhmdanybdhmhmwd.workers.dev/api/realtime'"));
});
