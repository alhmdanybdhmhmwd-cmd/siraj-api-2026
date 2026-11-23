import test from "node:test";
import assert from "node:assert/strict";
import { createHmac, generateKeyPairSync, sign } from "node:crypto";
import { verifyGoogleIdToken, createAdminAccessToken, createRefreshToken, sha256Hex } from "./auth.js";

const clientId = "barq-admin-android-client.apps.googleusercontent.com";
const ownerSub = "google-owner-subject-123";
const nonce = "n".repeat(48);
const now = Math.floor(Date.now() / 1000);

function b64url(value) {
  return Buffer.from(value).toString("base64url");
}

async function fixture(overrides = {}) {
  const { publicKey, privateKey } = generateKeyPairSync("rsa", {
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
    { iat: now + 120 },
    { nbf: now + 120 },
    { nbf: "not-a-timestamp" },
    { sub: "" },
    { aud: [clientId, "another-client"] }
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
  const expected = createHmac("sha256", "x".repeat(40))
    .update(header + "." + payload)
    .digest("base64url");
  assert.equal(signature, expected);
  await assert.rejects(
    () => createAdminAccessToken("too-short", ownerSub, "session-1", "device-1", now),
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

test("owner email allowlist works without a pre-known Google subject", async () => {
  const item = await fixture();
  const env = {
    BARQ_GOOGLE_OIDC_CLIENT_ID: clientId,
    BARQ_ADMIN_OWNER_EMAIL: "OWNER@EXAMPLE.TEST"
  };
  const identity = await verifyGoogleIdToken(item.token, nonce, env, {
    fetcher: item.fetcher, nowMs: now * 1000
  });
  assert.equal(identity.subject, ownerSub);
  await assert.rejects(() => verifyGoogleIdToken(item.token, nonce, {
    ...env, BARQ_ADMIN_OWNER_EMAIL: "other@example.test"
  }, { fetcher: item.fetcher, nowMs: now * 1000 }));
});

test("Google ID token rejects tampered signatures and unauthorized azp", async () => {
  const item = await fixture();
  const env = { BARQ_GOOGLE_OIDC_CLIENT_ID: clientId, BARQ_ADMIN_OWNER_SUBJECT: ownerSub };
  const parts = item.token.split(".");
  const changedSignature = (parts[2][0] === "A" ? "B" : "A") + parts[2].slice(1);
  const tampered = parts[0] + "." + parts[1] + "." + changedSignature;
  await assert.rejects(() => verifyGoogleIdToken(tampered, nonce, env, {
    fetcher: item.fetcher, nowMs: now * 1000
  }), /invalid_google_signature/);
  const validAzp = await fixture({ aud: [clientId, "another-client"], azp: clientId });
  const validIdentity = await verifyGoogleIdToken(validAzp.token, nonce, env, {
    fetcher: validAzp.fetcher, nowMs: now * 1000
  });
  assert.equal(validIdentity.subject, ownerSub);
  const wrongAzp = await fixture({ aud: [clientId, "another-client"], azp: "another-client" });
  await assert.rejects(() => verifyGoogleIdToken(wrongAzp.token, nonce, env, {
    fetcher: wrongAzp.fetcher, nowMs: now * 1000
  }), /claims_rejected/);
});
