import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPair, sign } from "node:crypto";
import { verifyGoogleIdToken, createAdminAccessToken, createRefreshToken, sha256Hex } from "./auth.js";

const clientId = "barq-admin-android-client.apps.googleusercontent.com";
const ownerSub = "google-owner-subject-123";
const nonce = "n".repeat(48);
const now = Math.floor(Date.now() / 1000);

function b64url(value) {
  return Buffer.from(value).toString("base64url");
}

async function fixture(overrides = {}) {
  const { publicKey, privateKey } = await generateKeyPair("rsa", {
    modulusLength: 2048,
  });
  const jwk = { ...publicKey.export({ format: "jwk" }), kid: "test-key", use: "sig", alg: "RS256" };
  const claims = {
    iss: "https://accounts.google.com", aud: clientId, sub: ownerSub,
    exp: now + 300, iat: now, email: "owner@example.test",
    email_verified: true, nonce, ...overrides
  };
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT", kid: "test-key" }));
  const payload = b64url(JSON.stringify(claims));
  const input = header + "." + payload;
  const signature = sign("RSA-SHA256", Buffer.from(input), privateKey).toString("base64url");
  return {
    token: input + "." + signature,
    fetcher: async () => new Response(JSON.stringify({ keys: [jwk] }), {
      status: 200, headers: { "Content-Type": "application/json" }
    })
  };
}

test("Google ID token requires a valid RS256 signature and exact owner identity", async () => {
  const item = await fixture();
  const env = { BARQ_GOOGLE_OIDC_CLIENT_ID: clientId, BARQ_ADMIN_OWNER_SUBJECT: ownerSub };
  const identity = await verifyGoogleIdToken(item.token, nonce, env, { fetcher: item.fetcher, nowMs: now * 1000 });
  assert.deepEqual(identity, { subject: ownerSub, email: "owner@example.test" });
  await assert.rejects(() => verifyGoogleIdToken(item.token, "x".repeat(48), env, {
    fetcher: item.fetcher, nowMs: now * 1000
  }), /claims_rejected/);
});

test("Google ID token rejects wrong audience, issuer, owner, expiry and unverified email", async () => {
  const env = { BARQ_GOOGLE_OIDC_CLIENT_ID: clientId, BARQ_ADMIN_OWNER_SUBJECT: ownerSub };
  for (const override of [
    { aud: "other-client" },
    { iss: "https://attacker.example" },
    { sub: "different-owner" },
    { exp: now - 1 },
    { email_verified: false },
    { iat: now + 120 }
  ]) {
    const item = await fixture(override);
    await assert.rejects(() => verifyGoogleIdToken(item.token, nonce, env, {
      fetcher: item.fetcher, nowMs: now * 1000
    }));
  }
});

test("Admin access tokens carry short-lived owner, device and session claims", async () => {
  const token = await createAdminAccessToken("x".repeat(40), ownerSub, "session-1", "device-1", now);
  const [header, payload, signature] = token.split(".");
  assert.equal(JSON.parse(Buffer.from(header, "base64url").toString()).alg, "HS256");
  const claims = JSON.parse(Buffer.from(payload, "base64url").toString());
  assert.equal(claims.sub, ownerSub);
  assert.equal(claims.sid, "session-1");
  assert.equal(claims.did, "device-1");
  assert.equal(claims.exp - claims.iat, 600);
  assert.ok(signature.length > 20);
});

test("refresh tokens are high entropy and only their SHA-256 hash is persisted", async () => {
  const first = createRefreshToken();
  const second = createRefreshToken();
  assert.notEqual(first, second);
  assert.ok(first.length >= 40);
  assert.equal(await sha256Hex(first), await sha256Hex(first));
  assert.notEqual(await sha256Hex(first), first);
});
