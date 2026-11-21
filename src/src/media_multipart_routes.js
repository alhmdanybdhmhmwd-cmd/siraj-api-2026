import { AwsClient } from "aws4fetch";
import {
  MEDIA_MULTIPART_PART_SIZE, MEDIA_MULTIPART_MAX_SIZE, MEDIA_UPLOAD_SESSION_TTL_MS,
  MEDIA_TRANSPORT_CHUNK_SIZE, validateMultipartDeclaration, validateMultipartPart,
  validateTransportChunk, normalizeMultipartEtag,
  parseMultipartUploadId, buildCompleteMultipartXml, isUploadSessionExpired,
  matchesUploadDeclaration
} from "./media_multipart.js";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-File-Name, X-Recipient-Id, X-Group-Id, X-Idempotency-Key",
  "Content-Type": "application/json; charset=utf-8"
};
const json = (data, status = 200) => new Response(JSON.stringify(data), { status, headers });

function storageClient(env) {
  if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) throw new Error("Media storage credentials are not configured");
  return new AwsClient({ accessKeyId: env.TIGRIS_ACCESS_KEY_ID, secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY, service: "s3", region: "auto", retries: 2 });
}
function objectUrl(env, objectKey, uploadId, partNumber) {
  const bucket = encodeURIComponent(env.TIGRIS_BUCKET || "siraj-media");
  const key = objectKey.split("/").map(encodeURIComponent).join("/");
  const url = new URL("https://" + bucket + ".t3.storage.dev/" + key);
  if (uploadId !== undefined) url.searchParams.set("uploadId", uploadId);
  if (partNumber !== undefined) url.searchParams.set("partNumber", String(partNumber));
  return url.toString();
}
async function readLimited(request, limit) {
  const declared = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declared) && declared > limit) return null;
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader(), chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) { await reader.cancel().catch(() => {}); return null; }
      chunks.push(value);
    }
  } finally { try { reader.releaseLock(); } catch (_) {} }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}
async function ensureSessionSchema(env) {
  const rows = await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('media_upload_sessions', 'media_upload_parts', 'media_upload_chunks')").all();
  const names = new Set((rows.results || []).map(row => row.name));
  if (!names.has("media_upload_sessions") || !names.has("media_upload_parts") || !names.has("media_upload_chunks")) {
    throw new Error("Resumable media upload migrations 0010 and 0011 are not applied");
  }
}
function stagedChunkKey(session, chunkNumber) {
  return session.object_key + ".barq-staging/" + session.id + "/" + chunkNumber;
}
async function deleteStagedChunks(storage, env, session, chunkNumbers) {
  for (const number of chunkNumbers) {
    const response = await storage.fetch(objectUrl(env, stagedChunkKey(session, number)), { method: "DELETE" });
    if (!response.ok && response.status !== 404) throw new Error("Could not clean a staged upload chunk");
  }
}
async function canUploadToConversation(env, ownerId, recipientId, groupId) {
  if (recipientId) {
    const friendship = await env.DB.prepare("SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?").bind(ownerId, recipientId).first();
    return Boolean(friendship);
  }
  const membership = await env.DB.prepare("SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?").bind(groupId, ownerId).first();
  return Boolean(membership);
}
async function sessionForOwner(env, id, ownerId) {
  return env.DB.prepare("SELECT * FROM media_upload_sessions WHERE id = ? AND owner_id = ?").bind(id, ownerId).first();
}

export async function cleanupExpiredUploadSessions(env, now = Date.now()) {
  await env.DB.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'media_upload_sessions'").first();
  const cutoff = new Date(now).toISOString();
  const rows = await env.DB.prepare(
    "SELECT id, object_key, storage_upload_id, state FROM media_upload_sessions " +
    "WHERE (state IN ('uploading', 'completing', 'failed') AND expires_at <= ?) " +
    "OR (state = 'completed' AND EXISTS (SELECT 1 FROM media_upload_chunks c WHERE c.session_id = media_upload_sessions.id)) " +
    "ORDER BY expires_at LIMIT 50"
  ).bind(cutoff).all();
  const storage = storageClient(env);
  let cleaned = 0;
  for (const row of rows.results || []) {
    try {
      if (row.state !== "completed") {
        const response = await storage.fetch(objectUrl(env, row.object_key, row.storage_upload_id), { method: "DELETE" });
        if (!response.ok && response.status !== 404) continue;
      }
      const staged = await env.DB.prepare("SELECT chunk_number AS chunkNumber FROM media_upload_chunks WHERE session_id = ?").bind(row.id).all();
      const cleanupSession = { id: row.id, object_key: row.object_key };
      await deleteStagedChunks(storage, env, cleanupSession, (staged.results || []).map(item => Number(item.chunkNumber)));
      await env.DB.prepare("DELETE FROM media_upload_chunks WHERE session_id = ?").bind(row.id).run();
      if (row.state !== "completed") {
        await env.DB.prepare("DELETE FROM media_upload_sessions WHERE id = ? AND state IN ('uploading', 'completing', 'failed') AND expires_at <= ?")
          .bind(row.id, cutoff).run();
      }
      cleaned++;
    } catch (error) {
      console.error("Expired multipart upload cleanup failed:", error?.name || "Error");
    }
  }
  return { checked: (rows.results || []).length, cleaned };
}

export async function handleResumableMediaUpload(request, env, currentUser, url, path, method) {
  const prefix = "/api/media/uploads";
  if (path !== prefix && !path.startsWith(prefix + "/")) return null;
  try {
    await ensureSessionSchema(env);
    const storage = storageClient(env);
    const suffix = path.slice(prefix.length).replace(/^\/+/, "");
    if (!suffix && method === "POST") {
      const body = await request.json().catch(() => null);
      if (!body || typeof body !== "object") return json({ error: "Invalid upload declaration" }, 400);
      let declaration;
      try {
        declaration = validateMultipartDeclaration({ size: body.size, contentType: body.contentType, fileName: body.fileName });
      } catch (error) { return json({ error: error.message }, 400); }
      const recipientId = String(body.recipientId || "").trim() || null;
      const groupId = String(body.groupId || "").trim() || null;
      const idempotencyKey = String(request.headers.get("X-Idempotency-Key") || body.idempotencyKey || "").trim();
      if ((recipientId && groupId) || (!recipientId && !groupId) ||
          (recipientId && recipientId.length > 128) || (groupId && groupId.length > 128) ||
          !/^[A-Za-z0-9._:-]{8,128}$/.test(idempotencyKey)) {
        return json({ error: "Provide exactly one valid recipientId or groupId and an idempotency key" }, 400);
      }
      if (!(await canUploadToConversation(env, currentUser.sub, recipientId, groupId))) {
        return json({ error: "You are not a member of this conversation" }, 403);
      }
      const expectedParts = Math.ceil(declaration.size / MEDIA_MULTIPART_PART_SIZE);
      const existing = await env.DB.prepare(
        "SELECT id, state, total_size AS size, expected_parts AS expectedParts, expires_at AS expiresAt, recipient_id AS recipientId, group_id AS groupId, content_type AS contentType, file_name AS fileName FROM media_upload_sessions WHERE owner_id = ? AND idempotency_key = ?"
      ).bind(currentUser.sub, idempotencyKey).first();
      if (existing && !isUploadSessionExpired(existing.expiresAt) && ["uploading", "completing", "completed"].includes(existing.state)) {
        if (!matchesUploadDeclaration(existing, declaration, recipientId, groupId) ||
            Number(existing.expectedParts) !== expectedParts) {
          return json({ error: "Idempotency key was already used for a different upload" }, 409);
        }
        const parts = await env.DB.prepare("SELECT part_number AS partNumber, etag, size FROM media_upload_parts WHERE session_id = ? ORDER BY part_number").bind(existing.id).all();
        return json({ session: existing, uploadedParts: parts.results || [], resumed: true });
      }
      const objectKey = currentUser.sub + "/chat-media/" + crypto.randomUUID();
      const initiated = await storage.fetch(objectUrl(env, objectKey) + "?uploads", {
        method: "POST",
        headers: { "Content-Type": declaration.contentType,
          "x-amz-meta-ownerid": currentUser.sub,
          "x-amz-meta-filename": encodeURIComponent(declaration.fileName),
          "x-amz-meta-category": "chat-media" }
      });
      if (!initiated.ok) return json({ error: "Could not initiate media upload", storageStatus: initiated.status }, 502);
      let uploadId;
      try { uploadId = parseMultipartUploadId(await initiated.text()); }
      catch (error) { return json({ error: error.message }, 502); }
      const id = crypto.randomUUID();
      const expiresAt = new Date(Date.now() + MEDIA_UPLOAD_SESSION_TTL_MS).toISOString();
      try {
        await env.DB.prepare(
          `INSERT INTO media_upload_sessions
           (id, owner_id, recipient_id, group_id, object_key, storage_upload_id,
            file_name, content_type, total_size, part_size, expected_parts,
            idempotency_key, state, expires_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'uploading', ?)`
        ).bind(id, currentUser.sub, recipientId, groupId, objectKey, uploadId,
          declaration.fileName, declaration.contentType, declaration.size,
          MEDIA_MULTIPART_PART_SIZE, expectedParts, idempotencyKey, expiresAt).run();
      } catch (error) {
        await storage.fetch(objectUrl(env, objectKey, uploadId), { method: "DELETE" }).catch(() => {});
        throw error;
      }
      return json({ session: { id, state: "uploading", size: declaration.size,
        partSize: MEDIA_MULTIPART_PART_SIZE, expectedParts, expiresAt }, uploadedParts: [], resumed: false }, 201);
    }

    const match = suffix.match(/^([A-Za-z0-9-]{1,128})(?:\/chunks\/(\d+)|\/parts\/(\d+)|\/(complete))?$/);
    if (!match) return json({ error: "Invalid upload session route" }, 404);
    const sessionId = match[1], chunkNumber = match[2] ? Number(match[2]) : null,
      partNumber = match[3] ? Number(match[3]) : null, action = match[4] || null;
    const session = await sessionForOwner(env, sessionId, currentUser.sub);
    if (!session) return json({ error: "Upload session not found" }, 404);
    if (isUploadSessionExpired(session.expires_at) && session.state !== "completed") {
      return json({ error: "Upload session expired; start a new upload" }, 410);
    }


    if (chunkNumber !== null && method === "PUT") {
      if (session.state !== "uploading") return json({ error: "Upload session is not accepting chunks" }, 409);
      const bytes = await readLimited(request, MEDIA_TRANSPORT_CHUNK_SIZE);
      if (!bytes?.byteLength) return json({ error: "Chunk is empty or exceeds the 1 MiB transport limit" }, 413);
      try { validateTransportChunk(Number(session.total_size), chunkNumber, bytes.byteLength); }
      catch (error) { return json({ error: error.message }, 400); }
      const chunksPerPart = MEDIA_MULTIPART_PART_SIZE / MEDIA_TRANSPORT_CHUNK_SIZE;
      const targetPart = Math.ceil(chunkNumber / chunksPerPart);
      const existingPart = await env.DB.prepare("SELECT part_number FROM media_upload_parts WHERE session_id = ? AND part_number = ?").bind(sessionId, targetPart).first();
      if (existingPart) return json({ sessionId, chunkNumber, partNumber: targetPart, partReady: true, alreadyStored: true });
      const stagedKey = stagedChunkKey(session, chunkNumber);
      const stagedUpload = await storage.fetch(objectUrl(env, stagedKey), {
        method: "PUT", headers: { "Content-Length": String(bytes.byteLength), "Content-Type": "application/octet-stream" }, body: bytes
      });
      if (!stagedUpload.ok) return json({ error: "Could not stage transport chunk", storageStatus: stagedUpload.status }, 502);
      try {
        await env.DB.prepare(
          "INSERT INTO media_upload_chunks (session_id, chunk_number, size) VALUES (?, ?, ?) " +
          "ON CONFLICT(session_id, chunk_number) DO UPDATE SET size = excluded.size, uploaded_at = CURRENT_TIMESTAMP"
        ).bind(sessionId, chunkNumber, bytes.byteLength).run();
      } catch (error) {
        await storage.fetch(objectUrl(env, stagedKey), { method: "DELETE" }).catch(() => {});
        throw error;
      }
      const firstChunk = (targetPart - 1) * chunksPerPart + 1;
      const expectedChunks = Math.ceil(Number(session.total_size) / MEDIA_TRANSPORT_CHUNK_SIZE);
      const lastChunk = Math.min(targetPart * chunksPerPart, expectedChunks);
      const stagedRows = await env.DB.prepare(
        "SELECT chunk_number AS chunkNumber, size FROM media_upload_chunks WHERE session_id = ? AND chunk_number BETWEEN ? AND ? ORDER BY chunk_number"
      ).bind(sessionId, firstChunk, lastChunk).all();
      const readyRows = stagedRows.results || [];
      if (readyRows.length !== lastChunk - firstChunk + 1) return json({ sessionId, chunkNumber, partNumber: targetPart, partReady: false });
      const buffers = [];
      let totalBytes = 0;
      for (let number = firstChunk; number <= lastChunk; number++) {
        const response = await storage.fetch(objectUrl(env, stagedChunkKey(session, number)));
        if (!response.ok) return json({ error: "A staged chunk is temporarily unavailable; retry this chunk" }, 503);
        const chunkBytes = new Uint8Array(await response.arrayBuffer());
        const recorded = readyRows.find(item => Number(item.chunkNumber) === number);
        if (!recorded || chunkBytes.byteLength !== Number(recorded.size)) return json({ error: "A staged chunk failed its size integrity check" }, 409);
        buffers.push(chunkBytes); totalBytes += chunkBytes.byteLength;
      }
      const partBytes = new Uint8Array(totalBytes);
      let offset = 0;
      for (const buffer of buffers) { partBytes.set(buffer, offset); offset += buffer.byteLength; }
      try { validateMultipartPart(Number(session.total_size), targetPart, partBytes.byteLength); }
      catch (error) { return json({ error: error.message }, 409); }
      const uploaded = await storage.fetch(objectUrl(env, session.object_key, session.storage_upload_id, targetPart), {
        method: "PUT", headers: { "Content-Length": String(partBytes.byteLength) }, body: partBytes
      });
      if (!uploaded.ok) return json({ error: "Media storage part assembly failed", storageStatus: uploaded.status }, 502);
      let etag;
      try { etag = normalizeMultipartEtag(uploaded.headers.get("ETag")); }
      catch (error) { return json({ error: error.message }, 502); }
      await env.DB.prepare(
        "INSERT INTO media_upload_parts (session_id, part_number, etag, size) VALUES (?, ?, ?, ?) " +
        "ON CONFLICT(session_id, part_number) DO UPDATE SET etag = excluded.etag, size = excluded.size, uploaded_at = CURRENT_TIMESTAMP"
      ).bind(sessionId, targetPart, etag, partBytes.byteLength).run();
      try {
        await deleteStagedChunks(storage, env, session, Array.from({ length: lastChunk - firstChunk + 1 }, (_, index) => firstChunk + index));
        await env.DB.prepare("DELETE FROM media_upload_chunks WHERE session_id = ? AND chunk_number BETWEEN ? AND ?").bind(sessionId, firstChunk, lastChunk).run();
      } catch (cleanupError) {
        console.error("Completed multipart staging cleanup deferred:", cleanupError?.name || "Error");
      }
      await env.DB.prepare("UPDATE media_upload_sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_id = ? AND state = 'uploading'").bind(sessionId, currentUser.sub).run();
      return json({ sessionId, chunkNumber, partNumber: targetPart, etag, size: partBytes.byteLength, partReady: true });
    }

    if (partNumber !== null && method === "PUT") {
      if (session.state !== "uploading") return json({ error: "Upload session is not accepting parts" }, 409);
      if (!Number.isInteger(partNumber) || partNumber < 1 || partNumber > Number(session.expected_parts)) return json({ error: "Invalid part number" }, 400);
      const bytes = await readLimited(request, MEDIA_MULTIPART_PART_SIZE);
      if (!bytes?.byteLength) return json({ error: "Part is empty or exceeds the maximum part size" }, 413);
      try { validateMultipartPart(Number(session.total_size), partNumber, bytes.byteLength); }
      catch (error) { return json({ error: error.message }, 400); }
      const uploaded = await storage.fetch(objectUrl(env, session.object_key, session.storage_upload_id, partNumber), {
        method: "PUT", headers: { "Content-Length": String(bytes.byteLength) }, body: bytes
      });
      if (!uploaded.ok) return json({ error: "Media part upload failed", storageStatus: uploaded.status }, 502);
      let etag;
      try { etag = normalizeMultipartEtag(uploaded.headers.get("ETag")); }
      catch (error) { return json({ error: error.message }, 502); }
      await env.DB.prepare(
        `INSERT INTO media_upload_parts (session_id, part_number, etag, size)
         VALUES (?, ?, ?, ?) ON CONFLICT(session_id, part_number) DO UPDATE SET
         etag = excluded.etag, size = excluded.size, uploaded_at = CURRENT_TIMESTAMP`
      ).bind(sessionId, partNumber, etag, bytes.byteLength).run();
      await env.DB.prepare("UPDATE media_upload_sessions SET updated_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_id = ? AND state = 'uploading'").bind(sessionId, currentUser.sub).run();
      return json({ sessionId, partNumber, etag, size: bytes.byteLength });
    }

    if (action === "complete" && method === "POST") {
      if (session.state === "completed") {
        return json({ attachment: { attachmentId: session.object_key, fileName: session.file_name,
          contentType: session.content_type, size: Number(session.total_size),
          recipientId: session.recipient_id, groupId: session.group_id }, alreadyCompleted: true });
      }
      if (session.state !== "uploading" && session.state !== "completing") return json({ error: "Upload session cannot be completed" }, 409);
      const rows = await env.DB.prepare("SELECT part_number AS partNumber, etag, size FROM media_upload_parts WHERE session_id = ? ORDER BY part_number").bind(sessionId).all();
      const parts = rows.results || [];
      if (parts.length !== Number(session.expected_parts) || parts.reduce((sum, part) => sum + Number(part.size), 0) !== Number(session.total_size)) {
        return json({ error: "Upload is incomplete; all parts must be uploaded before completion" }, 409);
      }
      let xml;
      try { xml = buildCompleteMultipartXml(parts); }
      catch (error) { return json({ error: error.message }, 409); }
      await env.DB.prepare("UPDATE media_upload_sessions SET state = 'completing', updated_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_id = ?").bind(sessionId, currentUser.sub).run();
      const completed = await storage.fetch(objectUrl(env, session.object_key, session.storage_upload_id), {
        method: "POST", headers: { "Content-Type": "application/xml" }, body: xml
      });
      if (!completed.ok) {
        await env.DB.prepare("UPDATE media_upload_sessions SET state = 'uploading', updated_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_id = ?").bind(sessionId, currentUser.sub).run();
        return json({ error: "Storage could not complete the media upload", storageStatus: completed.status }, 502);
      }
      const completionXml = await completed.text();
      if (/<Error[>\\s]/i.test(completionXml)) {
        await env.DB.prepare("UPDATE media_upload_sessions SET state = 'uploading', updated_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_id = ?").bind(sessionId, currentUser.sub).run();
        return json({ error: "Storage reported a multipart completion error" }, 502);
      }
      await env.DB.prepare(`CREATE TABLE IF NOT EXISTS media_access (
        object_key TEXT PRIMARY KEY, owner_id TEXT NOT NULL, recipient_id TEXT,
        group_id TEXT, file_name TEXT NOT NULL, content_type TEXT NOT NULL, expires_at TEXT NOT NULL
      )`).run();
      const permanentExpiry = "9999-12-31T23:59:59.999Z";
      const results = await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO media_access (object_key, owner_id, recipient_id, group_id, file_name, content_type, expires_at)
           VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(object_key) DO UPDATE SET
           owner_id = excluded.owner_id, recipient_id = excluded.recipient_id,
           group_id = excluded.group_id, file_name = excluded.file_name,
           content_type = excluded.content_type, expires_at = excluded.expires_at`
        ).bind(session.object_key, currentUser.sub, session.recipient_id, session.group_id,
          session.file_name, session.content_type, permanentExpiry),
        env.DB.prepare("UPDATE media_upload_sessions SET state = 'completed', completed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_id = ?").bind(sessionId, currentUser.sub)
      ]);
      if (Number(results?.[1]?.meta?.changes || 0) !== 1) return json({ error: "Media uploaded but final metadata could not be confirmed; recovery is required" }, 503);
      return json({ attachment: { attachmentId: session.object_key, fileName: session.file_name,
        contentType: session.content_type, size: Number(session.total_size),
        recipientId: session.recipient_id, groupId: session.group_id } }, 201);
    }

    if (method === "DELETE" && !action && partNumber === null) {
      if (session.state === "completed") return json({ error: "Completed media cannot be aborted through its upload session" }, 409);
      const staged = await env.DB.prepare("SELECT chunk_number AS chunkNumber FROM media_upload_chunks WHERE session_id = ?").bind(sessionId).all();
      const aborted = await storage.fetch(objectUrl(env, session.object_key, session.storage_upload_id), { method: "DELETE" });
      if (!aborted.ok && aborted.status !== 404) return json({ error: "Storage could not abort the upload", storageStatus: aborted.status }, 502);
      await deleteStagedChunks(storage, env, session, (staged.results || []).map(item => Number(item.chunkNumber)));
      await env.DB.prepare("DELETE FROM media_upload_chunks WHERE session_id = ?").bind(sessionId).run();
      await env.DB.prepare("UPDATE media_upload_sessions SET state = 'aborted', updated_at = CURRENT_TIMESTAMP WHERE id = ? AND owner_id = ?").bind(sessionId, currentUser.sub).run();
      await env.DB.prepare("DELETE FROM media_upload_parts WHERE session_id = ?").bind(sessionId).run();
      return json({ sessionId, state: "aborted" });
    }
    return json({ error: "Method not allowed" }, 405);
  } catch (error) {
    console.error("Resumable media upload request failed:", error?.name || "Error");
    return json({ error: "Resumable media upload is temporarily unavailable" }, 500);
  }
}
