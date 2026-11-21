import test from "node:test";
import assert from "node:assert/strict";
import {
  MEDIA_MULTIPART_PART_SIZE,
  MEDIA_MULTIPART_MAX_SIZE,
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
  }), { size: 10, contentType: "image/png", fileName: ".._photo.png" });
});

test("multipart declaration rejects empty, oversized and unsupported files", () => {
  assert.throws(() => validateMultipartDeclaration({ size: 0, contentType: "image/png" }), RangeError);
  assert.throws(() => validateMultipartDeclaration({ size: MEDIA_MULTIPART_MAX_SIZE + 1, contentType: "image/png" }), RangeError);
  assert.throws(() => validateMultipartDeclaration({ size: 5, contentType: "application/x-executable" }), TypeError);
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
