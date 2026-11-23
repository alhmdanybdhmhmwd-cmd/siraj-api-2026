const encoder = new TextEncoder();

function decodeBase64url(value) {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]+$/.test(value)) throw new Error("invalid_base64url");
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized + "=".repeat((4 - normalized.length % 4) % 4));
  return Uint8Array.from(binary, char => char.charCodeAt(0));
}

function encodeBase64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function constantTimeEqual(left, right) {
  if (typeof left !== "string" || typeof right !== "string" || left.length !== right.length) return false;
  let mismatch = 0;
  for (let i = 0; i < left.length; i++) mismatch |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return mismatch === 0;
}

export async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, "0")).join("");
}

let cachedJwks = null;
let cachedJwksAt = 0;

async function googleJwks(fetcher = fetch, nowMs = Date.now()) {
  if (fetcher === fetch && cachedJwks && nowMs - cachedJwksAt < 60 * 60 * 1000) return cachedJwks;
  const response = await fetcher("https://www.googleapis.com/oauth2/v3/certs", {
    headers: { Accept: "application/json" },
    cf: { cacheTtl: 3600, cacheEverything: true }
  });
  if (!response.ok) throw new Error("google_jwks_unavailable");
  const body = await response.json();
  if (!Array.isArray(body.keys) || body.keys.length === 0) throw new Error("google_jwks_invalid");
  if (fetcher === fetch) {
    cachedJwks = body.keys;
    cachedJwksAt = nowMs;
  }
  return body.keys;
}

export async function verifyGoogleIdToken(idToken, expectedNonce, env, options = {}) {
  if (typeof idToken !== "string" || idToken.length > 12000 ||
      typeof expectedNonce !== "string" || expectedNonce.length < 32 || expectedNonce.length > 256 ||
      !env.BARQ_GOOGLE_OIDC_CLIENT_ID || (!env.BARQ_ADMIN_OWNER_SUBJECT && !env.BARQ_ADMIN_OWNER_EMAIL)) {
    throw new Error("invalid_identity_request");
  }
  const parts = idToken.split(".");
  if (parts.length !== 3) throw new Error("invalid_google_token");
  const header = JSON.parse(new TextDecoder().decode(decodeBase64url(parts[0])));
  const claims = JSON.parse(new TextDecoder().decode(decodeBase64url(parts[1])));
  if (header.alg !== "RS256" || typeof header.kid !== "string" || (header.typ !== undefined && header.typ !== "JWT")) {
    throw new Error("invalid_google_token_header");
  }
  const keys = await googleJwks(options.fetcher || fetch, options.nowMs ?? Date.now());
  let jwk = keys.find(key => key.kid === header.kid && key.kty === "RSA" && key.use === "sig" &&
    (!key.alg || key.alg === "RS256"));
  if (!jwk && options.fetcher === undefined && cachedJwks) {
    cachedJwks = null;
    cachedJwksAt = 0;
    const refreshedKeys = await googleJwks(fetch, options.nowMs ?? Date.now());
    jwk = refreshedKeys.find(key => key.kid === header.kid && key.kty === "RSA" && key.use === "sig" &&
      (!key.alg || key.alg === "RS256"));
  }
  if (!jwk) throw new Error("google_signing_key_not_found");
  const key = await crypto.subtle.importKey(
    "jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]
  );
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5", key, decodeBase64url(parts[2]), encoder.encode(parts[0] + "." + parts[1])
  );
  if (!valid) throw new Error("invalid_google_signature");
  const now = Math.floor((options.nowMs ?? Date.now()) / 1000);
  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!["https://accounts.google.com", "accounts.google.com"].includes(claims.iss) ||
      !audiences.includes(env.BARQ_GOOGLE_OIDC_CLIENT_ID) ||
      (claims.azp !== undefined && claims.azp !== env.BARQ_GOOGLE_OIDC_CLIENT_ID) ||
      !Number.isSafeInteger(claims.exp) || claims.exp <= now ||
      !Number.isSafeInteger(claims.iat) || claims.iat > now + 60 ||
      typeof claims.sub !== "string" || claims.email_verified !== true ||
      (env.BARQ_ADMIN_OWNER_SUBJECT && claims.sub !== env.BARQ_ADMIN_OWNER_SUBJECT) ||
      (env.BARQ_ADMIN_OWNER_EMAIL && String(claims.email || "").toLowerCase() !== env.BARQ_ADMIN_OWNER_EMAIL.toLowerCase()) ||
      !constantTimeEqual(claims.nonce || "", expectedNonce)) {
    throw new Error("google_identity_claims_rejected");
  }
  return { subject: claims.sub, email: typeof claims.email === "string" ? claims.email : "" };
}

export function createRefreshToken() {
  return encodeBase64url(crypto.getRandomValues(new Uint8Array(32)));
}

export async function createAdminAccessToken(secret, subject, sessionId, deviceId, now = Math.floor(Date.now() / 1000)) {
  if (!secret || secret.length < 32) throw new Error("admin_signing_secret_missing");
  const header = encodeBase64url(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = encodeBase64url(encoder.encode(JSON.stringify({
    iss: "barq-admin-auth",
    aud: "barq-admin",
    sub: subject,
    sid: sessionId,
    did: deviceId,
    iat: now,
    nbf: now,
    exp: now + 600,
    jti: crypto.randomUUID()
  })));
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(header + "." + payload));
  return header + "." + payload + "." + encodeBase64url(new Uint8Array(signature));
}
