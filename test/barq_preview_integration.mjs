import assert from "node:assert/strict";
import { createHash, randomInt, randomUUID } from "node:crypto";

const base = process.env.BARQ_PREVIEW_URL;
if (!base) {
  console.log("Preview integration skipped: BARQ_PREVIEW_URL is not configured.");
} else {
  const isWorkersPreview = /^https:\/\/[a-z0-9.-]+\.workers\.dev$/i.test(base);
  const isVercelPreview = /^https:\/\/[a-z0-9.-]+\.vercel\.app$/i.test(base);
  if (!isWorkersPreview && !isVercelPreview) {
    throw new Error("BARQ_PREVIEW_URL must target the isolated Worker or its Vercel Preview proxy");
  }

async function call(path, { method = "GET", token, body, expected = 200 } = {}) {
  const response = await fetch(new URL(path, base), {
    method,
    headers: {
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });
  const raw = await response.text();
  let data;
  try { data = raw ? JSON.parse(raw) : {}; } catch { throw new Error(`${method} ${path}: non-JSON response (${response.status})`); }
  assert.equal(response.status, expected, `${method} ${path}: ${JSON.stringify(data)}`);
  return data;
}

const digits = () => String(randomInt(1000000, 9999999));
const password = "Preview-Test-" + randomUUID().slice(0, 8);
const suffix = randomUUID().replaceAll("-", "").slice(0, 8);
const accountAPhone = "+1202" + digits();
const accountA = {
  name: "Preview Alpha " + suffix,
  displayName: "Preview Alpha " + suffix,
  username: "barq" + createHash("sha256").update(accountAPhone).digest("hex").slice(0, 16),
  phone: accountAPhone,
  password
};
const accountB = { displayName: "Preview Beta " + suffix, username: "pb" + suffix, phone: "+1202" + digits(), password };

const a = await call("/api/register", { method: "POST", body: accountA, expected: 201 });
assert.ok(a.user?.id && a.token && /^[A-F0-9]{40}$/.test(a.recoveryCode || ""), "registration must return user, session and recovery code");
const b = await call("/api/register", { method: "POST", body: accountB, expected: 201 });
assert.ok(b.user?.id && b.token, "second account registration must return a session");

const login = await call("/api/login", { method: "POST", body: { username: accountA.phone, password } });
assert.ok(login.token && login.user.id === a.user.id, "phone login must return the created account");
await call("/api/login", {
  method: "POST", body: { username: accountA.phone, password: "Wrong-Preview-Password" }, expected: 401
});
await call("/api/register", {
  method: "POST", body: accountA, expected: 409
});
await call("/api/register", {
  method: "POST", body: { phone: "+12025550123", password }, expected: 400
});

const me = await call("/api/me", { token: a.token });
assert.equal(me.user.id, a.user.id);

// Optional identity packages must require authentication and return the expected
// versioned palette data before the Android client caches or enables them.
await call("/api/identity-packages/purpleShadow", { expected: 401 });
for (const identity of ["purpleShadow", "skyJewel"]) {
  const bundle = await call("/api/identity-packages/" + identity, { token: a.token });
  assert.equal(bundle.identity, identity);
  assert.equal(bundle.version, "1.0.0");
  assert.ok(bundle.palette?.primary && bundle.palette?.background && bundle.palette?.tagline);
}
await call("/api/identity-packages/blueLightning", { token: a.token, expected: 404 });
const updatedName = "Preview Updated " + suffix;
const attemptedPhoneChange = accountA.phone.slice(0, -1) + (accountA.phone.endsWith("0") ? "1" : "0");
const profile = await call("/api/profile", {
  method: "POST", token: a.token,
  body: { displayName: updatedName, phone: attemptedPhoneChange }
});
assert.equal(profile.user.displayName, updatedName);
assert.equal(profile.user.phone, accountA.phone,
  "profile edits must ignore attempts to change the immutable registration phone number");

const privacyOff = await call("/api/privacy", {
  method: "POST", token: b.token, body: { searchable: false, readReceipts: false }
});
assert.equal(privacyOff.privacy.searchable, false);
const hiddenMatch = await call("/api/contacts/match", {
  method: "POST", token: a.token, body: { phones: [accountB.phone] }
});
assert.equal(hiddenMatch.users.length, 0, "non-searchable accounts must not appear in contact matching");

await call("/api/privacy", {
  method: "POST", token: b.token, body: { searchable: true }
});
const arabicDigits = accountB.phone.replace(/[0-9]/g, d => String.fromCharCode(0x0660 + Number(d)));
const matches = await call("/api/contacts/match", {
  method: "POST", token: a.token, body: { phones: [arabicDigits] }
});
assert.ok(matches.users.some(user => user.id === b.user.id), "contact matching must normalize Arabic-Indic digits");

await call("/api/contacts", { method: "POST", token: a.token, body: { userId: b.user.id }, expected: 201 });
const friendsA = await call("/api/friends", { token: a.token });
const friendsB = await call("/api/friends", { token: b.token });
assert.ok(friendsA.friends.some(user => user.id === b.user.id), "contact addition must create the sender's contact link");
assert.ok(friendsB.friends.some(user => user.id === a.user.id), "contact addition must be reciprocal");


// A lost response followed by an offline-outbox retry must persist and notify
// only one message. Reusing an ID for a different sender/recipient is rejected.
// Keep the id unique across persistent Preview runs so reruns remain idempotent within each attempt.
const clientMessageId = randomUUID().replaceAll("-", "");
const firstMessage = await call("/api/messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "idempotency integration check", clientMessageId },
  expected: 201
});
assert.equal(firstMessage.id, clientMessageId);
await call("/api/messages/" + encodeURIComponent(clientMessageId) + "/reactions", {
  method: "POST", token: a.token, body: { emoji: "🔥" }
});
await call("/api/messages/" + encodeURIComponent(clientMessageId) + "/pin", {
  method: "POST", token: a.token
});
const interactedPrivate = await call("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
const privateInteraction = interactedPrivate.messages.find(message => message.id === clientMessageId);
assert.ok(privateInteraction?.is_pinned, "private pin must be returned by the conversation API");
assert.ok(privateInteraction?.reactions?.some(reaction => reaction.emoji === "🔥" && reaction.user_id === a.user.id),
  "private reaction must be returned by the conversation API");
await call("/api/messages/" + encodeURIComponent(clientMessageId) + "/pin", {
  method: "DELETE", token: a.token
});
await call("/api/messages/" + encodeURIComponent(clientMessageId) + "/reactions?emoji=" + encodeURIComponent("🔥"), {
  method: "DELETE", token: a.token
});
const retriedMessage = await call("/api/messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "idempotency integration check", clientMessageId }
});
assert.equal(retriedMessage.id, clientMessageId);
assert.equal(retriedMessage.duplicate, true, "same client ID must be acknowledged as a duplicate");
await call("/api/messages", {
  method: "POST", token: b.token,
  body: { receiverId: a.user.id, body: "different owner", clientMessageId },
  expected: 409
});



const secondPrivateId = randomUUID().replaceAll("-", "");
await call("/api/messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "second integration pagination fixture", clientMessageId: secondPrivateId },
  expected: 201
});
const firstPrivatePage = await call("/api/messages?with=" + encodeURIComponent(b.user.id) + "&limit=1", { token: a.token });
assert.equal(firstPrivatePage.messages.length, 1);
assert.equal(firstPrivatePage.hasMore, true, "private history must advertise older pages");
assert.ok(firstPrivatePage.nextCursor?.before && firstPrivatePage.nextCursor?.beforeId);
const olderPrivatePage = await call("/api/messages?with=" + encodeURIComponent(b.user.id) +
  "&limit=1&before=" + encodeURIComponent(firstPrivatePage.nextCursor.before) +
  "&beforeId=" + encodeURIComponent(firstPrivatePage.nextCursor.beforeId), { token: a.token });
assert.equal(olderPrivatePage.messages.length, 1);
assert.notEqual(firstPrivatePage.messages[0].id, olderPrivatePage.messages[0].id,
  "private cursor pages must not repeat the boundary message");
assert.equal(olderPrivatePage.hasMore, false);

// Delete-for-me must hide the private message only from the requesting account.
const deleteForMeId = randomUUID().replaceAll("-", "");
await call("/api/messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "delete for me fixture " + suffix, clientMessageId: deleteForMeId },
  expected: 201
});
await call("/api/messages/" + encodeURIComponent(deleteForMeId) + "?scope=me", {
  method: "DELETE", token: b.token
});
const bAfterDeleteForMe = await call("/api/messages?with=" + encodeURIComponent(a.user.id), { token: b.token });
assert.ok(!bAfterDeleteForMe.messages.some(message => message.id === deleteForMeId),
  "delete-for-me must hide the message for the requesting account");
const aAfterDeleteForMe = await call("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
assert.ok(aAfterDeleteForMe.messages.some(message => message.id === deleteForMeId),
  "delete-for-me must preserve the other participant's message");
await call("/api/messages/" + encodeURIComponent(deleteForMeId), {
  method: "DELETE", token: a.token, expected: 200
});

const conversation = await call("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
assert.equal(conversation.messages.filter(message => message.id === clientMessageId).length, 1,
  "retries must leave exactly one persisted message");

const privateSearch = await call("/api/messages/search?with=" + encodeURIComponent(b.user.id) + "&q=integration&limit=1", { token: a.token });
assert.equal(privateSearch.messages.length, 1);
assert.equal(privateSearch.hasMore, true, "private search should expose more matching results");
const privateSearchOlder = await call("/api/messages/search?with=" + encodeURIComponent(b.user.id) +
  "&q=integration&limit=1&before=" + encodeURIComponent(privateSearch.nextCursor.before) +
  "&beforeId=" + encodeURIComponent(privateSearch.nextCursor.beforeId), { token: a.token });
assert.equal(privateSearchOlder.messages.length, 1);
assert.notEqual(privateSearch.messages[0].id, privateSearchOlder.messages[0].id,
  "private search cursor must not repeat results");
await call("/api/messages/search?with=" + encodeURIComponent(a.user.id) + "&q=integration", { token: b.token })
  .then(result => assert.ok(result.messages.some(message => message.id === clientMessageId)));
await call("/api/messages/search?with=" + encodeURIComponent(b.user.id) + "&q=x", { token: a.token, expected: 400 });
await call("/api/messages/search?with=" + encodeURIComponent(a.user.id) + "&q=integration", { token: a.token, expected: 403 });

const sparkStatus = await call("/api/statuses", {
  method: "POST", token: a.token,
  body: { content: "SPARK integration " + suffix, backgroundKey: "midnight", textColorKey: "white", fontKey: "modern" },
  expected: 201
});
assert.ok(sparkStatus.status?.id, "SPARK text status must return its ID");
await call("/api/statuses/" + encodeURIComponent(sparkStatus.status.id) + "/reactions", {
  method: "POST", token: b.token, body: { emoji: "🎉" }
});
await call("/api/statuses/" + encodeURIComponent(sparkStatus.status.id) + "/replies", {
  method: "POST", token: b.token, body: { body: "SPARK reply integration " + suffix }, expected: 201
});
const sparkReplyFeed = await call("/api/statuses/" + encodeURIComponent(sparkStatus.status.id) + "/replies", { token: a.token });
assert.ok(sparkReplyFeed.replies?.some(reply => reply.body === "SPARK reply integration " + suffix),
  "SPARK replies must persist and be visible to the status owner");
await call("/api/statuses/" + encodeURIComponent(sparkStatus.status.id) + "/reactions?emoji=" + encodeURIComponent("🎉"), {
  method: "DELETE", token: b.token
});

const group = await call("/api/groups", { method: "POST", token: a.token, body: { name: "Search Test " + suffix }, expected: 201 });
assert.ok(group.group?.id);
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/members", {
  method: "POST", token: a.token, body: { userId: b.user.id }, expected: 201
});
const groupInteractionMessage = await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages", {
  method: "POST", token: a.token, body: { body: "group-search-needle-" + suffix }, expected: 201
});
assert.ok(groupInteractionMessage.id, "group message must return its ID");
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" +
  encodeURIComponent(groupInteractionMessage.id), {
    method: "PATCH", token: a.token, body: { body: "edited group root group-search-needle " + suffix }
  });
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" +
  encodeURIComponent(groupInteractionMessage.id), {
    method: "PATCH", token: b.token, body: { body: "unauthorized group edit" }, expected: 404
  });
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" +
  encodeURIComponent(groupInteractionMessage.id) + "/reactions", {
    method: "POST", token: b.token, body: { emoji: "❤️" }
  });
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" +
  encodeURIComponent(groupInteractionMessage.id) + "/pin", { method: "POST", token: b.token });
const groupInteractionPage = await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages", { token: b.token });
const groupInteraction = groupInteractionPage.messages.find(message => message.id === groupInteractionMessage.id);
assert.equal(groupInteraction?.body, "edited group root group-search-needle " + suffix,
  "group message edits must be returned by the conversation API");
assert.ok(groupInteraction?.is_pinned, "group pin must be returned by the group conversation API");
assert.ok(groupInteraction?.reactions?.some(reaction => reaction.emoji === "❤️" && reaction.user_id === b.user.id),
  "group reaction must be returned by the group conversation API");
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" +
  encodeURIComponent(groupInteractionMessage.id) + "/pin", { method: "DELETE", token: b.token });
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" +
  encodeURIComponent(groupInteractionMessage.id) + "/reactions?emoji=" + encodeURIComponent("❤️"), {
    method: "DELETE", token: b.token
  });
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages", {
  method: "POST", token: a.token, body: { body: "second group-search-needle fixture" }, expected: 201
});
const firstGroupPage = await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages?limit=1", { token: b.token });
assert.equal(firstGroupPage.messages.length, 1);
assert.equal(firstGroupPage.hasMore, true);
assert.ok(firstGroupPage.nextCursor?.before && firstGroupPage.nextCursor?.beforeId);
const olderGroupPage = await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages?limit=1&before=" +
  encodeURIComponent(firstGroupPage.nextCursor.before) + "&beforeId=" +
  encodeURIComponent(firstGroupPage.nextCursor.beforeId), { token: b.token });
assert.equal(olderGroupPage.messages.length, 1);
assert.notEqual(firstGroupPage.messages[0].id, olderGroupPage.messages[0].id,
  "group cursor pages must not repeat the boundary message");
assert.equal(olderGroupPage.hasMore, false);
const groupSearch = await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/search?q=group-search-needle&limit=1", { token: b.token });
assert.equal(groupSearch.messages.length, 1);
assert.equal(groupSearch.hasMore, true);
const groupSearchOlder = await call("/api/groups/" + encodeURIComponent(group.group.id) +
  "/messages/search?q=group-search-needle&limit=1&before=" + encodeURIComponent(groupSearch.nextCursor.before) +
  "&beforeId=" + encodeURIComponent(groupSearch.nextCursor.beforeId), { token: b.token });
assert.equal(groupSearchOlder.messages.length, 1);
assert.notEqual(groupSearch.messages[0].id, groupSearchOlder.messages[0].id,
  "group search cursor must not repeat results");
const groupReply = await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages", {
  method: "POST", token: b.token,
  body: { body: "group reply fixture " + suffix, replyToId: groupInteractionMessage.id }, expected: 201
});
const groupReplyPage = await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages", { token: a.token });
const persistedGroupReply = groupReplyPage.messages.find(message => message.id === groupReply.id);
assert.equal(persistedGroupReply?.reply_to_id, groupInteractionMessage.id,
  "group reply must remain attached to its target message");
assert.equal(persistedGroupReply?.reply_to_body, "edited group root group-search-needle " + suffix,
  "group reply preview must preserve the target text");
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/search?q=x", { token: b.token, expected: 400 });

await call("/api/contacts/match", { method: "POST", token: a.token, body: { phones: [] } }).then(result => {
  assert.deepEqual(result.users, []);
});
await call("/api/me", { expected: 401 });
await call("/api/contacts", { method: "POST", token: a.token, body: { userId: a.user.id }, expected: 400 });


const legacySuffix = randomUUID().replaceAll("-", "").slice(0, 8);
const legacyAccount = {
  name: "Legacy Registration " + legacySuffix,
  username: "legacy" + legacySuffix,
  phone: "+1202" + digits(),
  password: "Preview-Test-" + randomUUID().slice(0, 8)
};
const legacyRegistration = await call("/api/register", {
  method: "POST", body: legacyAccount, expected: 201
});
assert.ok(legacyRegistration.user?.id && legacyRegistration.token,
  "legacy name/username registration payload must be accepted");
const legacyLogin = await call("/api/login", {
  method: "POST", body: { username: legacyAccount.phone, password: legacyAccount.password }
});
assert.equal(legacyLogin.user.id, legacyRegistration.user.id,
  "legacy registration account must be able to sign in by phone");
await call("/api/messages/" + encodeURIComponent(deleteForMeId) + "?scope=me", {
  method: "DELETE", token: legacyLogin.token, expected: 404
});
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" +
  encodeURIComponent(groupInteractionMessage.id) + "/pin", {
    method: "POST", token: legacyLogin.token, expected: 404
  });
await call("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" +
  encodeURIComponent(groupInteractionMessage.id) + "/reactions", {
    method: "POST", token: legacyLogin.token, body: { emoji: "🔥" }, expected: 404
  });

const editedText = "edited preview message " + suffix;
await call("/api/messages/" + encodeURIComponent(clientMessageId), {
  method: "PATCH", token: a.token, body: { body: editedText }
});
await call("/api/messages/" + encodeURIComponent(clientMessageId) + "/pin", {
  method: "POST", token: a.token
});
await call("/api/messages/" + encodeURIComponent(clientMessageId) + "/reactions", {
  method: "POST", token: b.token, body: { emoji: "❤️" }
});
const interactionHistory = await call("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
const interactedMessage = interactionHistory.messages.find(message => message.id === clientMessageId);
assert.equal(interactedMessage?.body, editedText, "edited message must be persisted");
assert.equal(interactedMessage?.is_pinned, true, "message pin must be persisted for the pinning user");
assert.ok(interactedMessage?.reactions?.some(reaction => reaction.emoji === "❤️"),
  "message reactions must be visible to conversation participants");


const profilePng = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6j8AAAAASUVORK5CYII=",
  "base64"
);
const profileUpload = await fetch(new URL("/api/profile/photo/me", base), {
  method: "POST",
  headers: { Authorization: `Bearer ${a.token}`, "Content-Type": "image/png" },
  body: profilePng
});
const profilePhotoRaw = await profileUpload.text();
let profilePhoto;
try { profilePhoto = profilePhotoRaw ? JSON.parse(profilePhotoRaw) : {}; }
catch { throw new Error("Profile photo upload returned non-JSON response"); }
assert.equal(profileUpload.status, 201, `Profile photo upload failed: ${JSON.stringify(profilePhoto)}`);
assert.ok(profilePhoto.photoUrl, "profile photo upload must return its private photo URL");
const friendPhoto = await fetch(new URL(profilePhoto.photoUrl, base), {
  headers: { Authorization: `Bearer ${b.token}` }
});
assert.equal(friendPhoto.status, 200, "mutual contact must be allowed to view profile photo");
assert.ok((await friendPhoto.arrayBuffer()).byteLength > 0);
const privateMemory = await call("/api/private-memories", {
  method: "POST", token: a.token,
  body: { title: "Private vault " + suffix, content: "Only the owner should see this memory." },
  expected: 201
});
assert.ok(privateMemory.memory?.id, "private memory must be created");
const ownerMemories = await call("/api/private-memories", { token: a.token });
const otherMemories = await call("/api/private-memories", { token: b.token });
assert.ok(ownerMemories.memories.some(memory => memory.id === privateMemory.memory.id));
assert.ok(!otherMemories.memories.some(memory => memory.id === privateMemory.memory.id),
  "private memories must be isolated by owner");

const memoryPhotoUpload = await fetch(new URL(
  "/api/private-memories/" + encodeURIComponent(privateMemory.memory.id) + "/media", base
), {
  method: "POST",
  headers: {
    Authorization: `Bearer ${a.token}`,
    "Content-Type": "image/png",
    "X-File-Name": "barq-private-memory.png"
  },
  body: profilePng
});
const memoryPhotoRaw = await memoryPhotoUpload.text();
let memoryPhoto;
try { memoryPhoto = memoryPhotoRaw ? JSON.parse(memoryPhotoRaw) : {}; }
catch { throw new Error("Private memory photo upload returned non-JSON response"); }
assert.equal(memoryPhotoUpload.status, 201,
  `Private memory photo upload failed: ${JSON.stringify(memoryPhoto)}`);
assert.ok(memoryPhoto.media?.attachmentId, "private memory photo must return an attachment id");
const memoryListWithPhoto = await call("/api/private-memories", { token: a.token });
assert.ok(memoryListWithPhoto.memories.find(memory => memory.id === privateMemory.memory.id)
  ?.media?.some(media => media.attachmentId === memoryPhoto.media.attachmentId));
const ownerMemoryPhoto = await fetch(new URL(
  "/api/media/" + encodeURIComponent(memoryPhoto.media.attachmentId), base
), { headers: { Authorization: `Bearer ${a.token}` } });
assert.equal(ownerMemoryPhoto.status, 200, "only the owner should retrieve the private memory photo");
const otherMemoryPhoto = await fetch(new URL(
  "/api/media/" + encodeURIComponent(memoryPhoto.media.attachmentId), base
), { headers: { Authorization: `Bearer ${b.token}` } });
assert.equal(otherMemoryPhoto.status, 404, "private memory photos must be indistinguishable from missing media to other accounts");
await call("/api/private-memories/" + encodeURIComponent(privateMemory.memory.id), {
  method: "PATCH", token: a.token,
  body: { title: "Updated private vault " + suffix, content: "Updated private memory." }
});
await call("/api/private-memories/" + encodeURIComponent(privateMemory.memory.id), {
  method: "DELETE", token: a.token
});
const ownerMemoriesAfterDelete = await call("/api/private-memories", { token: a.token });
assert.ok(!ownerMemoriesAfterDelete.memories.some(memory => memory.id === privateMemory.memory.id),
  "deleted private memory must disappear from the owner's vault");

await call("/api/privacy", {
  method: "POST", token: a.token, body: { searchable: false, readReceipts: true }
});
const privatePhoto = await fetch(new URL(profilePhoto.photoUrl, base), {
  headers: { Authorization: `Bearer ${legacyLogin.token}` }
});
assert.equal(privatePhoto.status, 403, "non-contact must not access a private profile photo");

const sparkText = "Preview SPARK text " + suffix;
const textStatus = await call("/api/statuses", {
  method: "POST", token: a.token,
  body: { content: sparkText, backgroundKey: "midnight", textColorKey: "white", fontKey: "modern" },
  expected: 201
});
const bStatusesAfterText = await call("/api/statuses", { token: b.token });
assert.ok(bStatusesAfterText.statuses.some(status => status.id === textStatus.status.id),
  "mutual contact must see published text SPARK status");
const sparkReplyText = "SPARK reply " + suffix;
const sparkReply = await call("/api/statuses/" + encodeURIComponent(textStatus.status.id) + "/replies", {
  method: "POST", token: b.token, body: { body: sparkReplyText }, expected: 201
});
assert.equal(sparkReply.reply?.body, sparkReplyText, "SPARK reply must be persisted");
await call("/api/statuses/" + encodeURIComponent(textStatus.status.id) + "/reactions", {
  method: "POST", token: b.token, body: { emoji: "🔥" }
});
const sparkReplies = await call("/api/statuses/" + encodeURIComponent(textStatus.status.id) + "/replies", { token: a.token });
assert.ok(sparkReplies.replies.some(reply => reply.id === sparkReply.reply.id),
  "status owner must see replies in the same SPARK viewer");
await call("/api/statuses/" + encodeURIComponent(textStatus.status.id) + "/replies", {
  method: "POST", token: legacyLogin.token, body: { body: "unauthorized reply" }, expected: 403
});

const tinyPng = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6j8AAAAASUVORK5CYII=",
  "base64"
);
const mediaCaption = "Preview SPARK media caption " + suffix;
const mediaResponse = await fetch(new URL("/api/statuses/media", base), {
  method: "POST",
  headers: {
    Authorization: `Bearer ${a.token}`,
    "Content-Type": "image/png",
    "X-File-Name": "barq-preview.png",
    "X-Status-Caption": mediaCaption
  },
  body: tinyPng
});
const mediaRaw = await mediaResponse.text();
let mediaData;
try { mediaData = mediaRaw ? JSON.parse(mediaRaw) : {}; }
catch { throw new Error("SPARK media upload returned non-JSON response"); }
assert.equal(mediaResponse.status, 201, `SPARK media upload failed: ${JSON.stringify(mediaData)}`);
assert.equal(mediaData.status?.content, mediaCaption, "SPARK media post must retain its caption as the post text");
assert.equal(mediaData.status?.media?.caption, mediaCaption, "SPARK media row must retain its caption");
const bStatusesAfterMedia = await call("/api/statuses", { token: b.token });
const visibleMediaStatus = bStatusesAfterMedia.statuses.find(status => status.id === mediaData.status.id);
assert.ok(visibleMediaStatus, "mutual contact must see published SPARK media");
assert.equal(visibleMediaStatus.content, mediaCaption, "SPARK feed must return media caption with the post");
assert.ok(visibleMediaStatus.media?.some(media => media.caption === mediaCaption),
  "SPARK feed must return caption attached to the media item");
const mediaKey = mediaData.status.media.attachmentId;
const mediaFetch = await fetch(new URL("/api/media/" + encodeURIComponent(mediaKey), base), {
  headers: { Authorization: `Bearer ${b.token}` }
});
assert.equal(mediaFetch.status, 200, "authorized mutual contact must be able to load SPARK media");
assert.match(mediaFetch.headers.get("content-type") || "", /^image\/png/i);
assert.ok((await mediaFetch.arrayBuffer()).byteLength > 0, "SPARK media response must contain bytes");

const ephemeralSent = await call("/api/ephemeral-messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "Read-once preview message " + suffix },
  expected: 201
});
const ephemeralFirstRead = await call("/api/ephemeral-messages?with=" + encodeURIComponent(a.user.id), {
  token: b.token
});
assert.ok(ephemeralFirstRead.messages.some(message => message.id === ephemeralSent.id),
  "recipient must see ephemeral message on first read");
await new Promise(resolve => setTimeout(resolve, 11_000));
const ephemeralAfterExpiry = await call("/api/ephemeral-messages?with=" + encodeURIComponent(b.user.id), {
  token: a.token
});
assert.ok(!ephemeralAfterExpiry.messages.some(message => message.id === ephemeralSent.id),
  "ephemeral message must disappear ten seconds after first read");

await call("/api/blocks", {
  method: "POST", token: a.token, body: { userId: b.user.id }, expected: 201
});
const blockedList = await call("/api/blocks", { token: a.token });
assert.ok(blockedList.blockedUsers.some(user => user.userId === b.user.id),
  "block list must persist the selected user");
await call("/api/messages/" + encodeURIComponent(clientMessageId) + "/reactions", {
  method: "POST", token: b.token, body: { emoji: "🔥" }, expected: 403
});
await call("/api/messages/" + encodeURIComponent(clientMessageId) + "/pin", {
  method: "POST", token: a.token, expected: 403
});
await call("/api/messages", {
  method: "POST", token: b.token,
  body: { receiverId: a.user.id, body: "blocked message " + suffix },
  expected: 403
});
await call("/api/blocks?userId=" + encodeURIComponent(b.user.id), {
  method: "DELETE", token: a.token
});
const unblockedList = await call("/api/blocks", { token: a.token });
assert.ok(!unblockedList.blockedUsers.some(user => user.userId === b.user.id),
  "unblock must remove the selected account from the current user's block list");
await call("/api/messages", {
  method: "POST", token: b.token,
  body: { receiverId: a.user.id, body: "unblocked message " + suffix },
  expected: 201
});
// Conversation clear/delete are per-account, preserve the other participant's copy,
// keep the contact, and restore the chat list when a new message arrives.
const clearFixtureId = randomUUID().replaceAll("-", "");
const otherSideFixtureId = randomUUID().replaceAll("-", "");
await call("/api/messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "private clear fixture " + suffix, clientMessageId: clearFixtureId },
  expected: 201
});
await call("/api/messages", {
  method: "POST", token: b.token,
  body: { receiverId: a.user.id, body: "other side retained fixture " + suffix, clientMessageId: otherSideFixtureId },
  expected: 201
});
await call("/api/conversations/" + encodeURIComponent(b.user.id) + "/clear", {
  method: "POST", token: a.token
});
const clearedForA = await call("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
const retainedForB = await call("/api/messages?with=" + encodeURIComponent(a.user.id), { token: b.token });
assert.ok(!clearedForA.messages.some(message => message.id === clearFixtureId || message.id === otherSideFixtureId),
  "clear history must hide both directions from the current account");
assert.ok(retainedForB.messages.some(message => message.id === clearFixtureId) &&
  retainedForB.messages.some(message => message.id === otherSideFixtureId),
  "clear history must not delete the other participant's messages");
await call("/api/messages/" + encodeURIComponent(clearFixtureId), {
  method: "PATCH", token: a.token, body: { body: "stale edit after clear" }, expected: 404
});
await call("/api/messages/" + encodeURIComponent(clearFixtureId), {
  method: "DELETE", token: a.token, expected: 404
});
let friendsAfterClear = await call("/api/friends", { token: a.token });
assert.equal(friendsAfterClear.friends.find(user => user.id === b.user.id)?.chatHidden, false,
  "clear history must keep the conversation visible");

await call("/api/conversations/" + encodeURIComponent(b.user.id), {
  method: "DELETE", token: a.token
});
const deletedForA = await call("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
const retainedAfterDeleteForB = await call("/api/messages?with=" + encodeURIComponent(a.user.id), { token: b.token });
assert.ok(!deletedForA.messages.some(message => message.id === clearFixtureId || message.id === otherSideFixtureId),
  "delete conversation must keep the deleted account's history hidden");
assert.ok(retainedAfterDeleteForB.messages.some(message => message.id === clearFixtureId) &&
  retainedAfterDeleteForB.messages.some(message => message.id === otherSideFixtureId),
  "delete conversation must preserve the other participant's history");
let friendsAfterDelete = await call("/api/friends", { token: a.token });
assert.equal(friendsAfterDelete.friends.find(user => user.id === b.user.id)?.chatHidden, true,
  "delete conversation must hide the chat but retain the contact");

// A retry of an already-accepted offline message is not new activity and
// must not unhide a conversation that was deleted after the first response.
await call("/api/messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "private clear fixture " + suffix, clientMessageId: clearFixtureId },
  expected: 200
});
const friendsAfterDuplicateRetry = await call("/api/friends", { token: a.token });
assert.equal(friendsAfterDuplicateRetry.friends.find(user => user.id === b.user.id)?.chatHidden, true,
  "idempotent retries must not restore a locally deleted conversation");

const restoredMessageId = randomUUID().replaceAll("-", "");
await call("/api/messages", {
  method: "POST", token: b.token,
  body: { receiverId: a.user.id, body: "new message restores deleted chat " + suffix, clientMessageId: restoredMessageId },
  expected: 201
});
const restoredForA = await call("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
assert.ok(restoredForA.messages.some(message => message.id === restoredMessageId),
  "new incoming messages must appear after a chat was deleted locally");
assert.ok(!restoredForA.messages.some(message => message.id === clearFixtureId || message.id === otherSideFixtureId),
  "restoring a chat must not restore previously deleted history");
const friendsAfterRestore = await call("/api/friends", { token: a.token });
assert.equal(friendsAfterRestore.friends.find(user => user.id === b.user.id)?.chatHidden, false,
  "a new message must restore the conversation to the chat list");

console.log("Preview integration passed: legacy/current signup and phone login, profile/privacy/contacts, private message edit/pin/reactions, private-memory owner isolation/photo access, SPARK text replies/reactions, captioned media upload/feed/download, ephemeral expiry, blocking, and access guards.");

}
