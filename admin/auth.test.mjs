import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import {
  createAdminAccessToken,
  createRefreshToken,
  sha256Hex
} from "./auth.js";

const ownerSubject = "barq-admin-owner-v1";
const now = Math.floor(Date.now() / 1000);

test("Admin access tokens carry short-lived owner, device and session claims", async () => {
  const secret = "x".repeat(40);
  const token = await createAdminAccessToken(
    secret, ownerSubject, "session-1", "device-1", now
  );
  const [header, payload, signature] = token.split(".");
  assert.equal(
    JSON.parse(Buffer.from(header, "base64url").toString()).alg,
    "HS256"
  );
  const claims = JSON.parse(Buffer.from(payload, "base64url").toString());
  assert.equal(claims.sub, ownerSubject);
  assert.equal(claims.sid, "session-1");
  assert.equal(claims.did, "device-1");
  assert.equal(claims.exp - claims.iat, 600);
  assert.ok(signature.length > 20);
  const expected = createHmac("sha256", secret)
    .update(header + "." + payload)
    .digest("base64url");
  assert.equal(signature, expected);
  await assert.rejects(
    () => createAdminAccessToken("too-short", ownerSubject, "session-1", "device-1", now),
    /admin_signing_secret_missing/
  );
});

test("refresh tokens are high entropy and only their SHA-256 hash is persisted", async () => {
  const first = createRefreshToken();
  const second = createRefreshToken();
  assert.notEqual(first, second);
  assert.ok(first.length >= 40);
  assert.equal(
    await sha256Hex("abc"),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  );
  assert.equal(await sha256Hex(first), await sha256Hex(first));
  assert.notEqual(await sha256Hex(first), first);
});
