import assert from "node:assert/strict";
import { createHash, randomInt, randomUUID } from "node:crypto";

const base = process.env.BARQ_PREVIEW_URL;
if (!base) {
  console.log("Preview media integration skipped: BARQ_PREVIEW_URL is not configured.");
} else {
const isWorkersPreview = /^https:\/\/[a-z0-9.-]+\.workers\.dev$/i.test(base);
const isVercelPreview = /^https:\/\/[a-z0-9.-]+\.vercel\.app$/i.test(base);
if (!isWorkersPreview && !isVercelPreview) {
  throw new Error("BARQ_PREVIEW_URL must target the isolated Worker or its Vercel Preview proxy");
}

if (process.env.BARQ_PREVIEW_MEDIA_CREDENTIALS_CONFIGURED !== "true") {
  console.log("Preview media integration skipped: Preview-only Tigris credentials are not configured.");
} else {
async function request(path, { method = "GET", token, body, headers = {}, expected = 200 } = {}) {
  const requestHeaders = {
    ...(token ? { Authorization: `Bearer ${token}` } : {}),
    ...headers
  };
  // Cloudflare's edge can occasionally reset a live Preview connection while
  // accepting a multi-megabyte chunk. Retry only replay-safe operations:
  // GET/PUT/DELETE, or POST carrying an explicit idempotency key.
  const replaySafe = ["GET", "PUT", "DELETE"].includes(method.toUpperCase()) ||
    Object.keys(requestHeaders).some(name => name.toLowerCase() === "x-idempotency-key");
  let response;
  for (let attempt = 1; ; attempt++) {
    try {
      response = await fetch(new URL(path, base), {
        method,
        headers: requestHeaders,
        body,
        signal: AbortSignal.timeout(45_000)
      });
      if (replaySafe && [502, 503, 504].includes(response.status) && attempt < 4) {
        await response.arrayBuffer();
        await new Promise(resolve => setTimeout(resolve, attempt * 750));
        continue;
      }
      break;
    } catch (error) {
      if (!replaySafe || attempt >= 4) throw error;
      await new Promise(resolve => setTimeout(resolve, attempt * 750));
    }
  }
  const bytes = new Uint8Array(await response.arrayBuffer());
  assert.equal(response.status, expected,
    `${method} ${path}: HTTP ${response.status}, ${new TextDecoder().decode(bytes.slice(0, 1200))}`);
  return { response, bytes };
}

async function json(path, options = {}) {
  const result = await request(path, {
    ...options,
    headers: { "Content-Type": "application/json", ...(options.headers || {}) },
    body: options.body === undefined ? undefined : JSON.stringify(options.body)
  });
  return JSON.parse(new TextDecoder().decode(result.bytes));
}

const suffix = randomUUID().replaceAll("-", "").slice(0, 10);
const password = "Preview-Media-" + randomUUID().slice(0, 10);
const phone = () => "+1202" + String(randomInt(1000000, 9999999));
const a = await json("/api/register", {
  method: "POST", expected: 201,
  body: { displayName: "Media Owner " + suffix, username: "mo" + suffix, phone: phone(), password }
});
const b = await json("/api/register", {
  method: "POST", expected: 201,
  body: { displayName: "Media Recipient " + suffix, username: "mr" + suffix, phone: phone(), password }
});
const c = await json("/api/register", {
  method: "POST", expected: 201,
  body: { displayName: "Media Stranger " + suffix, username: "ms" + suffix, phone: phone(), password }
});
assert.ok(a.token && b.user?.id && c.token && c.user?.id);
await json("/api/contacts", {
  method: "POST", token: a.token, expected: 201, body: { userId: b.user.id }
});
// Hide the conversation first: completing a new private media upload must
// restore the chat row and create exactly one visible attachment message.
await request("/api/conversations/" + encodeURIComponent(b.user.id), {
  method: "DELETE", token: a.token, expected: 200
});

const MiB = 1024 * 1024;
const totalSize = 5 * MiB + 17;
const source = new Uint8Array(totalSize);
for (let i = 0; i < source.length; i++) source[i] = (i * 37 + 19) % 251;
const sourceHash = createHash("sha256").update(source).digest("hex");
const idempotencyKey = "media-preview-" + randomUUID();

const created = await json("/api/media/uploads", {
  method: "POST", token: a.token, expected: 201,
  headers: { "X-Idempotency-Key": idempotencyKey },
  body: {
    size: totalSize, contentType: "application/octet-stream",
    fileName: "barq-preview-media.bin", recipientId: b.user.id
  }
});
const sessionId = created.session?.id;
assert.ok(sessionId, "upload session must be created");

const totalChunks = Math.ceil(totalSize / MiB);
async function uploadChunk(number, bytes, token = a.token, expected = 200) {
  return request(`/api/media/uploads/${sessionId}/chunks/${number}`, {
    method: "PUT", token, body: bytes,
    headers: { "Content-Type": "application/octet-stream" }, expected
  });
}

// Simulate a client interruption after two transport chunks, then resume the
// same idempotent upload session as a fresh request sequence.
for (let number = 1; number <= 2; number++) {
  const start = (number - 1) * MiB;
  await uploadChunk(number, source.slice(start, Math.min(start + MiB, totalSize)));
}
const resumed = await json("/api/media/uploads", {
  method: "POST", token: a.token, expected: 200,
  headers: { "X-Idempotency-Key": idempotencyKey },
  body: {
    size: totalSize, contentType: "application/octet-stream",
    fileName: "barq-preview-media.bin", recipientId: b.user.id
  }
});
assert.equal(resumed.resumed, true, "restarting the upload declaration must resume the existing session");
assert.equal(resumed.session?.id, sessionId, "resuming must retain the original upload session ID");

// The recipient cannot mutate the sender-owned upload session.
await uploadChunk(1, source.slice(0, MiB), b.token, 404);
// An exact retry is accepted; reusing the same chunk number for different bytes is rejected.
await uploadChunk(1, source.slice(0, MiB));
const alteredChunk = source.slice(0, MiB);
alteredChunk[0] ^= 0xff;
await uploadChunk(1, alteredChunk, a.token, 409);

for (let number = 3; number <= totalChunks; number++) {
  const start = (number - 1) * MiB;
  const chunk = source.slice(start, Math.min(start + MiB, totalSize));
  await uploadChunk(number, chunk);
}

const completed = await json(`/api/media/uploads/${sessionId}/complete`, {
  method: "POST", token: a.token, expected: 201, body: {}
});
const attachmentId = completed.attachment?.attachmentId;
assert.ok(attachmentId, "completion must return a final attachment identifier");
assert.equal(completed.attachment.size, totalSize);

const chat = await json("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
const attachmentMessages = (chat.messages || []).filter(message => message.id === sessionId);
assert.equal(attachmentMessages.length, 1, "resumable upload must create exactly one chat message");
const attachmentBody = JSON.parse(attachmentMessages[0].body);
assert.equal(attachmentBody.type, "attachment");
assert.equal(attachmentBody.attachmentId, attachmentId);
assert.equal(attachmentBody.fileName, "barq-preview-media.bin");
assert.equal(attachmentBody.contentType, "application/octet-stream");
assert.equal(attachmentBody.size, totalSize);
const recipientChat = await json("/api/messages?with=" + encodeURIComponent(a.user.id), { token: b.token });
assert.ok((recipientChat.messages || []).some(message => message.id === sessionId),
  "the recipient must see the uploaded attachment in the conversation");
const friends = await json("/api/friends", { token: a.token });
const restoredChat = (friends.friends || []).find(friend => friend.id === b.user.id);
assert.equal(restoredChat?.chatHidden, false,
  "a newly delivered resumable attachment must restore the private conversation");

const downloaded = await request("/api/media/" + encodeURIComponent(attachmentId), {
  token: a.token, expected: 200
});
assert.equal(downloaded.bytes.length, totalSize, "full download size must match original");
assert.equal(createHash("sha256").update(downloaded.bytes).digest("hex"), sourceHash,
  "full download bytes must exactly match uploaded bytes");

const ranged = await request("/api/media/" + encodeURIComponent(attachmentId), {
  token: a.token, headers: { Range: "bytes=0-1023" }, expected: 206
});
assert.equal(ranged.bytes.length, 1024, "range download must return exactly 1024 bytes");
assert.equal(ranged.response.headers.get("content-range"), `bytes 0-1023/${totalSize}`);
assert.deepEqual(ranged.bytes, source.slice(0, 1024));

const recipientDownload = await request("/api/media/" + encodeURIComponent(attachmentId), {
  token: b.token, expected: 200
});
assert.equal(createHash("sha256").update(recipientDownload.bytes).digest("hex"), sourceHash,
  "authorized conversation recipient must download the same media");
await request("/api/media/" + encodeURIComponent(attachmentId), {
  token: c.token, expected: 403
});
// Hiding a message for one account must not revoke the shared attachment.
// Delete-for-everyone revokes access immediately and queues the retained object
// for scheduled cleanup, so authorized reads correctly return 410 (expired).
await request("/api/messages/" + encodeURIComponent(sessionId) + "?scope=me", {
  method: "DELETE", token: b.token, expected: 200
});
await request("/api/media/" + encodeURIComponent(attachmentId), {
  token: b.token, expected: 200
});
await request("/api/messages/" + encodeURIComponent(sessionId), {
  method: "DELETE", token: a.token, expected: 200
});
// The first authorized read observes expiry, returns 410, and performs
// immediate object cleanup. A later read sees the already-removed object (404).
await request("/api/media/" + encodeURIComponent(attachmentId), {
  token: a.token, expected: 410
});
await request("/api/media/" + encodeURIComponent(attachmentId), {
  token: b.token, expected: 404
});

const retry = await json(`/api/media/uploads/${sessionId}/complete`, {
  method: "POST", token: a.token, expected: 200, body: {}
});
assert.equal(retry.alreadyCompleted, true, "completion retry must be idempotent");
const afterRetry = await json("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
assert.equal((afterRetry.messages || []).filter(message => message.id === sessionId).length, 0,
  "completion retry must not recreate the attachment chat message after delete-for-everyone");

// Exercise the same resumable-media pipeline for a real Preview group conversation.
const group = await json("/api/groups", {
  method: "POST", token: a.token, expected: 201,
  body: { name: "Media Group " + suffix }
});
assert.ok(group.group?.id, "group must be created for group media coverage");
await json("/api/groups/" + encodeURIComponent(group.group.id) + "/members", {
  method: "POST", token: a.token, expected: 201, body: { userId: b.user.id }
});
const groupSource = new Uint8Array(256 * 1024 + 31);
for (let i = 0; i < groupSource.length; i++) groupSource[i] = (i * 19 + 7) % 253;
const groupHash = createHash("sha256").update(groupSource).digest("hex");
const groupKey = "media-group-preview-" + randomUUID();
const groupUpload = await json("/api/media/uploads", {
  method: "POST", token: a.token, expected: 201,
  headers: { "X-Idempotency-Key": groupKey },
  body: {
    size: groupSource.length, contentType: "application/octet-stream",
    fileName: "barq-preview-group.bin", groupId: group.group.id
  }
});
const groupSessionId = groupUpload.session?.id;
assert.ok(groupSessionId, "group upload session must be created");
await request(`/api/media/uploads/${groupSessionId}/chunks/1`, {
  method: "PUT", token: a.token, body: groupSource,
  headers: { "Content-Type": "application/octet-stream" }, expected: 200
});
const groupCompleted = await json(`/api/media/uploads/${groupSessionId}/complete`, {
  method: "POST", token: a.token, expected: 201, body: {}
});
const groupAttachmentId = groupCompleted.attachment?.attachmentId;
assert.ok(groupAttachmentId, "group upload must produce an attachment");
const groupMessages = await json("/api/groups/" + encodeURIComponent(group.group.id) + "/messages", {
  token: a.token
});
const groupAttachmentMessage = (groupMessages.messages || []).find(message => message.id === groupSessionId);
assert.ok(groupAttachmentMessage, "group attachment must be visible as exactly one group message");
const groupAttachmentBody = JSON.parse(groupAttachmentMessage.body);
assert.equal(groupAttachmentBody.attachmentId, groupAttachmentId);
assert.equal(groupAttachmentBody.size, groupSource.length);
const memberGroupMessages = await json("/api/groups/" + encodeURIComponent(group.group.id) + "/messages", {
  token: b.token
});
assert.ok((memberGroupMessages.messages || []).some(message => message.id === groupSessionId),
  "group member must see the uploaded attachment message");
const groupDownload = await request("/api/media/" + encodeURIComponent(groupAttachmentId), {
  token: b.token, expected: 200
});
assert.equal(createHash("sha256").update(groupDownload.bytes).digest("hex"), groupHash,
  "group member download must exactly match the uploaded bytes");
await request("/api/media/" + encodeURIComponent(groupAttachmentId), {
  token: c.token, expected: 403
});
await json("/api/groups/" + encodeURIComponent(group.group.id) + "/messages/" + encodeURIComponent(groupSessionId), {
  method: "PATCH", token: a.token, body: { body: "edited away from the attachment" }, expected: 200
});
await request("/api/media/" + encodeURIComponent(groupAttachmentId), {
  token: b.token, expected: 410
});
console.log("Preview group media integration passed: group attachment visibility, member SHA-256 download, non-member denial, and revocation after message deletion.");

console.log("Preview private media integration passed: resumable upload creates one visible chat message, restores a hidden conversation, exact SHA-256 readback, HTTP Range, recipient authorization, and idempotent completion.");


}
}
