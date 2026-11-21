import assert from "node:assert/strict";
import { createHash, randomInt, randomUUID } from "node:crypto";

const base = process.env.BARQ_PREVIEW_URL;
if (!base || !/^https:\/\/[a-z0-9.-]+\.workers\.dev$/i.test(base)) {
  throw new Error("BARQ_PREVIEW_URL must target the isolated workers.dev Preview host");
}

async function request(path, { method = "GET", token, body, headers = {}, expected = 200 } = {}) {
  const response = await fetch(new URL(path, base), {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers
    },
    body
  });
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
assert.ok(a.token && b.user?.id);
await json("/api/contacts", {
  method: "POST", token: a.token, expected: 201, body: { userId: b.user.id }
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
for (let number = 1; number <= totalChunks; number++) {
  const start = (number - 1) * MiB;
  const chunk = source.slice(start, Math.min(start + MiB, totalSize));
  await request(`/api/media/uploads/${sessionId}/chunks/${number}`, {
    method: "PUT", token: a.token, body: chunk,
    headers: { "Content-Type": "application/octet-stream" }, expected: 200
  });
}

const completed = await json(`/api/media/uploads/${sessionId}/complete`, {
  method: "POST", token: a.token, expected: 201, body: {}
});
const attachmentId = completed.attachment?.attachmentId;
assert.ok(attachmentId, "completion must return a final attachment identifier");
assert.equal(completed.attachment.size, totalSize);

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

const retry = await json(`/api/media/uploads/${sessionId}/complete`, {
  method: "POST", token: a.token, expected: 200, body: {}
});
assert.equal(retry.alreadyCompleted, true, "completion retry must be idempotent");

console.log("Preview media integration passed: 5 MiB+17 upload via 1 MiB chunks, multipart completion, exact SHA-256 readback, HTTP Range, recipient authorization, and completion retry.");
