import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const flutterApp = await readFile(new URL("../android/lib/main.dart", import.meta.url), "utf8");
const testConfig = await readFile(new URL("../wrangler.test.toml", import.meta.url), "utf8");
const productionConfig = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");
const replyMigration = await readFile(new URL("../migrations/0004_preview_message_replies.sql", import.meta.url), "utf8");
const interactionMigration = await readFile(new URL("../migrations/0006_preview_message_reactions_pins.sql", import.meta.url), "utf8");

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

test("message editing is PATCH-only for the authenticated author in private and group chats", () => {
  const privateStart = worker.indexOf("privateMessageActionMatch");
  const privateEnd = worker.indexOf("// Get conversation messages", privateStart);
  const privateRoute = worker.slice(privateStart, privateEnd);
  assert.ok(privateRoute.includes('method === "PATCH"'));
  assert.ok(privateRoute.includes("UPDATE messages SET body = ?, edited_at = CURRENT_TIMESTAMP"));
  assert.ok(privateRoute.includes("sender_id = ?"));
  assert.ok(privateRoute.includes("currentUser.sub"));

  const groupStart = worker.indexOf("groupMessageActionMatch");
  const groupEnd = worker.indexOf("const groupMessagesMatch", groupStart);
  const groupRoute = worker.slice(groupStart, groupEnd);
  assert.ok(groupRoute.includes('method === "PATCH"'));
  assert.ok(groupRoute.includes("group_members"));
  assert.ok(groupRoute.includes("UPDATE group_messages SET body = ?, edited_at = CURRENT_TIMESTAMP"));
  assert.ok(groupRoute.includes("sender_id = ?"));
  assert.ok(groupRoute.includes("message.length > 5000"));
  assert.ok(worker.includes("gm.edited_at"));
  assert.ok(worker.includes("reply_to_sender_id, edited_at"));

  assert.ok(flutterApp.includes("editPrivateMessage"));
  assert.ok(flutterApp.includes("editGroupMessage"));
  assert.ok(flutterApp.includes("تعديل الرسالة"));
  assert.ok(flutterApp.includes("تم التعديل"));
  assert.ok(replyMigration.includes("reply_to_id"));
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


test("private and group reactions are authenticated, conversation-scoped, and idempotent", () => {
  assert.ok(worker.includes("message_reactions"));
  assert.ok(worker.includes("groupInteractionMatch"));
  assert.ok(worker.includes("privateInteractionMatch"));
  assert.ok(worker.includes("INSERT OR IGNORE INTO message_reactions"));
  assert.ok(worker.includes("DELETE FROM message_reactions"));
  assert.ok(worker.includes("group_members WHERE group_id = ? AND user_id = ?"));
  assert.ok(worker.includes("sender_id = ? OR receiver_id = ?"));
  assert.ok(worker.includes("const allowed = [\"👍\", \"❤️\", \"😂\", \"😮\", \"😢\", \"😡\", \"🎉\", \"🔥\"]"));
  assert.ok(worker.includes("item.reactions = reactionMap.get(item.id) || []"));
  assert.ok(flutterApp.includes("reactPrivateMessage"));
  assert.ok(flutterApp.includes("reactGroupMessage"));
  assert.ok(flutterApp.includes("messageReactionBar"));
  assert.ok(interactionMigration.includes("PRIMARY KEY (scope_type, scope_id, message_id, user_id, emoji)"));
});

test("private and group message pins are per-user, scoped, and removable by the pin owner", () => {
  assert.ok(worker.includes("pinned_messages"));
  assert.ok(worker.includes("pinned_by = ?"));
  assert.ok(worker.includes("DELETE FROM pinned_messages"));
  assert.ok(worker.includes("item.is_pinned = pinnedIds.has(item.id)"));
  assert.ok(flutterApp.includes("pinPrivateMessage"));
  assert.ok(flutterApp.includes("pinGroupMessage"));
  assert.ok(flutterApp.includes("تثبيت الرسالة"));
  assert.ok(flutterApp.includes("إلغاء تثبيت الرسالة"));
  assert.ok(interactionMigration.includes("PRIMARY KEY (scope_type, scope_id, message_id, pinned_by)"));
});

test("server-side message search is scoped, authenticated, bounded, and rate-limited", () => {
  const privateStart = worker.indexOf('path === "/api/messages/search"');
  const privateEnd = worker.indexOf("// Get conversation messages", privateStart);
  const privateSearch = worker.slice(privateStart, privateEnd);
  const groupStart = worker.indexOf("const groupMessageSearchMatch");
  const groupEnd = worker.indexOf("const groupMessagesMatch", groupStart);
  const groupSearch = worker.slice(groupStart, groupEnd);
  assert.ok(privateSearch.includes("friendships"));
  assert.ok(privateSearch.includes("instr(lower(m.body), lower(?))"));
  assert.ok(privateSearch.includes("message-search-private"));
  assert.ok(privateSearch.includes("Math.min(50"));
  assert.ok(privateSearch.includes("nextCursor: hasMore && oldest"));
  assert.ok(groupSearch.includes("group_members"));
  assert.ok(groupSearch.includes("instr(lower(gm.body), lower(?))"));
  assert.ok(groupSearch.includes("message-search-group"));
  assert.ok(groupSearch.includes("Math.min(50"));
  assert.ok(groupSearch.includes("nextCursor: hasMore && oldest"));
  assert.ok(flutterApp.includes("searchPrivateMessages"));
  assert.ok(flutterApp.includes("searchGroupMessages"));
  assert.ok(flutterApp.includes("جميع رسائل المحادثة"));
  assert.ok(flutterApp.includes("Api.searchPrivateMessages(friendId, query, before: before)"));
  assert.ok(flutterApp.includes("Api.searchGroupMessages(groupId, query, before: before)"));
  assert.ok(flutterApp.includes("نتائج أقدم"));
});

test("private and group message pagination uses stable compound cursors and merges without duplicates", () => {
  assert.ok(worker.includes("created_at < ? OR (created_at = ? AND id < ?)"));
  assert.ok(worker.includes("nextCursor: hasMore && oldest"));
  assert.ok(flutterApp.includes("mergeMessages(older, messages)"));
  assert.ok(flutterApp.includes("Api.messagesPage(friendId, before: olderMessageCursor)"));
  assert.ok(flutterApp.includes("Api.groupMessagesPage(groupId, before: olderMessageCursor)"));
  assert.ok(flutterApp.includes("final unique = <String, Map<String, dynamic>>{}"));
});

test("on-demand AI conversation summaries are membership-checked, rate-limited, and opt-in", () => {
  assert.match(worker, /privateSummaryMatch/);
  assert.match(worker, /groupSummaryMatch/);
  assert.match(worker, /consumeLoginAttempt\(env, "conversation-summary"/);
  assert.match(worker, /FROM group_members WHERE group_id = \? AND user_id = \?/);
  assert.match(worker, /@cf\/qwen\/qwen3\.8-27b/);
  assert.match(worker, /LIMIT 60/);
  assert.ok(flutterApp.includes("لن يبدأ إرسال الرسائل قبل ضغطك على"));
  assert.ok(flutterApp.includes("لا تُرسل المرفقات"));
});

test("recorded AAC voice messages remain eligible for explicit transcription", () => {
  assert.match(worker, /"audio\/mp4"/);
  assert.match(worker, /maxTranscriptionBytes = 2 \* 1024 \* 1024/);
  assert.match(flutterApp, /contentType: 'audio\/mp4'/);
  assert.match(flutterApp, /isBarqTranscriptionSizeAllowed\(audioBytes\.length\)/);
});


test("AI summary routes authorize conversation membership before inference and cap source messages", () => {
  const groupStart = worker.indexOf("// On-demand group summary.");
  const groupEnd = worker.indexOf("const groupMessagesMatch", groupStart);
  const groupRoute = worker.slice(groupStart, groupEnd);
  const privateStart = worker.indexOf("// On-demand private conversation summary.");
  const privateEnd = worker.indexOf("// Private reactions and pins", privateStart);
  const privateRoute = worker.slice(privateStart, privateEnd);

  assert.ok(groupStart >= 0 && privateStart >= 0);
  assert.ok(groupRoute.indexOf("group_members") < groupRoute.indexOf("createConversationSummary"));
  assert.ok(groupRoute.includes("if (!member)"));
  assert.ok(groupRoute.includes('consumeLoginAttempt(env, "conversation-summary", currentUser.sub, 5)'));
  assert.ok(groupRoute.includes("LIMIT 60"));

  assert.ok(privateRoute.includes("FROM friendships WHERE user_id = ? AND friend_id = ?"));
  assert.ok(privateRoute.indexOf("friendships") < privateRoute.indexOf("createConversationSummary"));
  assert.ok(privateRoute.includes("Conversation access denied"));
  assert.ok(privateRoute.includes('consumeLoginAttempt(env, "conversation-summary", currentUser.sub, 5)'));
  assert.ok(privateRoute.includes("LIMIT 60"));

  assert.ok(worker.includes('@cf/qwen/qwen3.8-27b'));
  assert.ok(worker.includes("prepareConversationSummaryTranscript"));
  assert.ok(flutterApp.includes("لن يبدأ إرسال الرسائل قبل ضغطك على"));
  assert.ok(flutterApp.includes("لا تُرسل المرفقات"));
  assert.ok(flutterApp.includes("لا يُحفظ الملخص كرسالة"));
});

test("speech transcription route is behind bearer authentication and never persists audio or transcript", () => {
  const authIndex = worker.indexOf("const currentUser = await authenticate(request, env)");
  const unauthorizedIndex = worker.indexOf("if (!currentUser)", authIndex);
  const routeIndex = worker.indexOf('path === "/api/transcribe"');
  const routeEnd = worker.indexOf("// A single private invite code", routeIndex);
  const route = worker.slice(routeIndex, routeEnd);
  assert.ok(authIndex >= 0 && unauthorizedIndex > authIndex && routeIndex > unauthorizedIndex);
  assert.ok(route.includes("audio/mp4"));
  assert.ok(route.includes("maxTranscriptionBytes = 2 * 1024 * 1024"));
  assert.ok(route.includes('env.AI.run("@cf/openai/whisper"'));
  assert.ok(!route.includes("INSERT INTO messages"));
  assert.ok(!route.includes("INSERT INTO group_messages"));
  assert.ok(!route.includes("sendSirajPush"));
});


test("group role management is owner-controlled and member removal respects owner/admin boundaries", () => {
  const roleStart = worker.indexOf("const groupRoleMatch");
  const roleEnd = worker.indexOf("const groupMemberActionMatch", roleStart);
  const roleRoute = worker.slice(roleStart, roleEnd);
  const removeStart = worker.indexOf("const groupMemberActionMatch");
  const removeEnd = worker.indexOf("// Group reactions", removeStart);
  const removeRoute = worker.slice(removeStart, removeEnd);

  assert.ok(roleStart >= 0 && roleRoute.includes('group.owner_id !== currentUser.sub'));
  assert.ok(roleRoute.includes("Only the group owner can manage admin roles"));
  assert.ok(roleRoute.includes("targetUserId === group.owner_id"));
  assert.ok(roleRoute.includes("role !== \"admin\" && role !== \"member\""));
  assert.ok(removeRoute.includes("selfLeave"));
  assert.ok(removeRoute.includes("actorRole !== \"owner\""));
  assert.ok(removeRoute.includes('actorRole === "admin"'));
  assert.ok(removeRoute.includes('target?.role || "member"'));

  assert.ok(flutterApp.includes("setGroupMemberRole"));
  assert.ok(flutterApp.includes("removeGroupMember"));
  assert.ok(flutterApp.includes("تعيين مشرف"));
  assert.ok(flutterApp.includes("إلغاء الإشراف"));
  assert.ok(flutterApp.includes("مغادرة المجموعة"));
  assert.ok(flutterApp.includes("current_role"));
});


test("status surfaces and notifications use the approved SPARK feature name", () => {
  assert.ok(flutterApp.includes("label: 'SPARK'"));
  assert.ok(flutterApp.includes("النشر في SPARK"));
  assert.ok(flutterApp.includes("نشر في SPARK"));
  assert.ok(flutterApp.includes("Text('SPARK'"));
  assert.ok(flutterApp.includes("حالات SPARK الجديدة"));
  assert.ok(worker.includes("شارك لحظة جديدة في SPARK"));
});


test("group ownership transfer is conditional, owner-only, and limited to existing members", () => {
  const start = worker.indexOf("const groupOwnershipMatch");
  const end = worker.indexOf("const groupMemberActionMatch", start);
  const route = worker.slice(start, end);
  assert.ok(start >= 0);
  assert.ok(route.includes('method === "POST"'));
  assert.ok(route.includes("owner_id = ?"));
  assert.ok(route.includes("owner_id = ?"));
  assert.ok(route.includes("AND EXISTS"));
  assert.ok(route.includes("FROM group_members"));
  assert.ok(route.includes("targetUserId === currentUser.sub"));
  assert.ok(route.includes("Number(results?.[0]?.meta?.changes || 0) !== 1"));
  assert.ok(route.includes("DELETE FROM group_member_roles"));
  assert.ok(flutterApp.includes("transferGroupOwnership"));
  assert.ok(flutterApp.includes("barqCanTransferGroupOwnership"));
  assert.ok(flutterApp.includes("نقل ملكية المجموعة"));
});


test("SPARK media publishing stores private image/video objects with a 24-hour lifetime", () => {
  const uploadStart = worker.indexOf('path === "/api/statuses/media"');
  const uploadEnd = worker.indexOf("// Publish a 24-hour text status", uploadStart);
  const uploadRoute = worker.slice(uploadStart, uploadEnd);
  assert.ok(uploadStart >= 0 && uploadEnd > uploadStart);
  assert.ok(uploadRoute.includes('method === "POST"'));
  assert.ok(uploadRoute.includes("image/(jpeg|png|webp|gif)|video/(mp4|webm|quicktime)"));
  assert.ok(uploadRoute.includes("60 * 1024 * 1024"));
  assert.ok(uploadRoute.includes("Date.now() + 24 * 60 * 60 * 1000"));
  assert.ok(uploadRoute.includes("CREATE TABLE IF NOT EXISTS status_media"));
  assert.ok(uploadRoute.includes("INSERT INTO media_access"));
  assert.ok(uploadRoute.includes("INSERT INTO media_expirations"));
  assert.ok(uploadRoute.includes('category: "statuses"'));
  assert.ok(uploadRoute.includes("env.DB.batch"));
  assert.ok(uploadRoute.includes("storage.fetch(storageUrl, { method: \"DELETE\" })"));
});

test("SPARK media reads enforce active friend visibility and expire with their status", () => {
  const mediaStart = worker.indexOf('path === "/api/media/"');
  const mediaEnd = worker.indexOf("return json({ error: \"Route not found\" }, 404)", mediaStart);
  const mediaRoute = worker.slice(mediaStart, mediaEnd);
  assert.ok(mediaStart >= 0);
  assert.ok(mediaRoute.includes("FROM status_media sm JOIN status_posts sp"));
  assert.ok(mediaRoute.includes("sparkMedia.ownerId === currentUser.sub"));
  assert.ok(mediaRoute.includes("FROM friendships WHERE user_id = ? AND friend_id = ?"));
  assert.ok(mediaRoute.includes("sparkMedia.expiresAt"));
  assert.ok(mediaRoute.includes("if (!accessRow && !sparkMedia)"));
  assert.ok(mediaRoute.includes("SPARK media access denied"));

  const cleanupStart = worker.indexOf("async function cleanupExpiredMedia");
  const cleanupEnd = worker.indexOf("async function cleanupExpiredEphemeralMessages", cleanupStart);
  const cleanup = worker.slice(cleanupStart, cleanupEnd);
  assert.ok(cleanup.includes("SELECT status_id FROM status_media WHERE object_key = ?"));
  assert.ok(cleanup.includes("DELETE FROM status_media WHERE status_id = ?"));
  assert.ok(cleanup.includes("DELETE FROM status_posts WHERE id = ?"));
});

test("Android SPARK media flow supports authenticated upload, caption, image/video viewing and paging", () => {
  assert.ok(flutterApp.includes("publishSparkMedia"));
  assert.ok(flutterApp.includes("X-Status-Caption"));
  assert.ok(flutterApp.includes("FileType.media"));
  assert.ok(flutterApp.includes("publishSparkMediaDialog"));
  assert.ok(flutterApp.includes("SparkMediaViewer"));
  assert.ok(flutterApp.includes("PageView.builder"));
  assert.ok(flutterApp.includes("VideoPlayerController.networkUrl"));
  assert.ok(flutterApp.includes("Api.sparkMediaUri"));
});
