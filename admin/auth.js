const encoder = new TextEncoder();

function encodeBase64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\\+/g, "-").replace(/\\//g, "_").replace(/=+$/, "");
}

export async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return [...new Uint8Array(digest)]
    .map(byte => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function createRefreshToken() {
  return encodeBase64url(crypto.getRandomValues(new Uint8Array(32)));
}

export async function createAdminAccessToken(
  secret,
  subject,
  sessionId,
  deviceId,
  now = Math.floor(Date.now() / 1000)
) {
  if (!secret || secret.length < 32) {
    throw new Error("admin_signing_secret_missing");
  }
  const header = encodeBase64url(
    encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" }))
  );
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
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(header + "." + payload)
  );
  return header + "." + payload + "." +
    encodeBase64url(new Uint8Array(signature));
}
