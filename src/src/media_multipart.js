export const MEDIA_MULTIPART_PART_SIZE = 5 * 1024 * 1024;
// Transport chunks remain below the default Vercel request payload ceiling.
export const MEDIA_TRANSPORT_CHUNK_SIZE = 1 * 1024 * 1024;
export const MEDIA_MULTIPART_MAX_SIZE = 60 * 1024 * 1024;
export const MEDIA_MULTIPART_MAX_PARTS = Math.ceil(
  MEDIA_MULTIPART_MAX_SIZE / MEDIA_MULTIPART_PART_SIZE
);
export const MEDIA_UPLOAD_SESSION_TTL_MS = 24 * 60 * 60 * 1000;

export function validateMultipartDeclaration({ size, contentType, fileName, caption = '' }) {
  const normalizedSize = Number(size);
  if (!Number.isSafeInteger(normalizedSize) || normalizedSize < 1 ||
      normalizedSize > MEDIA_MULTIPART_MAX_SIZE) {
    throw new RangeError("File size must be between 1 byte and 60 MiB");
  }
  const type = String(contentType || "").split(";")[0].trim().toLowerCase();
  const allowedTypes = /^(image\/(jpeg|png|webp|gif)|video\/(mp4|webm|quicktime)|audio\/(mpeg|mp4|aac|wav|ogg|webm)|application\/(octet-stream|pdf|zip|msword|vnd\.ms-excel|vnd\.ms-powerpoint|vnd\.openxmlformats-officedocument\.[a-z0-9.]+)|text\/plain)$/;
  if (!allowedTypes.test(type)) throw new TypeError("Unsupported media type");
  const name = String(fileName || "attachment").replace(/[\\/\x00-\x1f\x7f]/g, "_").trim().slice(0, 180) || "attachment";
  const normalizedCaption = String(caption || '').trim();
  if (normalizedCaption.length > 2000) throw new RangeError('Media caption must not exceed 2000 characters');
  return { size: normalizedSize, contentType: type, fileName: name, caption: normalizedCaption };
}

export function getMultipartPartBounds(totalSize, partNumber) {
  if (!Number.isSafeInteger(totalSize) || totalSize < 1 || totalSize > MEDIA_MULTIPART_MAX_SIZE) {
    throw new RangeError("Invalid total upload size");
  }
  if (!Number.isSafeInteger(partNumber) || partNumber < 1 || partNumber > MEDIA_MULTIPART_MAX_PARTS) {
    throw new RangeError("Invalid multipart part number");
  }
  const start = (partNumber - 1) * MEDIA_MULTIPART_PART_SIZE;
  if (start >= totalSize) throw new RangeError("Part number exceeds declared file size");
  const endExclusive = Math.min(start + MEDIA_MULTIPART_PART_SIZE, totalSize);
  return { start, endExclusive, size: endExclusive - start, isLast: endExclusive === totalSize };
}

export function validateMultipartPart(totalSize, partNumber, receivedSize) {
  const bounds = getMultipartPartBounds(totalSize, partNumber);
  if (!Number.isSafeInteger(receivedSize) || receivedSize !== bounds.size) {
    throw new RangeError("Uploaded part size does not match its declared byte range");
  }
  return bounds;
}

export function normalizeMultipartEtag(value) {
  const etag = String(value || "").trim();
  if (!/^"?[a-fA-F0-9-]{8,128}"?$/.test(etag)) {
    throw new TypeError("Storage returned an invalid multipart ETag");
  }
  return etag.startsWith('"') ? etag : '"' + etag + '"';
}

export function parseMultipartUploadId(xml) {
  const source = String(xml || "");
  const match = source.match(/<UploadId>([^<]{1,2048})<\/UploadId>/i);
  if (!match) throw new TypeError("Storage did not return a multipart upload identifier");
  const value = match[1].trim();
  if (!value || /[\r\n]/.test(value)) throw new TypeError("Invalid multipart upload identifier");
  return value;
}

export function buildCompleteMultipartXml(parts) {
  if (!Array.isArray(parts) || parts.length < 1 || parts.length > MEDIA_MULTIPART_MAX_PARTS) {
    throw new RangeError("Invalid multipart completion part list");
  }
  const sorted = [...parts].sort((a, b) => a.partNumber - b.partNumber);
  for (let i = 0; i < sorted.length; i++) {
    if (sorted[i].partNumber !== i + 1) throw new RangeError("Multipart parts must be contiguous");
    const etag = normalizeMultipartEtag(sorted[i].etag);
    sorted[i] = { partNumber: sorted[i].partNumber, etag };
  }
  const entries = sorted.map(part =>
    "<Part><PartNumber>" + part.partNumber + "</PartNumber><ETag>" +
    part.etag.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") +
    "</ETag></Part>"
  ).join("");
  return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><CompleteMultipartUpload>" +
    entries + "</CompleteMultipartUpload>";
}

export function isUploadSessionExpired(expiresAt, now = Date.now()) {
  const timestamp = Date.parse(expiresAt);
  return !Number.isFinite(timestamp) || timestamp <= now;
}

export function getTransportChunkBounds(totalSize, chunkNumber) {
  if (!Number.isSafeInteger(totalSize) || totalSize < 1 || totalSize > MEDIA_MULTIPART_MAX_SIZE) {
    throw new RangeError("Invalid total upload size");
  }
  const expectedChunks = Math.ceil(totalSize / MEDIA_TRANSPORT_CHUNK_SIZE);
  if (!Number.isSafeInteger(chunkNumber) || chunkNumber < 1 || chunkNumber > expectedChunks) {
    throw new RangeError("Invalid transport chunk number");
  }
  const start = (chunkNumber - 1) * MEDIA_TRANSPORT_CHUNK_SIZE;
  const endExclusive = Math.min(start + MEDIA_TRANSPORT_CHUNK_SIZE, totalSize);
  return { start, endExclusive, size: endExclusive - start, isLast: endExclusive === totalSize };
}

export function validateTransportChunk(totalSize, chunkNumber, receivedSize) {
  const bounds = getTransportChunkBounds(totalSize, chunkNumber);
  if (!Number.isSafeInteger(receivedSize) || receivedSize !== bounds.size) {
    throw new RangeError("Transport chunk size does not match its declared byte range");
  }
  return bounds;
}

export function matchesUploadDeclaration(existing, declaration, recipientId, groupId) {
  return Number(existing?.size) === declaration.size &&
    existing?.recipientId === recipientId &&
    existing?.groupId === groupId &&
    existing?.contentType === declaration.contentType &&
    existing?.fileName === declaration.fileName &&
    String(existing?.caption || '') === String(declaration?.caption || '');
}
