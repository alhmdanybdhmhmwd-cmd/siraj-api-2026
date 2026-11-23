import test from "node:test";
import assert from "node:assert/strict";
import {
  MEDIA_MULTIPART_PART_SIZE,
  MEDIA_MULTIPART_MAX_SIZE,
  MEDIA_TRANSPORT_CHUNK_SIZE,
  getTransportChunkBounds,
  validateTransportChunk,
  matchesUploadDeclaration,
  getMultipartPartBounds,
  validateMultipartDeclaration,
  validateMultipartPart,
  normalizeMultipartEtag,
  parseMultipartUploadId,
  buildCompleteMultipartXml,
  isUploadSessionExpired
} from "../src/src/media_multipart.js";

test("multipart declaration accepts supported files and sanitizes file names", () => {
  assert.deepEqual(validateMultipartDeclaration({
    size: 10, contentType: "IMAGE/PNG; charset=binary", fileName: "../photo.png"
  }), { size: 10, contentType: "image/png", fileName: ".._photo.png", caption: "" });
});

test("multipart declaration rejects empty, oversized and unsupported files", () => {
  assert.throws(() => validateMultipartDeclaration({ size: 0, contentType: "image/png" }), RangeError);
  assert.throws(() => validateMultipartDeclaration({ size: MEDIA_MULTIPART_MAX_SIZE + 1, contentType: "image/png" }), RangeError);
  assert.throws(() => validateMultipartDeclaration({ size: 5, contentType: "application/x-executable" }), TypeError);
  assert.throws(() => validateMultipartDeclaration({ size: 5, contentType: "image/png", caption: "x".repeat(2001) }), RangeError);
});

test("part bounds use 5 MiB pieces and permit a smaller final part", () => {
  const first = getMultipartPartBounds(MEDIA_MULTIPART_PART_SIZE + 17, 1);
  const last = getMultipartPartBounds(MEDIA_MULTIPART_PART_SIZE + 17, 2);
  assert.equal(first.size, MEDIA_MULTIPART_PART_SIZE);
  assert.equal(first.isLast, false);
  assert.equal(last.size, 17);
  assert.equal(last.isLast, true);
});

test("part bounds reject gaps and parts beyond the declared file", () => {
  assert.throws(() => getMultipartPartBounds(100, 2), RangeError);
  assert.throws(() => getMultipartPartBounds(100, 0), RangeError);
  assert.throws(() => validateMultipartPart(100, 1, 99), RangeError);
  assert.equal(validateMultipartPart(100, 1, 100).size, 100);
});

test("multipart ETags are normalized and malformed values rejected", () => {
  assert.equal(normalizeMultipartEtag("abcdef12"), '"abcdef12"');
  assert.throws(() => normalizeMultipartEtag("bad etag"), TypeError);
});

test("multipart initiation response must contain a valid UploadId", () => {
  assert.equal(parseMultipartUploadId("<UploadId>abc-123</UploadId>"), "abc-123");
  assert.throws(() => parseMultipartUploadId("<Error>no id</Error>"), TypeError);
});

test("completion XML sorts contiguous parts and escapes ETags", () => {
  const xml = buildCompleteMultipartXml([
    { partNumber: 2, etag: "abcdef1234567890" },
    { partNumber: 1, etag: "12345678" }
  ]);
  assert.ok(xml.indexOf("<PartNumber>1</PartNumber>") < xml.indexOf("<PartNumber>2</PartNumber>"));
  assert.throws(() => buildCompleteMultipartXml([{ partNumber: 2, etag: "12345678" }]), RangeError);
});

test("upload sessions expire when their deadline is invalid or elapsed", () => {
  assert.equal(isUploadSessionExpired("invalid", 1000), true);
  assert.equal(isUploadSessionExpired(new Date(1000).toISOString(), 1000), true);
  assert.equal(isUploadSessionExpired(new Date(2000).toISOString(), 1000), false);
});


test("transport chunks are bounded at 1 MiB and cover a 5 MiB part exactly", () => {
  const total = MEDIA_MULTIPART_PART_SIZE + 17;
  for (let number = 1; number <= 5; number++) {
    const bounds = getTransportChunkBounds(total, number);
    assert.equal(bounds.size, MEDIA_TRANSPORT_CHUNK_SIZE);
    assert.equal(bounds.isLast, false);
    assert.equal(validateTransportChunk(total, number, bounds.size).size, MEDIA_TRANSPORT_CHUNK_SIZE);
  }
  const last = getTransportChunkBounds(total, 6);
  assert.equal(last.size, 17);
  assert.equal(last.isLast, true);
  assert.throws(() => validateTransportChunk(total, 6, 16), RangeError);
  assert.throws(() => getTransportChunkBounds(total, 7), RangeError);
});

test("transport chunk bounds cover the 60 MiB maximum without gaps", () => {
  const total = MEDIA_MULTIPART_MAX_SIZE;
  let cursor = 0;
  for (let number = 1; number <= 60; number++) {
    const bounds = getTransportChunkBounds(total, number);
    assert.equal(bounds.start, cursor);
    cursor = bounds.endExclusive;
  }
  assert.equal(cursor, total);
  assert.throws(() => getTransportChunkBounds(total + 1, 1), RangeError);
});

test("resuming an upload requires the exact file and conversation declaration", () => {
  const existing = {
    size: 1234, recipientId: "friend-1", groupId: null,
    contentType: "image/png", fileName: "photo.png"
  };
  const declaration = { size: 1234, contentType: "image/png", fileName: "photo.png" };
  assert.equal(matchesUploadDeclaration(existing, declaration, "friend-1", null), true);
  assert.equal(matchesUploadDeclaration(existing, { ...declaration, caption: "تعليق" }, "friend-1", null), false);
  assert.equal(matchesUploadDeclaration(existing, declaration, "friend-2", null), false);
  assert.equal(matchesUploadDeclaration(existing, declaration, null, "group-1"), false);
  assert.equal(matchesUploadDeclaration(existing, { ...declaration, fileName: "other.png" }, "friend-1", null), false);
  assert.equal(matchesUploadDeclaration(existing, { ...declaration, contentType: "image/jpeg" }, "friend-1", null), false);
  assert.equal(matchesUploadDeclaration(existing, { ...declaration, size: 999 }, "friend-1", null), false);
});
