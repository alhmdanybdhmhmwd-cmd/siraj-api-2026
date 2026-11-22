import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const flutterApp = await readFile(new URL("../android/lib/main.dart", import.meta.url), "utf8");
const androidManifest = await readFile(new URL("../android/android/app/src/main/AndroidManifest.xml", import.meta.url), "utf8");
const testConfig = await readFile(new URL("../wrangler.test.toml", import.meta.url), "utf8");
const fallbackTestConfig = await readFile(new URL("../wrangler.fallback.test.toml", import.meta.url), "utf8");
const productionConfig = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");
const replyMigration = await readFile(new URL("../migrations/0004_preview_message_replies.sql", import.meta.url), "utf8");
const interactionMigration = await readFile(new URL("../migrations/0006_preview_message_reactions_pins.sql", import.meta.url), "utf8");
const conversationMigration = await readFile(new URL("../migrations/0014_private_conversation_visibility.sql", import.meta.url), "utf8");

function hasPath(path) {
  return worker.includes('path === "' + path + '"') ||
    worker.includes("path === '" + path + "'");
}

test("Android app prevents automatic backup of private local data", () => {
  assert.match(androidManifest, /android:allowBackup="false"/);
  assert.match(androidManifest, /android:fullBackupContent="false"/);
});

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

test("private conversation clear/delete is per-account and preserves contacts", () => {
  assert.ok(conversationMigration.includes("CREATE TABLE IF NOT EXISTS hidden_private_messages"));
  assert.ok(conversationMigration.includes("CREATE TABLE IF NOT EXISTS private_conversation_state"));
  assert.ok(worker.includes('path.match(/^\\/api\\/conversations\\/([^/]+)(\\/clear)?$/)'));
  assert.ok(worker.includes("INSERT OR IGNORE INTO hidden_private_messages"));
  assert.ok(worker.includes("hm.user_id = ? AND hm.message_id = messages.id"));
  assert.ok(worker.includes("chat_hidden"));
  assert.ok(flutterApp.includes("static Future<void> clearPrivateConversation(String friendId)"));
  assert.ok(flutterApp.includes("static Future<void> deletePrivateConversation(String friendId)"));
  assert.ok(flutterApp.includes("مسح سجل المحادثة"));
  assert.ok(flutterApp.includes("حذف المحادثة"));
  assert.ok(flutterApp.includes("جهات الاتصال"));
});

test("private chat exposes the authenticated block and unblock API controls", () => {
  assert.ok(worker.includes('path === "/api/blocks" && method === "GET"'));
  assert.ok(worker.includes('path === "/api/blocks" && (method === "POST" || method === "DELETE")'));
  assert.ok(flutterApp.includes("static Future<List<Map<String, dynamic>>> blockedUsers()"));
  assert.ok(flutterApp.includes("static Future<void> blockUser(String userId)"));
  assert.ok(flutterApp.includes("static Future<void> unblockUser(String userId)"));
  assert.ok(flutterApp.includes("blockedByMe ? 'إلغاء حظر المستخدم' : 'حظر المستخدم'"));
  assert.ok(flutterApp.includes("await Api.blockUser(friendId)"));
  assert.ok(flutterApp.includes("await Api.unblockUser(friendId)"));
  assert.ok(flutterApp.includes("if (blockedByMe)"));
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
  const end = worker.indexOf("// Directional user blocks", start);
  const route = worker.slice(start, end);
  assert.ok(route.includes('ai.run("@cf/openai/whisper"'));
  assert.ok(route.includes("maxTranscriptionBytes = 2 * 1024 * 1024"));
  assert.ok(route.includes("transcription_rate_limits"));
  assert.ok(route.includes("attempts") && route.includes("> 10"));
  assert.ok(!route.includes("INSERT INTO messages"));
  assert.ok(!route.includes("sendSirajPush"));
  assert.ok(route.includes("return json({ text })"));
  assert.ok(productionConfig.includes("[ai]") && productionConfig.includes('binding = "AI"'));
  assert.ok(testConfig.includes("[ai]") && testConfig.includes('binding = "AI"'));
});

test("excluded referral and invitation mechanics are absent from BARQ registration and API", () => {
  assert.ok(!flutterApp.includes("inviteCode"));
  assert.ok(!flutterApp.includes("BarqInviteLinks"));
  assert.ok(!flutterApp.includes("inviteFriendsDialog"));
  assert.ok(!worker.includes('path === "/api/referrals"'));
  assert.ok(!worker.includes("body.inviteCode"));
  assert.ok(!worker.includes("user_invites"));
  assert.ok(!worker.includes("user_invite_codes"));
});

test("Android API, media, and realtime origins are selectable for isolated preview builds", () => {
  assert.ok(flutterApp.includes("'BARQ_API_BASE'"));
  assert.ok(flutterApp.includes("'BARQ_MEDIA_BASE'"));
  assert.ok(flutterApp.includes("'BARQ_REALTIME_URL'"));
  assert.ok(flutterApp.includes("defaultValue: 'https://siraj-api-2026.vercel.app'"));
  assert.ok(flutterApp.includes("defaultValue: '',"));
  assert.ok(flutterApp.includes("const String mediaWorkerBase = String.fromEnvironment"));
  assert.equal((flutterApp.match(/defaultValue: 'https:\/\/siraj-api-2026\.vercel\.app'/g) || []).length, 1);
  assert.ok(flutterApp.includes("defaultValue: 'https://siraj-api.alhmdanybdhmhmwd.workers.dev'"));
  assert.ok(flutterApp.includes("BARQ_MEDIA_BASE"));
  assert.ok(flutterApp.includes("BARQ_REALTIME_URL"));
  assert.ok(!flutterApp.includes(".t3.storage.dev"));
  assert.ok(flutterApp.includes("const String? fallbackTranscribeBase = null;"));
});



test("conversation hub keeps search and the three agreed sections", () => {
  const start = flutterApp.indexOf("Widget _chatsPage()");
  const end = flutterApp.indexOf("String _personName(", start);
  const page = flutterApp.slice(start, end);
  assert.ok(page.includes("ابحث في المحادثات والمجموعات"));
  assert.ok(page.includes("المحادثات"));
  assert.ok(page.includes("المجموعات"));
  assert.ok(page.includes("المكالمات"));
  assert.ok(page.includes("conversationQuery"));
  assert.ok(!flutterApp.includes("IconButton(onPressed: loadMessages, icon: const Icon(Icons.refresh))"));
});

test("message actions are opened by long press and include pin, forward, edit, and delete", () => {
  const start = flutterApp.indexOf("Future<void> showMessageActions(");
  const end = flutterApp.indexOf("Future<void> forwardBarqMessage(", start);
  const menu = flutterApp.slice(start, end);
  assert.ok(menu.includes("تثبيت الرسالة"));
  assert.ok(menu.includes("تحويل الرسالة"));
  assert.ok(menu.includes("تعديل الرسالة"));
  assert.ok(menu.includes("حذف الرسالة"));
  assert.ok(flutterApp.includes("onLongPress: () => showMessageActions("));
  assert.ok(flutterApp.includes("Api.readAttachmentBytes"));
  assert.ok(!flutterApp.includes("BarqFeatures.lightningMode"));
});

test("SPARK supports text, captioned media, replies, reactions, and authorized media reads", () => {
  assert.ok(flutterApp.includes("publishSparkMedia"));
  assert.ok(flutterApp.includes("X-Status-Caption"));
  assert.ok(worker.includes("path === \"/api/statuses/media\""));
  assert.ok(worker.includes("sparkInteractionMatch"));
  assert.ok(worker.includes("status_replies"));
  assert.ok(worker.includes("status_reactions"));
  assert.ok(worker.includes("status_media"));
});

test("chat wallpaper is selectable and persists per conversation", () => {
  assert.ok(flutterApp.includes("Icons.wallpaper_outlined"));
  assert.ok(flutterApp.includes("_chooseChatWallpaper"));
  assert.ok(flutterApp.includes("_loadChatWallpaper"));
  assert.ok(flutterApp.includes("barq_chat_wallpaper_"));
});

test("visible private and group reaction chips toggle the current user's reaction", () => {
  const start = flutterApp.indexOf("Widget messageReactionBar(");
  const end = flutterApp.indexOf("Future<void> showMessageActions(", start);
  const reactionBar = flutterApp.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.ok(reactionBar.includes("onReact(entry.key, alreadyReacted)"));
  assert.ok(reactionBar.includes("onPressed: () async"));
  assert.ok(flutterApp.includes("Api.reactPrivateMessage("));
  assert.ok(flutterApp.includes("Api.reactGroupMessage("));
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
  const routeEnd = worker.indexOf("// Directional user blocks", routeIndex);
  const route = worker.slice(routeIndex, routeEnd);
  assert.ok(authIndex >= 0 && unauthorizedIndex > authIndex && routeIndex > unauthorizedIndex);
  assert.ok(route.includes("audio/mp4"));
  assert.ok(route.includes("maxTranscriptionBytes = 2 * 1024 * 1024"));
  assert.ok(route.includes('ai.run("@cf/openai/whisper"'));
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
  assert.ok(flutterApp.includes("لحظات SPARK الجديدة"));
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
  assert.ok(route.includes("transferredGroup?.owner_id !== targetUserId"));
  assert.ok(route.includes("DELETE FROM group_member_roles"));
  assert.ok(flutterApp.includes("transferGroupOwnership"));
  assert.ok(flutterApp.includes("barqCanTransferGroupOwnership"));
  assert.ok(flutterApp.includes("نقل ملكية المجموعة"));
});


test("SPARK media publishing stores private image/video objects with a 24-hour lifetime", () => {
  const uploadStart = worker.indexOf('if (method === "POST" && path === "/api/statuses/media")');
  const uploadEnd = worker.indexOf("// Publish a 24-hour text status", uploadStart);
  const uploadRoute = worker.slice(uploadStart, uploadEnd);
  assert.ok(uploadStart >= 0 && uploadEnd > uploadStart);
  assert.ok(uploadRoute.includes("image\\/") && uploadRoute.includes("video\\/"));
  assert.ok(uploadRoute.includes("60 * 1024 * 1024"));
  assert.ok(uploadRoute.includes("Date.now() + 24 * 60 * 60 * 1000"));
  assert.ok(uploadRoute.includes("CREATE TABLE IF NOT EXISTS status_media"));
  assert.ok(uploadRoute.includes("INSERT INTO media_access"));
  assert.ok(uploadRoute.includes("INSERT INTO media_expirations"));
  assert.ok(uploadRoute.includes('category: "statuses"'));
  assert.ok(uploadRoute.includes("env.DB.batch"));
  assert.ok(uploadRoute.includes("rollbackSparkMediaUpload(env, storage, storageUrl, objectKey)"));
});

test("SPARK media reads enforce active friend visibility and expire with their status", () => {
  const mediaStart = worker.indexOf("const mediaMatch = path.match");
  const mediaEnd = worker.indexOf("return json({ error: \"Route not found\" }, 404)", mediaStart);
  const mediaRoute = worker.slice(mediaStart, mediaEnd);
  assert.ok(mediaStart >= 0);
  assert.ok(mediaRoute.includes("FROM status_media sm JOIN status_posts sp"));
  assert.ok(mediaRoute.includes("sparkMedia.ownerId === currentUser.sub"));
  assert.ok(mediaRoute.includes("FROM friendships reciprocal"));
  assert.ok(mediaRoute.includes("reciprocal.user_id = ? AND reciprocal.friend_id = ?"));
  assert.ok(mediaRoute.includes("sparkMedia.expiresAt"));
  assert.ok(mediaRoute.includes("!Number.isFinite(sparkExpiry) || sparkExpiry <= Date.now()"));
  assert.ok(mediaRoute.indexOf("sparkExpiry <= Date.now()") < mediaRoute.indexOf("permitted = sparkMedia.ownerId === currentUser.sub"));
  assert.ok(mediaRoute.includes("if (!accessRow && !sparkMedia)"));
  assert.ok(mediaRoute.includes("SPARK media access denied"));
  const sparkDeniedAt = mediaRoute.indexOf('if (!permitted) return json({ error: "SPARK media access denied" }, 403)');
  const storageHeadAt = mediaRoute.indexOf('storage.fetch(storageUrl, { method: "HEAD" })');
  assert.ok(sparkDeniedAt >= 0 && storageHeadAt > sparkDeniedAt, "SPARK authorization must finish before storage HEAD");

  const cleanupStart = worker.indexOf("async function cleanupExpiredMedia");
  const cleanupEnd = worker.indexOf("async function cleanupExpiredEphemeralMessages", cleanupStart);
  const cleanup = worker.slice(cleanupStart, cleanupEnd);
  assert.ok(cleanup.includes("DELETE FROM status_media WHERE object_key = ?"));
  assert.ok(cleanup.includes("DELETE FROM status_reactions WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"));
  assert.ok(cleanup.includes("DELETE FROM status_replies WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"));
  assert.ok(cleanup.includes("DELETE FROM status_media WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"));
  assert.ok(cleanup.includes("DELETE FROM status_posts WHERE expires_at <= ?"));
});

test("Android SPARK media flow supports authenticated upload, caption, image/video viewing and paging", () => {
  assert.ok(flutterApp.includes("publishSparkMedia"));
  assert.ok(flutterApp.includes("X-Status-Caption"));
  assert.ok(flutterApp.includes("AssetPicker.pickAssets"));
  assert.ok(flutterApp.includes("RequestType.common"));
  assert.ok(flutterApp.includes("title: 'اختيار صور للذكرى'"));
  assert.ok(flutterApp.includes("title: 'اختيار صورة الملف الشخصي'"));
  assert.ok(flutterApp.includes("allowFiles: false"));
  assert.ok(flutterApp.includes("publishSparkMediaDialog"));
  assert.ok(flutterApp.includes("SparkMediaViewer"));
  assert.ok(flutterApp.includes("PageView.builder"));
  assert.ok(flutterApp.includes("VideoPlayerController.networkUrl"));
  assert.ok(flutterApp.includes("Api.sparkMediaUri"));
});


test("media reads and small uploads prefer the public API gateway with Worker fallback", () => {
  assert.ok(flutterApp.includes("static Future<http.Response> _postMediaPathResponse("));
  assert.ok(flutterApp.includes("static Future<http.Response> _getMediaPathResponse("));
  assert.ok(flutterApp.includes("final bases = bytes.length <= proxyMediaThresholdBytes"));
  assert.ok(flutterApp.includes("'$apiBase/api/media/"));
  assert.ok(flutterApp.includes("static Uri sparkMediaUri"));
  assert.ok(flutterApp.includes("final bases = <String>[apiBase, if (mediaWorkerBase != apiBase) mediaWorkerBase]"));
  assert.ok(flutterApp.includes("'/api/private-memories/"));
  assert.ok(flutterApp.includes("'/api/statuses/"));
});

test("media picker reads files on demand instead of eagerly retaining every selected file", () => {
  assert.ok(flutterApp.includes("Future<Uint8List> readBarqPickedFileBytes"));
  assert.ok(flutterApp.includes("File(photos[index]['path'] as String)"));
  assert.doesNotMatch(flutterApp, /withData:\s*true/);
});

test("private and group conversation polling stops in background and resumes cleanly", () => {
  for (const className of ["_ChatPageState", "_GroupChatPageState"]) {
    const start = flutterApp.indexOf("class " + className);
    assert.ok(start >= 0, "Missing " + className);
    const next = flutterApp.indexOf("\nclass ", start + 1);
    const stateSource = flutterApp.slice(start, next < 0 ? undefined : next);
    assert.ok(stateSource.includes("with WidgetsBindingObserver"));
    assert.ok(stateSource.includes("didChangeAppLifecycleState"));
    assert.ok(stateSource.includes("_startRefreshTimer"));
    assert.ok(stateSource.includes("_stopRefreshTimer"));
    assert.ok(stateSource.includes("barqShouldPauseBackgroundWork(state)"));
  }
});

test("SPARK media upload metadata headers are allowed by Worker CORS", () => {
  assert.ok(worker.includes("X-Status-Caption, X-Status-Id"));
});

test("SPARK stories can group multiple media objects under one owner-controlled status id", () => {
  const uploadStart = worker.indexOf('if (method === "POST" && path === "/api/statuses/media")');
  const uploadEnd = worker.indexOf("// Publish a 24-hour text status", uploadStart);
  const route = worker.slice(uploadStart, uploadEnd);
  assert.ok(route.includes('request.headers.get("X-Status-Id")'));
  assert.ok(route.includes("existingStatus.user_id !== currentUser.sub"));
  assert.ok(route.includes("status_id TEXT NOT NULL"));
  assert.ok(route.includes("INSERT INTO status_media (id, status_id, object_key"));
  assert.ok(route.includes("if (!requestedStatusId)"));
  assert.ok(route.includes("existingStatusExpiry"));
  assert.ok(flutterApp.includes("'X-Status-Id': statusId"));
  assert.ok(flutterApp.includes("allowMultiple: true"));
  assert.ok(flutterApp.includes("for (final item in prepared)"));
});

test("SPARK text statuses accept only allowlisted style keys and return persisted style fields", () => {
  assert.ok(worker.includes('const SPARK_STATUS_BACKGROUNDS = new Set(["electric_blue", "violet", "gold", "midnight"])'));
  assert.ok(worker.includes('const SPARK_STATUS_TEXT_COLORS = new Set(["white", "black", "gold"])'));
  assert.ok(worker.includes('const SPARK_STATUS_FONTS = new Set(["modern", "classic", "mono"])'));
  assert.ok(worker.includes('typeof backgroundKey !== "string" || !SPARK_STATUS_BACKGROUNDS.has(backgroundKey)'));
  assert.ok(worker.includes('typeof textColorKey !== "string" || !SPARK_STATUS_TEXT_COLORS.has(textColorKey)'));
  assert.ok(worker.includes('typeof fontKey !== "string" || !SPARK_STATUS_FONTS.has(fontKey)'));
  assert.ok(worker.includes('(backgroundKey === "gold" && textColorKey !== "black")'));
  assert.ok(worker.includes('(backgroundKey !== "gold" && textColorKey === "black")'));
  assert.ok(flutterApp.includes(".where((entry) => backgroundKey == 'gold' ? entry.key == 'black' : entry.key != 'black')"));
  assert.ok(worker.includes("ensureSparkStatusStyleColumns(env)"));
  assert.ok(worker.includes("s.background_key AS backgroundKey"));
  assert.ok(worker.includes("s.text_color_key AS textColorKey"));
  assert.ok(worker.includes("s.font_key AS fontKey"));
  assert.ok(worker.includes("DEFAULT 'midnight'"));
  assert.ok(worker.includes("DEFAULT 'white'"));
  assert.ok(worker.includes("DEFAULT 'modern'"));
  assert.ok(flutterApp.includes("backgroundKey: backgroundKey"));
  assert.ok(flutterApp.includes("textColorKey: textColorKey"));
  assert.ok(flutterApp.includes("fontKey: fontKey"));
  assert.ok(flutterApp.includes("معاينة لحظتك"));
  assert.ok(flutterApp.includes("backgroundKey: field(status"));
});

test("SPARK text formatting is applied only to text-only status viewing, not media presentation", () => {
  const viewerStart = flutterApp.indexOf("class SparkMediaViewer");
  const viewerEnd = flutterApp.indexOf("class _SparkAudioReplyTile", viewerStart);
  const viewer = flutterApp.slice(viewerStart, viewerEnd);
  assert.ok(viewer.includes("widget.media.isEmpty"));
  assert.ok(viewer.includes("widget.backgroundKey"));
  assert.ok(viewer.includes("widget.textColorKey"));
  assert.ok(viewer.includes("widget.fontKey"));
  const mediaBranch = viewer.slice(viewer.indexOf(": PageView.builder"), viewer.indexOf("          ),\n          Container", viewer.indexOf(": PageView.builder")));
  assert.ok(!mediaBranch.includes("widget.backgroundKey"));
  assert.ok(!mediaBranch.includes("widget.fontKey"));
});

test("SPARK media expiration cleanup is scheduled and preserves failed deletion retries", () => {
  assert.ok(productionConfig.includes('crons = ["*/15 * * * *"]'));
  const scheduledStart = worker.indexOf("async scheduled(_controller, env)");
  const scheduledEnd = worker.indexOf("async fetch(request, env, ctx)", scheduledStart);
  const scheduled = worker.slice(scheduledStart, scheduledEnd);
  assert.ok(scheduledStart >= 0 && scheduledEnd > scheduledStart);
  assert.ok(scheduled.includes("run: () => cleanupExpiredMedia(env)"));

  const cleanupStart = worker.indexOf("async function cleanupExpiredMedia");
  const cleanupEnd = worker.indexOf("async function cleanupExpiredEphemeralMessages", cleanupStart);
  const cleanup = worker.slice(cleanupStart, cleanupEnd);
  const successGate = cleanup.indexOf("if (response.ok || response.status === 404)");
  const expirationDelete = cleanup.indexOf('DELETE FROM media_expirations WHERE object_key = ? AND expires_at <= ?');
  const failureBranch = cleanup.indexOf('else {\n        console.error("Expired media deletion failed:", response.status);');
  assert.ok(successGate >= 0 && expirationDelete > successGate);
  assert.ok(failureBranch > expirationDelete, "failed storage deletion must retain its expiration row for retry");
  const retryCatchStart = cleanup.indexOf("} catch (error) {", failureBranch);
  const retryCatchEnd = cleanup.indexOf("\n    }", retryCatchStart);
  const retryCatch = cleanup.slice(retryCatchStart, retryCatchEnd);
  assert.ok(retryCatch.includes("Expired media cleanup item failed"));
  assert.ok(!retryCatch.includes("DELETE FROM media_expirations"), "network/storage exceptions must preserve the retry record");
  assert.ok(cleanup.includes("response.status === 404"), "already-missing objects must be treated as successfully cleaned");
  assert.ok(cleanup.includes("LIMIT 100"), "scheduled cleanup must process a bounded batch");
  assert.ok(cleanup.includes("Skipping invalid media expiration key"), "invalid object keys must never reach storage");
  assert.ok(cleanup.includes("deleted++;"), "only successfully deleted or already-missing objects count as deleted");
});

test("SPARK voice replies are private, limited, tied to status expiry, and cleaned from Tigris", () => {
  const start = worker.indexOf("const sparkAudioReplyMatch");
  const end = worker.indexOf("// SPARK replies and reactions", start);
  const route = worker.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.ok(route.includes('method === "POST"'));
  assert.ok(route.includes('method === "GET"'));
  assert.ok(route.includes('expires_at > CURRENT_TIMESTAMP'));
  assert.ok(route.includes("FROM friendships reciprocal"));
  assert.ok(route.includes('consumeLoginAttempt(env, "spark_audio_reply"'));
  assert.ok(route.includes("durationMs > 60000"));
  assert.ok(route.includes("5 * 1024 * 1024"));
  assert.ok(route.includes('audioSignature !== "ftyp"'));
  assert.ok(route.includes("INSERT INTO status_audio_replies"));
  assert.ok(route.includes("INSERT INTO media_expirations"));
  assert.ok(route.includes("statusId.length > 128"));
  assert.ok(route.includes("audioReplyId.length > 128"));
  assert.ok(route.includes("rollbackSparkMediaUpload(env, storage, storageUrl, objectKey)"));
  const friendshipDeniedAt = route.indexOf("if (!friendship) return json({ error: \"SPARK status access denied\" }, 403)");
  const firstStorageWriteAt = route.indexOf('storage.fetch(storageUrl, {');
  assert.ok(friendshipDeniedAt >= 0 && firstStorageWriteAt > friendshipDeniedAt, "SPARK audio access must be authorized before storage operations");
  const audioReadAt = route.indexOf("const media = await storage.fetch(storageUrl)");
  assert.ok(audioReadAt > friendshipDeniedAt, "SPARK audio download must follow reciprocal-friend authorization");
  assert.ok(worker.includes("INSERT INTO media_expirations (object_key, expires_at) VALUES (?, ?) ON CONFLICT(object_key) DO UPDATE SET expires_at = excluded.expires_at"));
  assert.ok(route.includes('"Cache-Control": "private, no-store"'));
  const cleanupStart = worker.indexOf("async function cleanupExpiredMedia");
  const cleanupEnd = worker.indexOf("async function cleanupExpiredEphemeralMessages", cleanupStart);
  const cleanup = worker.slice(cleanupStart, cleanupEnd);
  assert.ok(cleanup.includes("DELETE FROM status_audio_replies WHERE object_key = ?"));
  assert.ok(cleanup.includes("DELETE FROM status_audio_replies WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"));
});

test("Android SPARK viewer records up to 60-second AAC voice replies and plays authorized audio", () => {
  assert.ok(flutterApp.includes("AudioRecorder"));
  assert.ok(flutterApp.includes("AudioEncoder.aacLc"));
  assert.ok(flutterApp.includes("_finishAudioReplyRecording"));
  assert.ok(flutterApp.includes("_recordingClock"));
  assert.ok(flutterApp.includes("uploadSparkAudioReply"));
  assert.ok(flutterApp.includes("fetchSparkAudioReplyBytes"));
  assert.ok(flutterApp.includes("_SparkAudioReplyTile"));
  assert.ok(flutterApp.includes("X-Audio-Duration-Ms"));
  assert.ok(flutterApp.includes("_audioRecorder.hasPermission()"));
});

test("SPARK reactions and replies require an active status visible to the requesting contact", () => {
  const start = worker.indexOf("const sparkInteractionMatch");
  const end = worker.indexOf("// Ensure privacy preferences table exists", start);
  const route = worker.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.ok(route.includes("expires_at > CURRENT_TIMESTAMP"));
  assert.ok(route.includes("FROM friendships reciprocal"));
  assert.ok(route.includes("reciprocal.user_id = ? AND reciprocal.friend_id = ?"));
  assert.ok(route.includes("CREATE TABLE IF NOT EXISTS status_reactions"));
  assert.ok(route.includes("CREATE TABLE IF NOT EXISTS status_replies"));
  assert.ok(route.includes("INSERT OR IGNORE INTO status_reactions"));
  assert.ok(route.includes("DELETE FROM status_reactions"));
  assert.ok(route.includes("INSERT INTO status_replies"));
  assert.ok(route.includes("consumeLoginAttempt(env, \"spark_reply\""));
  assert.ok(flutterApp.includes("reactSparkStatus"));
  assert.ok(flutterApp.includes("replyToSpark"));
  assert.ok(flutterApp.includes("لا توجد ردود بعد"));
});


test("SPARK status feeds and push notifications are restricted to reciprocal contacts", () => {
  const listStart = worker.indexOf("// List active statuses from the current user and their friends");
  const listEnd = worker.indexOf("const statuses = result.results || [];", listStart);
  const listRoute = worker.slice(listStart, listEnd);
  assert.ok(listRoute.includes("f.user_id = ? AND f.friend_id = s.user_id"));
  assert.ok(listRoute.includes("FROM friendships reciprocal"));
  assert.ok(listRoute.includes("reciprocal.user_id = s.user_id AND reciprocal.friend_id = ?"));
  const mediaUploadStart = worker.indexOf('if (method === "POST" && path === "/api/statuses/media")');
  const mediaUploadEnd = worker.indexOf("// Publish a 24-hour text status", mediaUploadStart);
  const mediaUpload = worker.slice(mediaUploadStart, mediaUploadEnd);
  assert.ok(mediaUpload.includes("reciprocal.user_id = f.friend_id AND reciprocal.friend_id = ?"));
  assert.ok(worker.includes("شارك لحظة جديدة في SPARK"));
});


test("SPARK view tracking is unique per viewer and only the owner can inspect viewer identities", () => {
  const start = worker.indexOf("const sparkViewerMatch");
  const end = worker.indexOf("// SPARK replies and reactions", start);
  const route = worker.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.ok(route.includes("INSERT OR IGNORE INTO status_views"));
  assert.ok(route.includes("SELECT COUNT(*) AS count FROM status_views"));
  assert.ok(route.includes("status.user_id !== currentUser.sub"));
  assert.ok(route.includes("Only the status owner can view this list"));
  assert.ok(route.includes("FROM status_views sv JOIN users u"));
  assert.ok(flutterApp.includes("markSparkViewed"));
  assert.ok(flutterApp.includes("sparkViewers"));
  assert.ok(flutterApp.includes("مشاهدو SPARK"));
  assert.ok(flutterApp.includes("viewCount"));
});


test("SPARK media uploads validate file signatures and enforce the ten-item server limit", () => {
  assert.ok(worker.includes("function detectSparkMediaType(bytes)"));
  assert.ok(worker.includes("detectSparkMediaType(bytes) !== contentType"));
  assert.ok(worker.includes('ascii(4, 8) === "ftyp"'));
  assert.ok(worker.includes('ascii(8, 12) === "qt  " ? "video/quicktime" : "video/mp4"'), "SPARK MOV files selected by Android must pass server MIME validation");
  assert.ok(worker.includes('ascii(0, 6) === "GIF87a"'));
  const uploadStart = worker.indexOf('if (method === "POST" && path === "/api/statuses/media")');
  const uploadEnd = worker.indexOf("// Publish a 24-hour text status", uploadStart);
  const uploadRoute = worker.slice(uploadStart, uploadEnd);
  assert.ok(uploadRoute.includes("SELECT COUNT(*) AS count FROM status_media WHERE status_id = ?"));
  assert.ok(uploadRoute.includes("existingMediaCount?.count || 0) >= 10"));
  assert.ok(uploadRoute.includes("WHERE (SELECT COUNT(*) FROM status_media WHERE status_id = ?) < 10"));
  assert.ok(uploadRoute.includes("savedRows?.[mediaInsertIndex]?.meta?.changes || 0) !== 1"));
  assert.ok(uploadRoute.includes("at most 10 media files"));
});


test("SPARK audio replies enforce active-status friendship, duration, size, and cleanup contracts", () => {
  const routeStart = worker.indexOf("sparkAudioReplyMatch = path.match");
  const routeEnd = worker.indexOf("// SPARK replies and reactions are available only while the status is active and visible.", routeStart);
  const route = worker.slice(routeStart, routeEnd);
  assert.ok(routeStart >= 0 && routeEnd > routeStart);
  assert.ok(route.includes("expires_at > CURRENT_TIMESTAMP"));
  assert.ok(route.includes("reciprocal.user_id = ? AND reciprocal.friend_id = ?"));
  assert.ok(route.includes('contentType !== "audio/mp4"'));
  assert.ok(route.includes("durationMs < 1000 || durationMs > 60000"));
  assert.ok(route.includes("const maxAudioReplyBytes = 5 * 1024 * 1024"));
  assert.ok(route.includes("readRequestBodyLimited(request, maxAudioReplyBytes)"));
  assert.ok(route.includes('audioSignature !== "ftyp"'));
  assert.ok(route.includes("rollbackSparkMediaUpload(env, storage, storageUrl, objectKey)"));
  assert.ok(route.includes("WHERE r.id = ? AND r.status_id = ? AND s.expires_at > CURRENT_TIMESTAMP"));
  assert.ok(route.includes('if (method === "GET" && !audioReplyId)'));
  assert.ok(route.includes('if (method === "GET" && audioReplyId)'));
  assert.ok(flutterApp.includes("AudioEncoder.aacLc"));
  assert.ok(flutterApp.includes("seconds >= 60"));
  assert.ok(flutterApp.includes("durationMs < 1000"));
  assert.ok(flutterApp.includes("bytes.length > 5 * 1024 * 1024"));
});


test("SPARK scheduled cleanup removes expired audio reply metadata with its media object", () => {
  const cleanupStart = worker.indexOf("async function cleanupExpiredMedia");
  const cleanupEnd = worker.indexOf("async function cleanupExpiredEphemeralMessages", cleanupStart);
  const cleanup = worker.slice(cleanupStart, cleanupEnd);
  assert.ok(cleanupStart >= 0 && cleanupEnd > cleanupStart);
  assert.ok(cleanup.includes('DELETE FROM status_audio_replies WHERE object_key = ?'));
  assert.ok(cleanup.includes('DELETE FROM status_audio_replies WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)'));
  assert.ok(cleanup.includes('DELETE FROM media_expirations WHERE object_key = ? AND expires_at <= ?'));
  assert.ok(cleanup.includes('if (response.ok || response.status === 404)'));
});


test("SPARK audio downloads and media reads authorize viewers before touching Tigris", () => {
  const audioStart = worker.indexOf("const sparkAudioReplyMatch = path.match");
  const audioEnd = worker.indexOf("// SPARK replies and reactions are available only while the status is active and visible.", audioStart);
  const audioRoute = worker.slice(audioStart, audioEnd);
  assert.ok(audioStart >= 0 && audioEnd > audioStart);
  const audioFriendship = audioRoute.indexOf("if (!friendship) return json({ error: \"SPARK status access denied\" }, 403)");
  const audioStorage = audioRoute.indexOf("storage.fetch(storageUrl)");
  assert.ok(audioFriendship >= 0 && audioStorage > audioFriendship,
    "audio reply access must be authorized before downloading from Tigris");
  assert.ok(audioRoute.includes("s.expires_at > CURRENT_TIMESTAMP"));

  const mediaStart = worker.indexOf("const mediaMatch = path.match");
  const mediaEnd = worker.indexOf('return json({ error: "Route not found" }, 404);', mediaStart);
  const mediaRoute = worker.slice(mediaStart, mediaEnd);
  assert.ok(mediaStart >= 0 && mediaEnd > mediaStart);
  const mediaFriendship = mediaRoute.indexOf("reciprocal.user_id = ? AND reciprocal.friend_id = ?");
  const mediaDenied = mediaRoute.indexOf('if (!permitted) return json({ error: "SPARK media access denied" }, 403)');
  const mediaHead = mediaRoute.indexOf('storage.fetch(storageUrl, { method: "HEAD" })');
  assert.ok(mediaFriendship >= 0 && mediaDenied > mediaFriendship && mediaHead > mediaDenied,
    "SPARK media must require reciprocal friendship before any storage HEAD request");
  assert.ok(mediaRoute.includes("sparkExpiry <= Date.now()"));
});


test("private memories are owner-scoped with bounded create, edit, and delete operations", () => {
  const start = worker.indexOf("if (path === \"/api/private-memories\" || path.startsWith(\"/api/private-memories/\"))");
  const end = worker.indexOf("// Explicitly requested speech transcription", start);
  const route = worker.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.ok(route.includes("CREATE TABLE IF NOT EXISTS private_memories"));
  assert.ok(route.includes("owner_id TEXT NOT NULL"));
  assert.ok(route.includes("WHERE owner_id = ? ORDER BY updated_at DESC"));
  assert.ok(route.includes("LIMIT 200"));
  assert.ok(route.includes("title.length > 120"));
  assert.ok(route.includes("content.length > 10000"));
  assert.ok(route.includes('["text", "message"].includes(sourceType)'));
  assert.ok(route.includes("WHERE id = ? AND owner_id = ?"));
  assert.ok(route.includes("UPDATE private_memories SET title = ?, content = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_id = ?"));
  assert.ok(route.includes("DELETE FROM private_memories WHERE id = ? AND owner_id = ?"));
  assert.ok(worker.includes('"Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS"'));
});


test("private memory photos are owner-only, size-limited, and scheduled for cleanup on memory deletion", () => {
  const start = worker.indexOf("const memoryPathPrefix = \"/api/private-memories/\";");
  const end = worker.indexOf("const memoryIdOnly", start);
  const upload = worker.slice(start, end);
  assert.ok(start >= 0 && end > start);
  assert.ok(upload.includes("WHERE id = ? AND owner_id = ?"));
  assert.ok(upload.includes('["image/jpeg", "image/png", "image/webp"]'));
  assert.ok(upload.includes("const maxPhotoBytes = 4 * 1024 * 1024"));
  assert.ok(upload.includes("readRequestBodyLimited(request, maxPhotoBytes)"));
  assert.ok(upload.includes("detectProfileImageType(bytes) !== contentType"));
  assert.ok(upload.includes("INSERT INTO private_memory_media"));
  assert.ok(upload.includes("INSERT INTO media_access"));
  assert.ok(upload.includes("rollbackSparkMediaUpload(env, storage, storageUrl, objectKey)"));

  const routeStart = worker.indexOf("if (path === \"/api/private-memories\" || path.startsWith(\"/api/private-memories/\"))");
  const routeEnd = worker.indexOf("// Explicitly requested speech transcription", routeStart);
  const route = worker.slice(routeStart, routeEnd);
  assert.ok(route.includes("WHERE owner_id = ? ORDER BY updated_at DESC"));
  assert.ok(route.includes("FROM private_memory_media WHERE owner_id = ?"));
  assert.ok(route.includes("INSERT INTO media_expirations (object_key, expires_at)"));
  assert.ok(route.includes("DELETE FROM media_access WHERE object_key = ?"));
  assert.ok(route.includes("DELETE FROM private_memory_media WHERE memory_id = ? AND owner_id = ? AND object_key = ?"));
});

test("Worker CORS matches the public gateway for resumable media and range downloads", () => {
  assert.match(worker, /"Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS"/);
  assert.match(worker, /"Access-Control-Allow-Headers": "[^"]*Range[^"]*X-Idempotency-Key/);
  assert.match(worker, /"Access-Control-Expose-Headers": "[^"]*(?:Content-Range[^"]*Accept-Ranges|Accept-Ranges[^"]*Content-Range)/);
});

test("fallback Worker is isolated from production and shares only Preview data resources", () => {
  assert.match(fallbackTestConfig, /^name = "barq-api-phase2-fallback-test"$/m);
  assert.match(fallbackTestConfig, /^workers_dev = true$/m);
  assert.match(fallbackTestConfig, /database_id = "5bfada32-4f9b-4edb-85dd-3b3b30ab73b0"/);
  assert.match(fallbackTestConfig, /TIGRIS_BUCKET = "barq-preview-media"/);
  assert.doesNotMatch(fallbackTestConfig, /^routes\s*=/m);
  assert.doesNotMatch(fallbackTestConfig, /^crons\s*=/m);
  assert.match(testConfig, /database_id = "5bfada32-4f9b-4edb-85dd-3b3b30ab73b0"/);
  assert.match(productionConfig, /database_id = "0db93afd-4bf5-4423-9e25-7a2f4f4bdbe0"/);
  assert.doesNotMatch(fallbackTestConfig, /0db93afd-4bf5-4423-9e25-7a2f4f4bdbe0/);
  assert.doesNotMatch(fallbackTestConfig, /siraj-media/);
});

test("fallback Worker deployment requires explicit manual Preview approval", async () => {
  const workflow = await readFile(new URL("../.github/workflows/barq-preview-fallback-deploy.yml", import.meta.url), "utf8");
  assert.match(workflow, /workflow_dispatch:/);
  assert.match(workflow, /default: false/);
  assert.match(workflow, /inputs\.deploy_preview_fallback == true/);
  assert.match(workflow, /wrangler\.fallback\.test\.toml/);
  assert.doesNotMatch(workflow, /wrangler\.toml\s/);
});
