import { AwsClient } from "aws4fetch";
import { prepareConversationSummaryTranscript, buildConversationSummaryMessages, extractConversationSummaryText } from "./conversation_summary.js";


const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-File-Name, X-Recipient-Id, X-Group-Id, X-Status-Caption, X-Status-Id, X-Audio-Duration-Ms",
  "Content-Type": "application/json; charset=utf-8"
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders
  });

const encoder = new TextEncoder();

function base64url(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function decodeBase64url(value) {
  const s = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(s + "=".repeat((4 - s.length % 4) % 4));
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}


async function ensureAccountSecurity(env) {
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS account_security (
      user_id TEXT PRIMARY KEY,
      session_version INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  `).run();
}

async function getSessionVersion(env, userId) {
  await ensureAccountSecurity(env);
  await env.DB.prepare(
    "INSERT OR IGNORE INTO account_security (user_id, session_version) VALUES (?, 0)"
  ).bind(userId).run();
  const row = await env.DB.prepare(
    "SELECT session_version FROM account_security WHERE user_id = ?"
  ).bind(userId).first();
  return Number(row?.session_version || 0);
}

async function signToken(user, secret, sessionVersion = 0) {
  const header = base64url(
    encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" }))
  );

  const payload = base64url(
    encoder.encode(JSON.stringify({
      sub: user.id,
      username: user.username,
      sv: Number(sessionVersion || 0),
      exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30
    }))
  );

  const data = header + "." + payload;

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
    encoder.encode(data)
  );

  return data + "." + base64url(new Uint8Array(signature));
}

async function verifyToken(token, secret) {
  try {
    if (typeof token !== "string" || token.length > 8192) return null;
    const parts = token.split(".");
    if (parts.length !== 3) return null;

    // Accept only the exact JWT profile issued by this API.
    const header = JSON.parse(
      new TextDecoder().decode(decodeBase64url(parts[0]))
    );
    if (header.alg !== "HS256" || header.typ !== "JWT") return null;

    const key = await crypto.subtle.importKey(
      "raw",
      encoder.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"]
    );

    const valid = await crypto.subtle.verify(
      "HMAC",
      key,
      decodeBase64url(parts[2]),
      encoder.encode(parts[0] + "." + parts[1])
    );

    if (!valid) return null;

    const payload = JSON.parse(
      new TextDecoder().decode(decodeBase64url(parts[1]))
    );

    if (
      !payload.sub ||
      !payload.exp ||
      payload.exp < Math.floor(Date.now() / 1000)
    ) {
      return null;
    }

    return payload;
  } catch {
    return null;
  }
}

async function hashPassword(password, salt) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(password),
    "PBKDF2",
    false,
    ["deriveBits"]
  );

  const bits = await crypto.subtle.deriveBits(
    {
      name: "PBKDF2",
      salt: decodeBase64url(salt),
      iterations: 100000,
      hash: "SHA-256"
    },
    key,
    256
  );

  return base64url(new Uint8Array(bits));
}

async function authenticate(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";

  if (!token) return null;

  const payload = await verifyToken(token, env.JWT_SECRET);
  if (!payload || !Number.isSafeInteger(payload.sv) || payload.sv < 0) return null;
  try {
    const row = await env.DB.prepare(
      "SELECT session_version FROM account_security WHERE user_id = ?"
    ).bind(payload.sub).first();
    // A valid session must carry an explicit, non-negative integer version.
    if (!row || !Number.isSafeInteger(Number(row.session_version)) ||
        payload.sv !== Number(row.session_version)) {
      return null;
    }
    const tokenHash = await sha256Hex(token);
    const revoked = await env.DB.prepare(
      "SELECT 1 FROM revoked_sessions WHERE token_hash = ? AND user_id = ? AND expires_at > unixepoch()"
    ).bind(tokenHash, payload.sub).first();
    if (revoked) return null;
  } catch (error) {
    // Never accept a session when its revocation state cannot be verified.
    console.error("Session security check failed:", error);
    return null;
  }
  return payload;
}


function phoneVariants(value) {
  // Accept Arabic-Indic and Persian digits commonly used in saved phone contacts.
  const normalized = String(value || "").replace(/[٠-٩۰-۹]/g, digit => {
    const code = digit.charCodeAt(0);
    return String(code >= 0x06f0 ? code - 0x06f0 : code - 0x0660);
  });
  const digits = normalized.replace(/\D/g, "");
  const variants = new Set();
  const add = candidate => {
    if (candidate.length >= 7 && candidate.length <= 15) variants.add(candidate);
  };
  add(digits);
  const international = digits.startsWith("00") ? digits.slice(2) : digits;
  add(international);
  if (international.startsWith("967") && international.length >= 10) {
    add(international.slice(3));
  }
  if (international.startsWith("0") && international.length >= 8) {
    add(international.slice(1));
  }
  return [...variants];
}


function normalizedPhoneSql(column = "phone") {
  let expression = column;
  const digits = [
    ["٠", "0"], ["١", "1"], ["٢", "2"], ["٣", "3"], ["٤", "4"],
    ["٥", "5"], ["٦", "6"], ["٧", "7"], ["٨", "8"], ["٩", "9"],
    ["۰", "0"], ["۱", "1"], ["۲", "2"], ["۳", "3"], ["۴", "4"],
    ["۵", "5"], ["۶", "6"], ["۷", "7"], ["۸", "8"], ["۹", "9"]
  ];
  for (const [from, to] of digits) {
    expression = `replace(${expression}, '${from}', '${to}')`;
  }
  for (const character of [" ", "+", "-", "(", ")", ".", "\t"]) {
    expression = `replace(${expression}, '${character}', '')`;
  }
  return expression;
}

function phoneConflictCondition(column, phone) {
  const variants = [...new Set(phoneVariants(phone))];
  if (!variants.length) return { sql: "0", bindings: [] };

  const normalized = normalizedPhoneSql(column);
  const placeholders = variants.map(() => "?").join(", ");
  const conditions = [
    `${normalized} IN (${placeholders})`,
    `(substr(${normalized}, 1, 2) = '00' AND substr(${normalized}, 3) IN (${placeholders}))`,
    `(substr(${normalized}, 1, 3) = '967' AND length(${normalized}) >= 10 AND substr(${normalized}, 4) IN (${placeholders}))`,
    `(substr(${normalized}, 1, 1) = '0' AND length(${normalized}) >= 8 AND substr(${normalized}, 2) IN (${placeholders}))`
  ];
  return {
    sql: "(" + conditions.join(" OR ") + ")",
    bindings: [...variants, ...variants, ...variants, ...variants]
  };
}

async function phoneAlreadyInUse(env, phone, excludeUserId = "") {
  const requested = [...new Set(phoneVariants(phone))];
  if (!requested.length) return false;
  const normalizedPhone = normalizedPhoneSql("phone");
  for (let offset = 0; offset < requested.length; offset += 40) {
    const chunk = requested.slice(offset, offset + 40);
    const suffixes = [...new Set(chunk.filter(value => value.length >= 9).map(value => value.slice(-9)))];
    const exactPlaceholders = chunk.map(() => "?").join(", ");
    const suffixPlaceholders = suffixes.map(() => "?").join(", ");
    const result = await env.DB.prepare(
      `SELECT id, phone FROM users
       WHERE id != ? AND (
         ${normalizedPhone} IN (${exactPlaceholders})
         OR substr(${normalizedPhone}, -9) IN (${suffixPlaceholders || "''"})
       )`
    ).bind(excludeUserId, ...chunk, ...suffixes).all();
    for (const candidate of result.results || []) {
      if (phoneVariants(candidate.phone).some(value => requested.includes(value))) {
        return true;
      }
    }
  }
  return false;
}

function cleanUser(user) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.display_name,
    phone: user.phone || null,
    ...(user.photo_updated_at ? {
      photoUrl: "/api/profile/photo/" + encodeURIComponent(user.id),
      photoUpdatedAt: user.photo_updated_at
    } : {})
  };
}

async function readJsonRequestLimited(request, maxBytes = 256 * 1024) {
  const declaredLength = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    try { await request.body?.cancel(); } catch (_) {}
    const error = new Error("JSON request body is too large");
    error.status = 413;
    throw error;
  }
  const bytes = await readRequestBodyLimited(request, maxBytes);
  if (!bytes) {
    const error = new Error("JSON request body is too large");
    error.status = 413;
    throw error;
  }
  return JSON.parse(new TextDecoder().decode(bytes));
}

async function readRequestBodyLimited(request, maxBytes) {
  const stream = request.body;
  if (!stream) return new Uint8Array();
  const reader = stream.getReader();
  const chunks = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      const chunk = value instanceof Uint8Array ? value : new Uint8Array(value);
      total += chunk.byteLength;
      if (total > maxBytes) {
        try { await reader.cancel(); } catch (_) {}
        return null;
      }
      chunks.push(chunk);
    }
  } finally {
    try { reader.releaseLock(); } catch (_) {}
  }
  const result = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function detectSparkMediaType(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const ascii = (start, end) => String.fromCharCode(...b.slice(start, end));
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b.length >= 8 && b[0] === 0x89 && ascii(1, 4) === "PNG" &&
      b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return "image/png";
  if (b.length >= 12 && ascii(0, 4) === "RIFF" && ascii(8, 12) === "WEBP") return "image/webp";
  if (b.length >= 6 && (ascii(0, 6) === "GIF87a" || ascii(0, 6) === "GIF89a")) return "image/gif";
  if (b.length >= 12 && ascii(4, 8) === "ftyp") return "video/mp4";
  if (b.length >= 4 && b[0] === 0x1a && b[1] === 0x45 && b[2] === 0xdf && b[3] === 0xa3) return "video/webm";
  return null;
}

function detectProfileImageType(bytes) {
  const b = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "image/jpeg";
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47 &&
      b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return "image/png";
  if (b.length >= 12 && String.fromCharCode(...b.slice(0, 4)) === "RIFF" &&
      String.fromCharCode(...b.slice(8, 12)) === "WEBP") return "image/webp";
  return null;
}

async function ensureProfilePhotos(env) {
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS profile_photos (
      user_id TEXT PRIMARY KEY,
      object_key TEXT NOT NULL UNIQUE,
      content_type TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  `).run();
}

function safeFileName(value) {
  let decoded = String(value || "attachment");
  try { decoded = decodeURIComponent(decoded); } catch (_) {}
  const cleaned = Array.from(decoded, char => { const code = char.charCodeAt(0); return char === "/" || code === 92 || code < 32 || code === 127 ? "_" : char; }).join("").trim().slice(0, 180);
  return cleaned || "attachment";
}


async function sendSirajPush(env, recipientId, senderId, senderName, messageText, options = {}) {
  const category = ["groups", "statuses"].includes(options.category) ? options.category : "messages";
  const pushType = category === "groups" ? "group_message"
    : category === "statuses" ? "status_update" : "direct_message";
  if (!env.FCM_SERVICE_ACCOUNT_JSON) return;
  try {
    const account = JSON.parse(env.FCM_SERVICE_ACCOUNT_JSON);
    const now = Math.floor(Date.now() / 1000);
    const pem = String(account.private_key || "").replace(/\\n/g, "\n");
    const keyBytes = Uint8Array.from(
      atob(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\\s/g, "")),
      c => c.charCodeAt(0)
    );
    const signingKey = await crypto.subtle.importKey(
      "pkcs8", keyBytes,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false, ["sign"]
    );
    const assertionHeader = base64url(encoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
    const assertionPayload = base64url(encoder.encode(JSON.stringify({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: account.token_uri || "https://oauth2.googleapis.com/token",
      iat: now, exp: now + 3600
    })));
    const unsigned = assertionHeader + "." + assertionPayload;
    const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", signingKey, encoder.encode(unsigned));
    const assertion = unsigned + "." + base64url(new Uint8Array(signature));
    const tokenResponse = await fetch(account.token_uri || "https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion
      })
    });
    if (!tokenResponse.ok) throw new Error("FCM OAuth token request failed: " + tokenResponse.status);
    const tokenData = await tokenResponse.json();
    const projectId = account.project_id || env.FCM_PROJECT_ID;
    if (!projectId || !tokenData.access_token) throw new Error("FCM project or access token missing");

    await env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS notification_preferences (
        user_id TEXT PRIMARY KEY,
        messages INTEGER NOT NULL DEFAULT 1,
        groups INTEGER NOT NULL DEFAULT 1,
        statuses INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    `).run();
    const pref = await env.DB.prepare(
      "SELECT " + category + " AS enabled FROM notification_preferences WHERE user_id = ?"
    ).bind(recipientId).first();
    if (pref && pref.enabled === 0) return;

    await env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS device_tokens (
        user_id TEXT NOT NULL,
        fcm_token TEXT PRIMARY KEY,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    `).run();
    const devices = await env.DB.prepare(
      "SELECT fcm_token FROM device_tokens WHERE user_id = ?"
    ).bind(recipientId).all();

    const preview = String(messageText || "").slice(0, 120);
    await Promise.all((devices.results || []).map(async device => {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": "Bearer " + tokenData.access_token,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            message: {
              token: device.fcm_token,
              notification: {
                title: category === "groups"
                  ? "رسالة في " + String(options.groupName || "مجموعة برق").slice(0, 65)
                  : category === "statuses"
                    ? "SPARK جديد من " + String(senderName || "مستخدم برق").slice(0, 80)
                    : "رسالة من " + String(senderName || "مستخدم برق").slice(0, 80),
                body: category === "statuses" ? "شارك لحظة جديدة في SPARK" : preview || "لديك رسالة جديدة"
              },
              data: {
                type: pushType,
                senderId: String(senderId || ""),
                ...(category === "groups" ? { groupId: String(options.groupId || "") } : {})
              },
              android: { priority: "HIGH", notification: { channel_id: category === "groups" ? "barq_groups" : category === "statuses" ? "barq_statuses" : "barq_messages" } }
            }
          })
        }
      );
      if (!response.ok) {
        const detail = await response.clone().text().catch(() => "");
        if ((response.status === 404 || response.status === 400) &&
            /UNREGISTERED|INVALID_ARGUMENT/i.test(detail)) {
          await env.DB.prepare("DELETE FROM device_tokens WHERE fcm_token = ?")
            .bind(device.fcm_token).run();
        } else {
          console.error("FCM message send failed:", response.status, detail.slice(0, 300));
        }
      }
    }));
  } catch (error) {
    console.error("Barq push delivery failed:", error);
  }
}


const RECOVERY_CODE_TTL_SECONDS = 90 * 24 * 60 * 60;

function randomHex(byteLength) {
  return Array.from(crypto.getRandomValues(new Uint8Array(byteLength)))
    .map(value => value.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(value));
  return Array.from(new Uint8Array(digest))
    .map(value => value.toString(16).padStart(2, "0")).join("");
}

function constantTimeHexEqual(left, right) {
  const a = String(left || "");
  const b = String(right || "");
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let i = 0; i < length; i++) {
    difference |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  }
  return difference === 0;
}

async function generateRecoveryCode() {
  const code = randomHex(20).toUpperCase();
  const salt = randomHex(16);
  const codeHash = await sha256Hex(salt + ":" + code);
  return { code, salt, codeHash };
}

async function saveRecoveryCode(env, userId, recovery) {
  const now = Math.floor(Date.now() / 1000);
  await env.DB.prepare(
    "INSERT INTO recovery_codes (user_id, code_hash, code_salt, expires_at, consumed_at, created_at) VALUES (?, ?, ?, ?, NULL, ?) ON CONFLICT(user_id) DO UPDATE SET code_hash = excluded.code_hash, code_salt = excluded.code_salt, expires_at = excluded.expires_at, consumed_at = NULL, created_at = excluded.created_at"
  ).bind(userId, recovery.codeHash, recovery.salt, now + RECOVERY_CODE_TTL_SECONDS, now).run();
}

async function consumeLoginAttempt(env, scope, identifier, maxAttempts = 10) {
  const normalized = String(identifier || "").trim().toLowerCase().slice(0, 256);
  const bucketKey = await sha256Hex("login:" + scope + ":" + normalized);
  const now = Math.floor(Date.now() / 1000);
  const windowStart = now - 15 * 60;
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS login_rate_limits (
      bucket_key TEXT PRIMARY KEY,
      window_started INTEGER NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0
    )
  `).run();
  await env.DB.prepare(
    "INSERT INTO login_rate_limits (bucket_key, window_started, attempts) VALUES (?, ?, 1) ON CONFLICT(bucket_key) DO UPDATE SET window_started = CASE WHEN login_rate_limits.window_started <= ? THEN excluded.window_started ELSE login_rate_limits.window_started END, attempts = CASE WHEN login_rate_limits.window_started <= ? THEN 1 ELSE login_rate_limits.attempts + 1 END"
  ).bind(bucketKey, now, windowStart, windowStart).run();
  const row = await env.DB.prepare(
    "SELECT attempts FROM login_rate_limits WHERE bucket_key = ?"
  ).bind(bucketKey).first();
  return Number(row?.attempts || 0) <= maxAttempts;
}

async function consumeRecoveryAttempt(env, scope, identifier, maxAttempts = 5) {
  const normalized = String(identifier).toLowerCase().replace(/[\s()+.-]/g, "");
  const bucketKey = await sha256Hex("recovery:" + scope + ":" + normalized);
  const now = Math.floor(Date.now() / 1000);
  const windowStart = now - 15 * 60;
  await env.DB.prepare(
    "INSERT INTO recovery_rate_limits (bucket_key, window_started, attempts) VALUES (?, ?, 1) ON CONFLICT(bucket_key) DO UPDATE SET window_started = CASE WHEN recovery_rate_limits.window_started <= ? THEN excluded.window_started ELSE recovery_rate_limits.window_started END, attempts = CASE WHEN recovery_rate_limits.window_started <= ? THEN 1 ELSE recovery_rate_limits.attempts + 1 END"
  ).bind(bucketKey, now, windowStart, windowStart).run();
  const row = await env.DB.prepare(
    "SELECT attempts FROM recovery_rate_limits WHERE bucket_key = ?"
  ).bind(bucketKey).first();
  return Number(row?.attempts || 0) <= maxAttempts;
}

async function cleanupExpiredMedia(env, now = Date.now()) {
  if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
    throw new Error("Media storage credentials are not configured");
  }
  await env.DB.prepare("CREATE TABLE IF NOT EXISTS media_expirations (object_key TEXT PRIMARY KEY, expires_at TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)").run();
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS media_access (
      object_key TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL,
      recipient_id TEXT,
      group_id TEXT,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      expires_at TEXT NOT NULL
    )
  `).run();
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS status_posts (
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, content TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, expires_at TEXT NOT NULL,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  `).run();
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS status_media (
      id TEXT PRIMARY KEY, status_id TEXT NOT NULL, object_key TEXT NOT NULL UNIQUE,
      file_name TEXT NOT NULL, content_type TEXT NOT NULL,
      size INTEGER NOT NULL, caption TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE
    )
  `).run();
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS status_audio_replies (
      id TEXT PRIMARY KEY, status_id TEXT NOT NULL, user_id TEXT NOT NULL,
      object_key TEXT NOT NULL UNIQUE, content_type TEXT NOT NULL,
      size INTEGER NOT NULL, duration_ms INTEGER NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  `).run();
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS status_views (
      status_id TEXT NOT NULL, viewer_id TEXT NOT NULL,
      viewed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (status_id, viewer_id),
      FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
      FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE CASCADE
    )
  `).run();
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS status_reactions (
      status_id TEXT NOT NULL, user_id TEXT NOT NULL, emoji TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (status_id, user_id, emoji),
      FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE
    )
  `).run();
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS status_replies (
      id TEXT PRIMARY KEY, status_id TEXT NOT NULL, user_id TEXT NOT NULL,
      body TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
      FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    )
  `).run();
  const cutoff = new Date(now).toISOString();
  const expired = await env.DB.prepare(
    "SELECT object_key FROM media_expirations WHERE expires_at <= ? ORDER BY expires_at ASC LIMIT 100"
  ).bind(cutoff).all();
  const bucket = env.TIGRIS_BUCKET || "siraj-media";
  const storage = new AwsClient({
    accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
    secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
    retries: 2
  });
  let deleted = 0;
  for (const item of expired.results || []) {
    const key = String(item.object_key || "");
    if (!key || key.length > 512 || key.startsWith("/") ||
        key.split("/").some(part => !part || part === "." || part === "..")) {
      console.error("Skipping invalid media expiration key");
      continue;
    }
    const objectPath = key.split("/").map(encodeURIComponent).join("/");
    const storageUrl = "https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + objectPath;
    try {
      const response = await storage.fetch(storageUrl, { method: "DELETE" });
      if (response.ok || response.status === 404) {
        await env.DB.prepare("DELETE FROM status_media WHERE object_key = ?").bind(key).run();
        await env.DB.prepare("DELETE FROM status_audio_replies WHERE object_key = ?").bind(key).run();
        await env.DB.prepare("DELETE FROM media_access WHERE object_key = ?").bind(key).run();
        await env.DB.prepare(
          "DELETE FROM media_expirations WHERE object_key = ? AND expires_at <= ?"
        ).bind(key, cutoff).run();
        deleted++;
      } else {
        console.error("Expired media deletion failed:", response.status);
      }
    } catch (error) {
      // Keep this record for retry, but do not let one failed object block the rest.
      console.error("Expired media cleanup item failed:", error);
    }
  }
  await env.DB.prepare(
    "DELETE FROM status_views WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"
  ).bind(cutoff).run();
  await env.DB.prepare(
    "DELETE FROM status_reactions WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"
  ).bind(cutoff).run();
  await env.DB.prepare(
    "DELETE FROM status_replies WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"
  ).bind(cutoff).run();
  await env.DB.prepare(
    "DELETE FROM status_media WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"
  ).bind(cutoff).run();
  await env.DB.prepare(
    "DELETE FROM status_audio_replies WHERE status_id IN (SELECT id FROM status_posts WHERE expires_at <= ?)"
  ).bind(cutoff).run();
  await env.DB.prepare("DELETE FROM status_posts WHERE expires_at <= ?").bind(cutoff).run();
  return { checked: (expired.results || []).length, deleted };
}

async function cleanupExpiredEphemeralMessages(env, now = Date.now()) {
  await env.DB.prepare(`
    CREATE TABLE IF NOT EXISTS ephemeral_messages (
      id TEXT PRIMARY KEY,
      sender_id TEXT NOT NULL,
      receiver_id TEXT NOT NULL,
      body TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      read_at INTEGER,
      delete_at INTEGER
    )
  `).run();
  await env.DB.prepare(
    "CREATE INDEX IF NOT EXISTS idx_ephemeral_expiration ON ephemeral_messages(delete_at)"
  ).run();
  const cutoff = Math.floor(now / 1000);
  const result = await env.DB.prepare(
    "DELETE FROM ephemeral_messages WHERE delete_at IS NOT NULL AND delete_at <= ?"
  ).bind(cutoff).run();
  return { deleted: Number(result?.meta?.changes || 0), cutoff };
}

async function cleanupExpiredRevokedSessions(env, now = Date.now()) {
  const cutoff = Math.floor(now / 1000);
  const result = await env.DB.prepare(
    "DELETE FROM revoked_sessions WHERE expires_at <= ?"
  ).bind(cutoff).run();
  return { deleted: Number(result?.meta?.changes || 0), cutoff };
}

async function cleanupExpiredRateLimits(env, now = Date.now()) {
  const cutoff = Math.floor(now / 1000) - 24 * 60 * 60;
  const results = {};
  for (const table of ["login_rate_limits", "recovery_rate_limits", "transcription_rate_limits"]) {
    try {
      const result = await env.DB.prepare(
        `DELETE FROM ${table} WHERE window_started < ?`
      ).bind(cutoff).run();
      results[table] = Number(result?.meta?.changes || 0);
    } catch (error) {
      // Recovery limits may not exist until the additive recovery migration is applied.
      console.error("Rate limit cleanup failed for " + table + ":", error);
      results[table] = null;
    }
  }
  return results;
}

export { phoneVariants, safeFileName, cleanupExpiredMedia, cleanupExpiredRateLimits, cleanupExpiredEphemeralMessages, cleanupExpiredRevokedSessions };


async function createConversationSummary(env, messages, conversationType) {
  if (!env.AI || typeof env.AI.run !== "function") {
    return json({ error: "Conversation summaries are not configured" }, 503);
  }
  const transcript = prepareConversationSummaryTranscript(messages);
  if (!transcript.length) {
    return json({ error: "لا توجد رسائل نصية كافية لتلخيصها." }, 422);
  }
  try {
    const result = await env.AI.run("@cf/qwen/qwen3.8-27b", {
      messages: buildConversationSummaryMessages(transcript, conversationType),
      max_tokens: 380,
      temperature: 0.2
    });
    const summary = extractConversationSummaryText(result);
    if (!summary) return json({ error: "تعذر إنشاء ملخص واضح. حاول مرة أخرى." }, 502);
    return json({
      summary,
      messageCount: transcript.length,
      generatedAt: new Date().toISOString(),
      scope: "latest_available_messages"
    });
  } catch (error) {
    console.error("Conversation summary inference failed:", error?.name || "Error");
    return json({ error: "تعذر إنشاء ملخص المحادثة حاليًا. حاول مرة أخرى." }, 502);
  }
}

export default {
  async scheduled(_controller, env) {
    try {
      const result = await cleanupExpiredRevokedSessions(env);
      console.log("Revoked session cleanup:", result);
    } catch (error) {
      console.error("Revoked session cleanup failed:", error);
    }
    try {
      const result = await cleanupExpiredRateLimits(env);
      console.log("Rate limit cleanup:", result);
    } catch (error) {
      console.error("Rate limit cleanup failed:", error);
    }
    try {
      const result = await cleanupExpiredMedia(env);
      console.log("Media expiration cleanup:", result);
    } catch (error) {
      console.error("Media expiration cleanup failed:", error);
    }
    try {
      const result = await cleanupExpiredEphemeralMessages(env);
      console.log("Ephemeral message cleanup:", result);
    } catch (error) {
      console.error("Ephemeral message cleanup failed:", error);
    }
  },
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";
    const method = request.method;

    try {
      // Liveness is intentionally independent of D1 and secrets so platform
      // probes can distinguish a running Worker from a ready API instance.
      if (method === "GET" && path === "/health/live") {
        return json({ status: "alive", service: "barq-api" });
      }

      // Readiness performs a read-only D1 probe. It never creates tables,
      // applies migrations, or mutates production data.
      if (method === "GET" && path === "/health/ready") {
        if (!env.DB || !env.JWT_SECRET) {
          return json({ status: "not_ready" }, 503);
        }
        try {
          const probe = await env.DB.prepare("SELECT 1 AS ok").first();
          if (Number(probe?.ok) !== 1) {
            return json({ status: "not_ready" }, 503);
          }
        } catch { 
          console.error("Readiness database probe failed");
          return json({ status: "not_ready" }, 503);
        }
        return json({ status: "ready", service: "barq-api" });
      }

      if (!env.DB || !env.JWT_SECRET) {
        return json(
          { error: "Server configuration is incomplete" },
          500
        );
      }

      // API status
      if (method === "GET" && path === "/") {
        return json({ name: "Siraj API", status: "ready" });
      }

      // Register
      if (method === "POST" && path === "/api/register") {
        const body = await readJsonRequestLimited(request);

        const displayName = String(body.displayName || "").trim();
        let username = String(body.username || "").trim().toLowerCase();
        const password = String(body.password || "");
        const phone = String(body.phone || "").trim();
        const inviteCode = String(body.inviteCode || "").trim().toUpperCase();

        if (inviteCode && !/^[A-F0-9]{12}$/.test(inviteCode)) {
          return json({ error: "Invalid invite code" }, 400);
        }
        let inviterUserId = null;
        if (inviteCode) {
          await env.DB.prepare(`
            CREATE TABLE IF NOT EXISTS user_invite_codes (
              user_id TEXT PRIMARY KEY,
              invite_code TEXT NOT NULL UNIQUE,
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
            )
          `).run();
          const inviter = await env.DB.prepare(
            "SELECT user_id FROM user_invite_codes WHERE invite_code = ?"
          ).bind(inviteCode).first();
          if (!inviter?.user_id) {
            return json({ error: "Invite code was not found" }, 400);
          }
          inviterUserId = String(inviter.user_id);
          await env.DB.prepare(`
            CREATE TABLE IF NOT EXISTS user_invites (
              invitee_user_id TEXT PRIMARY KEY,
              inviter_user_id TEXT NOT NULL,
              created_at INTEGER NOT NULL DEFAULT (unixepoch()),
              FOREIGN KEY (invitee_user_id) REFERENCES users(id) ON DELETE CASCADE,
              FOREIGN KEY (inviter_user_id) REFERENCES users(id) ON DELETE CASCADE
            )
          `).run();
        }

        if (!displayName || !phone || !password) {
          return json({
            error: "Display name, international phone number and password are required"
          }, 400);
        }

        if (username && !/^[a-zA-Z0-9_.]{3,30}$/.test(username)) {
          return json({
            error: "Username must be 3-30 characters: letters, numbers, _ or ."
          }, 400);
        }

        if (password.length < 8 || password.length > 128) {
          return json({
            error: "Password must be 8-128 characters"
          }, 400);
        }

        // Registration uses an international E.164 phone as the primary account
        // identifier. National/local formatting must be normalized by the client
        // using the selected country code before reaching this endpoint.
        if (!/^\+[1-9][0-9]{7,14}$/.test(phone)) {
          return json({ error: "Enter a valid international phone number including its country code" }, 400);
        }
        if (await phoneAlreadyInUse(env, phone)) {
          return json({ error: "Phone number is already registered" }, 409);
        }
        // Limit automated account creation before the expensive password hash.
        const registrationIp = request.headers.get("CF-Connecting-IP") || "unknown";
        if (!(await consumeLoginAttempt(env, "register-client", registrationIp, 20))) {
          return new Response(JSON.stringify({
            error: "Too many registration attempts. Please try again in 15 minutes."
          }), {
            status: 429,
            headers: { ...corsHeaders, "Retry-After": "900" }
          });
        }

        // Usernames are optional and secondary. Generate a private handle when
        // the user chooses not to create one; phone remains the login identifier.
        if (!username) username = "barq" + randomHex(6).toLowerCase();

        const id = crypto.randomUUID();
        const salt = base64url(
          crypto.getRandomValues(new Uint8Array(16))
        );

        const passwordHash = await hashPassword(password, salt);

        const recovery = await generateRecoveryCode();
        const createdAt = Math.floor(Date.now() / 1000);
        const registrationStatements = [
          (() => {
            const phoneConflict = phone ? phoneConflictCondition("phone", phone) : { sql: "0", bindings: [] };
            return env.DB.prepare(`INSERT INTO users
              (id, username, display_name, password_hash, password_salt, phone)
              SELECT ?, ?, ?, ?, ?, ?
              WHERE NOT EXISTS (
                SELECT 1 FROM users WHERE ${phoneConflict.sql}
              )`).bind(id, username, displayName, passwordHash, salt, phone || null,
                ...phoneConflict.bindings);
          })(),
          env.DB.prepare(`INSERT INTO recovery_codes
            (user_id, code_hash, code_salt, expires_at, consumed_at, created_at)
            SELECT ?, ?, ?, ?, NULL, ?
            WHERE EXISTS (SELECT 1 FROM users WHERE id = ?)`)
            .bind(id, recovery.codeHash, recovery.salt, createdAt + RECOVERY_CODE_TTL_SECONDS, createdAt, id)
        ];
        if (inviterUserId) {
          registrationStatements.push(env.DB.prepare(`
            INSERT INTO user_invites (invitee_user_id, inviter_user_id)
            SELECT ?, ?
            WHERE EXISTS (SELECT 1 FROM users WHERE id = ?)
              AND EXISTS (SELECT 1 FROM users WHERE id = ?)
          `).bind(id, inviterUserId, id, inviterUserId));
        }
        const registrationResults = await env.DB.batch(registrationStatements);
        if (inviterUserId && Number(registrationResults?.[2]?.meta?.changes || 0) !== 1) {
          throw new Error("Invite attribution could not be saved");
        }
        if (Number(registrationResults?.[0]?.meta?.changes || 0) !== 1) {
          return json({ error: phone ? "Phone number is already registered" : "Unable to create account" }, 409);
        }

        const user = {
          id,
          username,
          display_name: displayName,
          phone
        };

        const recoveryCode = recovery.code;
        const sessionVersion = await getSessionVersion(env, id);
        const token = await signToken(user, env.JWT_SECRET, sessionVersion);

        return json({
          user: cleanUser(user),
          token,
          recoveryCode
        }, 201);
      }


      // Recover an account with its one-time recovery code (no SMS/email dependency).
      if (method === "POST" && path === "/api/password/recover") {
        const body = await readJsonRequestLimited(request);
        const identifier = String(body.identifier || body.username || body.phone || "").trim();
        const recoveryCode = String(body.recoveryCode || "").replace(/[\s-]/g, "").toUpperCase();
        const newPassword = String(body.newPassword || "");
        if (!identifier || !/^[A-F0-9]{40}$/.test(recoveryCode)) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }
        if (newPassword.length < 8 || newPassword.length > 128) {
          return json({ error: "كلمة المرور يجب أن تكون بين 8 و128 حرفًا" }, 400);
        }
        const clientIp = request.headers.get("CF-Connecting-IP") || "unknown";
        const [identifierAllowed, clientAllowed] = await Promise.all([
          consumeRecoveryAttempt(env, "identifier", identifier, 5),
          consumeRecoveryAttempt(env, "client", clientIp, 20)
        ]);
        if (!identifierAllowed || !clientAllowed) {
          return json({ error: "محاولات كثيرة. انتظر 15 دقيقة ثم حاول مجددًا." }, 429);
        }

        const variants = phoneVariants(identifier);
        const suffixes = [...new Set(variants.filter(value => value.length >= 9).map(value => value.slice(-9)))];
        const normalizedPhone = normalizedPhoneSql("phone");
        const phoneClauses = [];
        const bindings = [identifier.toLowerCase(), identifier];
        if (variants.length) {
          phoneClauses.push(`${normalizedPhone} IN (${variants.map(() => "?").join(", ")})`);
          bindings.push(...variants);
        }
        if (suffixes.length) {
          phoneClauses.push(`substr(${normalizedPhone}, -9) IN (${suffixes.map(() => "?").join(", ")})`);
          bindings.push(...suffixes);
        }
        const phoneLookup = phoneClauses.length ? " OR " + phoneClauses.join(" OR ") : "";
        const user = await env.DB.prepare(
          `SELECT id FROM users WHERE username = ? OR phone = ?${phoneLookup} LIMIT 1`
        ).bind(...bindings).first();
        if (!user) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }

        if (!(await consumeRecoveryAttempt(env, "account", user.id))) {
          return json({ error: "محاولات كثيرة. انتظر 15 دقيقة ثم حاول مجددًا." }, 429);
        }
        const stored = await env.DB.prepare(
          "SELECT code_hash, code_salt, consumed_at, expires_at FROM recovery_codes WHERE user_id = ?"
        ).bind(user.id).first();
        if (!stored || (stored.consumed_at !== null && stored.consumed_at !== undefined)) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }

        const suppliedHash = await sha256Hex(stored.code_salt + ":" + recoveryCode);
        const now = Math.floor(Date.now() / 1000);
        if (!constantTimeHexEqual(suppliedHash, stored.code_hash) ||
            stored.expires_at === null || stored.expires_at === undefined ||
            Number(stored.expires_at) <= now) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }

        const newSalt = base64url(crypto.getRandomValues(new Uint8Array(16)));
        const newHash = await hashPassword(newPassword, newSalt);
        await ensureAccountSecurity(env);
        await env.DB.prepare(
          "INSERT OR IGNORE INTO account_security (user_id, session_version) VALUES (?, 0)"
        ).bind(user.id).run();

        const results = await env.DB.batch([
          env.DB.prepare(
            "UPDATE users SET password_hash = ?, password_salt = ? WHERE id = ? AND EXISTS (SELECT 1 FROM recovery_codes WHERE user_id = ? AND code_hash = ? AND consumed_at IS NULL AND expires_at > ?)"
          ).bind(newHash, newSalt, user.id, user.id, stored.code_hash, now),
          env.DB.prepare(
            "UPDATE recovery_codes SET consumed_at = ? WHERE user_id = ? AND code_hash = ? AND consumed_at IS NULL AND expires_at > ?"
          ).bind(now, user.id, stored.code_hash, now),
          env.DB.prepare(
            "UPDATE account_security SET session_version = session_version + 1, updated_at = CURRENT_TIMESTAMP WHERE user_id = ? AND EXISTS (SELECT 1 FROM recovery_codes WHERE user_id = ? AND code_hash = ? AND consumed_at = ?)"
          ).bind(user.id, user.id, stored.code_hash, now)
        ]);
        if (Number(results?.[0]?.meta?.changes || 0) !== 1 ||
            Number(results?.[1]?.meta?.changes || 0) !== 1 ||
            Number(results?.[2]?.meta?.changes || 0) !== 1) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }
        return json({ message: "تم تحديث كلمة المرور وإبطال الجلسات السابقة. سجّل الدخول من جديد." });
      }

      // Login
      if (method === "POST" && path === "/api/login") {
        const body = await readJsonRequestLimited(request);

        const username = String(body.username || "").trim().toLowerCase();
        const password = String(body.password || "");

        // Apply independent per-identifier and per-client limits. The identifier
        // bucket prevents IP rotation from bypassing protection; the IP bucket
        // limits bursts across many account names from one client.
        const clientIp = request.headers.get("CF-Connecting-IP") || "unknown";
        // Canonicalize phone identifiers so local, international, and formatted
        // versions of the same number share one account-level rate-limit bucket.
        const phoneIdentifierVariants = phoneVariants(username);
        const rateLimitIdentifier = phoneIdentifierVariants.length
          ? phoneIdentifierVariants.sort((a, b) => a.length - b.length)[0]
          : username;
        const [identifierAllowed, clientAllowed] = await Promise.all([
          consumeLoginAttempt(env, "identifier", rateLimitIdentifier),
          consumeLoginAttempt(env, "client", clientIp)
        ]);
        if (!identifierAllowed || !clientAllowed) {
          return new Response(JSON.stringify({
            error: "Too many login attempts. Please try again in 15 minutes."
          }), {
            status: 429,
            headers: { ...corsHeaders, "Retry-After": "900" }
          });
        }

        // Match phone identifiers across Yemen local/international formats,
        // while retaining exact username lookup.
        const phoneConflict = phoneConflictCondition("phone", username);
        const user = await env.DB.prepare(
          `SELECT * FROM users
           WHERE username = ? OR phone = ? OR ${phoneConflict.sql}
           LIMIT 1`
        ).bind(username, username, ...phoneConflict.bindings).first();

        if (
          !user ||
          await hashPassword(password, user.password_salt) !== user.password_hash
        ) {
          return json({
            error: "Incorrect username or password"
          }, 401);
        }

        const sessionVersion = await getSessionVersion(env, user.id);
        const token = await signToken(user, env.JWT_SECRET, sessionVersion);

        return json({
          user: cleanUser(user),
          token
        });
      }

      // Authentication required below this point
      const currentUser = await authenticate(request, env);

      if (!currentUser) {
        return json({ error: "Unauthorized" }, 401);
      }

      // Revoke only this bearer token; other device sessions remain valid.
      if (method === "POST" && path === "/api/logout") {
        const authHeader = request.headers.get("Authorization") || "";
        const bearerToken = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
        if (!bearerToken) return json({ error: "Unauthorized" }, 401);
        await ensureAccountSecurity(env);
        await env.DB.prepare(
          "INSERT OR IGNORE INTO revoked_sessions (token_hash, user_id, expires_at) VALUES (?, ?, ?)"
        ).bind(await sha256Hex(bearerToken), currentUser.sub, currentUser.exp).run();
        return json({ message: "تم تسجيل الخروج من هذا الجهاز." });
      }

      // Explicitly requested speech transcription. Audio and transcript are never persisted.
      if (method === "POST" && path === "/api/transcribe") {
        if (!env.AI || typeof env.AI.run !== "function") {
          return json({ error: "Speech transcription is not configured" }, 503);
        }
        const contentType = (request.headers.get("Content-Type") || "").split(";")[0].trim().toLowerCase();
        const allowedAudioTypes = new Set(["audio/mpeg", "audio/mp4", "audio/aac", "audio/wav", "audio/ogg", "audio/webm", "audio/x-wav", "audio/3gpp", "audio/amr"]);
        if (!allowedAudioTypes.has(contentType)) {
          return json({ error: "Unsupported audio format" }, 415);
        }
        const declaredLength = Number(request.headers.get("Content-Length"));
        const maxTranscriptionBytes = 2 * 1024 * 1024;
        if (Number.isFinite(declaredLength) && declaredLength > maxTranscriptionBytes) {
          return json({ error: "Audio must not exceed 2 MB for transcription" }, 413);
        }
        const audio = await readRequestBodyLimited(request, maxTranscriptionBytes);
        if (!audio) {
          return json({ error: "Audio must not exceed 2 MB for transcription" }, 413);
        }
        if (!audio.byteLength) {
          return json({ error: "Audio must be between 1 byte and 2 MB" }, 413);
        }

        // Limit each account to 10 inference requests per rolling hour to prevent abuse.
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS transcription_rate_limits (
            user_id TEXT PRIMARY KEY,
            window_started INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0
          )
        `).run();
        const now = Math.floor(Date.now() / 1000);
        const windowStart = now - 3600;
        await env.DB.prepare(
          `INSERT INTO transcription_rate_limits (user_id, window_started, attempts)
           VALUES (?, ?, 1)
           ON CONFLICT(user_id) DO UPDATE SET
             window_started = CASE WHEN transcription_rate_limits.window_started <= ? THEN excluded.window_started ELSE transcription_rate_limits.window_started END,
             attempts = CASE WHEN transcription_rate_limits.window_started <= ? THEN 1 ELSE transcription_rate_limits.attempts + 1 END`
        ).bind(currentUser.sub, now, windowStart, windowStart).run();
        const usage = await env.DB.prepare(
          "SELECT attempts FROM transcription_rate_limits WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        if (Number(usage?.attempts || 0) > 10) {
          return json({ error: "Transcription limit reached. Try again later." }, 429);
        }

        try {
          const result = await env.AI.run("@cf/openai/whisper", {
            audio: Array.from(new Uint8Array(audio))
          });
          const text = String(result?.text || "").trim();
          if (!text) return json({ error: "No clear speech was detected" }, 422);
          return json({ text });
        } catch (error) {
          console.error("Speech transcription inference failed:", error?.name || "Error");
          return json({ error: "Speech transcription failed. Please try again." }, 502);
        }
      }

      // A single private invite code per account; no counters, badges, thresholds, or rewards.
      if (method === "GET" && path === "/api/referrals") {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS user_invite_codes (
            user_id TEXT PRIMARY KEY,
            invite_code TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        const existing = await env.DB.prepare(
          "SELECT invite_code FROM user_invite_codes WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        if (existing?.invite_code) return json({ inviteCode: existing.invite_code });

        const inviteCode = Array.from(crypto.getRandomValues(new Uint8Array(6)), byte => byte.toString(16).padStart(2, "0")).join("").toUpperCase();
        await env.DB.prepare(
          "INSERT OR IGNORE INTO user_invite_codes (user_id, invite_code) VALUES (?, ?)"
        ).bind(currentUser.sub, inviteCode).run();
        const saved = await env.DB.prepare(
          "SELECT invite_code FROM user_invite_codes WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        if (!saved?.invite_code) return json({ error: "Could not create invite code" }, 503);
        return json({ inviteCode: saved.invite_code });
      }

      // Ephemeral private messages are stored only in D1 (never sent to Firebase).
      // The ten-second deletion window starts when the recipient first fetches the message.
      if (path === "/api/ephemeral-messages" && (method === "GET" || method === "POST")) {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS ephemeral_messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            receiver_id TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at INTEGER NOT NULL DEFAULT (unixepoch()),
            read_at INTEGER,
            delete_at INTEGER,
            FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare(
          "CREATE INDEX IF NOT EXISTS idx_ephemeral_conversation ON ephemeral_messages(sender_id, receiver_id, created_at)"
        ).run();
        await env.DB.prepare(
          "CREATE INDEX IF NOT EXISTS idx_ephemeral_expiration ON ephemeral_messages(delete_at)"
        ).run();
        await env.DB.prepare(
          "DELETE FROM ephemeral_messages WHERE delete_at IS NOT NULL AND delete_at <= unixepoch()"
        ).run();

        if (method === "POST") {
          const body = await readJsonRequestLimited(request);
          const receiverId = String(body.receiverId || "").trim();
          const message = String(body.body || "").trim();
          if (!receiverId || !message) {
            return json({ error: "Receiver and message are required" }, 400);
          }
          if (receiverId === currentUser.sub) {
            return json({ error: "Cannot message yourself" }, 400);
          }
          if (message.length > 5000) {
            return json({ error: "Message is too long" }, 400);
          }
          const friendship = await env.DB.prepare(
            "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
          ).bind(currentUser.sub, receiverId).first();
          if (!friendship) return json({ error: "You can only message friends" }, 403);

          const id = crypto.randomUUID();
          await env.DB.prepare(
            "INSERT INTO ephemeral_messages (id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)"
          ).bind(id, currentUser.sub, receiverId, message).run();
          // Deliberately no push notification: ephemeral content must not be copied to Firebase.
          return json({ message: "Ephemeral message sent", id }, 201);
        }

        const friendId = (url.searchParams.get("with") || "").trim();
        if (!friendId) return json({ error: "Friend ID is required" }, 400);
        const friendship = await env.DB.prepare(
          "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
        ).bind(currentUser.sub, friendId).first();
        if (!friendship) return json({ error: "You can only view chats with friends" }, 403);

        // First retrieval by the recipient is the read event; start the ten-second TTL once.
        await env.DB.prepare(
          `UPDATE ephemeral_messages
           SET read_at = unixepoch(), delete_at = unixepoch() + 10
           WHERE sender_id = ? AND receiver_id = ? AND read_at IS NULL`
        ).bind(friendId, currentUser.sub).run();

        const result = await env.DB.prepare(
          `SELECT id, sender_id, receiver_id, body, created_at, read_at, delete_at
           FROM ephemeral_messages
           WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
             AND (delete_at IS NULL OR delete_at > unixepoch())
           ORDER BY created_at ASC, id ASC
           LIMIT 200`
        ).bind(currentUser.sub, friendId, friendId, currentUser.sub).all();
        const messages = result.results || [];
        // Schedule physical D1 deletion for ten seconds after the recipient's first read.
        // Cron cleanup remains a recovery path if the request's background task is interrupted.
        if (ctx && typeof ctx.waitUntil === "function") {
          for (const message of messages) {
            const deleteAt = Number(message.delete_at || 0);
            if (!message.id || !Number.isFinite(deleteAt) || deleteAt <= 0) continue;
            const delay = Math.max(0, deleteAt * 1000 - Date.now());
            ctx.waitUntil(
              new Promise(resolve => setTimeout(resolve, delay))
                .then(() => env.DB.prepare(
                  "DELETE FROM ephemeral_messages WHERE id = ? AND delete_at IS NOT NULL AND delete_at <= unixepoch()"
                ).bind(message.id).run())
                .catch(error => console.error("Ephemeral message deletion task failed:", error?.name || "Error"))
            );
          }
        }
        return json({ messages });
      }

      // Rotate the one-time recovery code after verifying the current password.
      if (method === "POST" && path === "/api/recovery-code") {
        const body = await readJsonRequestLimited(request);
        const password = String(body.password || "");
        const user = await env.DB.prepare(
          "SELECT password_hash, password_salt FROM users WHERE id = ?"
        ).bind(currentUser.sub).first();
        if (!user || !password || await hashPassword(password, user.password_salt) !== user.password_hash) {
          return json({ error: "كلمة المرور الحالية غير صحيحة" }, 401);
        }
        const recovery = await generateRecoveryCode();
        await saveRecoveryCode(env, currentUser.sub, recovery);
        return json({
          recoveryCode: recovery.code,
          message: "احفظ رمز الاسترداد في مكان آمن؛ لن يظهر مرة أخرى."
        });
      }

      // Private profile photos use their own namespace and never enter chat-media expiry.
      const profilePhotoPrefix = "/api/profile/photo/";
      if (path.startsWith(profilePhotoPrefix) && (method === "GET" || method === "POST")) {
        if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
          return json({ error: "Profile photo storage is not configured" }, 503);
        }
        let targetUserId;
        try {
          targetUserId = decodeURIComponent(path.slice(profilePhotoPrefix.length));
          if (targetUserId === "me") targetUserId = currentUser.sub;
        } catch (_) {
          return json({ error: "Invalid profile identifier" }, 400);
        }
        if (!targetUserId || targetUserId.length > 128) {
          return json({ error: "Invalid profile identifier" }, 400);
        }
        await ensureProfilePhotos(env);

        if (method === "POST") {
          if (targetUserId !== currentUser.sub) return json({ error: "You can only update your own photo" }, 403);
          const contentType = (request.headers.get("Content-Type") || "").split(";")[0].trim().toLowerCase();
          if (!["image/jpeg", "image/png", "image/webp"].includes(contentType)) {
            return json({ error: "Use a JPEG, PNG, or WebP image" }, 415);
          }
          const declaredLength = Number(request.headers.get("Content-Length"));
          const maxPhotoBytes = 4 * 1024 * 1024;
          if (Number.isFinite(declaredLength) && declaredLength > maxPhotoBytes) {
            return json({ error: "Profile photo must not exceed 4 MiB" }, 413);
          }
          const bytes = await readRequestBodyLimited(request, maxPhotoBytes);
          if (!bytes || !bytes.length) {
            return json({ error: "Profile photo must be between 1 byte and 4 MiB" }, 413);
          }
          if (detectProfileImageType(bytes) !== contentType) {
            return json({ error: "Image content does not match its declared type" }, 415);
          }
          const previous = await env.DB.prepare(
            "SELECT object_key FROM profile_photos WHERE user_id = ?"
          ).bind(currentUser.sub).first();
          const objectKey = "profiles/" + currentUser.sub + "/" + crypto.randomUUID();
          const bucket = env.TIGRIS_BUCKET || "siraj-media";
          const objectPath = objectKey.split("/").map(encodeURIComponent).join("/");
          const storageUrl = "https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + objectPath;
          const storage = new AwsClient({
            accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
            secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
            service: "s3",
            region: "auto",
            retries: 2
          });
          const putResponse = await storage.fetch(storageUrl, {
            method: "PUT",
            headers: {
              "Content-Type": contentType,
              "x-amz-meta-ownerid": currentUser.sub,
              "x-amz-meta-contenttype": contentType
            },
            body: bytes
          });
          if (!putResponse.ok) {
            return json({ error: "Profile photo upload failed", storageStatus: putResponse.status }, 502);
          }
          try {
            await env.DB.prepare(`
              INSERT INTO profile_photos (user_id, object_key, content_type, updated_at)
              VALUES (?, ?, ?, CURRENT_TIMESTAMP)
              ON CONFLICT(user_id) DO UPDATE SET
                object_key = excluded.object_key,
                content_type = excluded.content_type,
                updated_at = CURRENT_TIMESTAMP
            `).bind(currentUser.sub, objectKey, contentType).run();
          } catch (error) {
            let objectRemoved = false;
            try {
              const deletion = await storage.fetch(storageUrl, { method: "DELETE" });
              objectRemoved = deletion.ok || deletion.status === 404;
            } catch (cleanupError) {
              console.error("SPARK audio rollback delete failed:", cleanupError);
            }
            // If Tigris cannot delete the orphan immediately, preserve a retry
            // record so the scheduled cleanup can remove it after status expiry.
            if (!objectRemoved) {
              try {
                await env.DB.prepare(
                  "INSERT OR IGNORE INTO media_expirations (object_key, expires_at) VALUES (?, ?)"
                ).bind(objectKey, expiresAt).run();
              } catch (cleanupError) {
                console.error("SPARK audio rollback retry record failed:", cleanupError);
              }
            }
            throw error;
          }
          if (previous?.object_key && previous.object_key !== objectKey) {
            const oldPath = String(previous.object_key).split("/").map(encodeURIComponent).join("/");
            try {
              await storage.fetch("https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + oldPath, { method: "DELETE" });
            } catch (error) {
              console.error("Previous profile photo cleanup failed:", error?.name || "Error");
            }
          }
          const saved = await env.DB.prepare(
            "SELECT updated_at FROM profile_photos WHERE user_id = ?"
          ).bind(currentUser.sub).first();
          return json({
            photoUrl: "/api/profile/photo/" + encodeURIComponent(currentUser.sub),
            updatedAt: saved?.updated_at || null
          }, 201);
        }

        if (targetUserId !== currentUser.sub) {
          const friendship = await env.DB.prepare(
            `SELECT 1 FROM friendships
             WHERE (user_id = ? AND friend_id = ?)
                OR (user_id = ? AND friend_id = ?)
             LIMIT 1`
          ).bind(currentUser.sub, targetUserId, targetUserId, currentUser.sub).first();
          if (!friendship) {
            const sharedGroup = await env.DB.prepare(
              `SELECT 1
               FROM group_members mine
               JOIN group_members theirs ON theirs.group_id = mine.group_id
               WHERE mine.user_id = ? AND theirs.user_id = ?
               LIMIT 1`
            ).bind(currentUser.sub, targetUserId).first();
            if (!sharedGroup) {
              // A discoverable public profile may be opened from search or matched
              // phone contacts without a friendship or shared group. Keep private
              // profiles protected by the same searchable preference as discovery.
              await env.DB.prepare(`
                CREATE TABLE IF NOT EXISTS user_privacy (
                  user_id TEXT PRIMARY KEY,
                  searchable INTEGER NOT NULL DEFAULT 1,
                  read_receipts INTEGER NOT NULL DEFAULT 1,
                  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
                )
              `).run();
              const privacy = await env.DB.prepare(
                "SELECT searchable FROM user_privacy WHERE user_id = ?"
              ).bind(targetUserId).first();
              if (Number(privacy?.searchable ?? 1) !== 1) {
                return json({ error: "Profile photo access denied" }, 403);
              }
            }
          }
        }
        const photo = await env.DB.prepare(
          "SELECT object_key, content_type, updated_at FROM profile_photos WHERE user_id = ?"
        ).bind(targetUserId).first();
        if (!photo?.object_key) return json({ error: "Profile photo not found" }, 404);
        const objectPath = String(photo.object_key).split("/").map(encodeURIComponent).join("/");
        const storageUrl = "https://" + encodeURIComponent(env.TIGRIS_BUCKET || "siraj-media") + ".t3.storage.dev/" + objectPath;
        const storage = new AwsClient({
          accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
          secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
          service: "s3",
          region: "auto",
          retries: 2
        });
        const stored = await storage.fetch(storageUrl, { method: "GET" });
        if (stored.status === 404) return json({ error: "Profile photo not found" }, 404);
        if (!stored.ok) return json({ error: "Profile photo could not be loaded" }, 502);
        return new Response(await stored.arrayBuffer(), {
          status: 200,
          headers: {
            ...corsHeaders,
            "Content-Type": photo.content_type,
            "Cache-Control": "private, max-age=300",
            "Vary": "Authorization",
            "X-Content-Type-Options": "nosniff"
          }
        });
      }

      // Update current user's editable profile fields
      if (method === "POST" && path === "/api/profile") {
        await ensureProfilePhotos(env);
        const body = await readJsonRequestLimited(request);
        const displayName = String(body.displayName || "").trim();
        const phone = String(body.phone || "").trim();
        if (!displayName || displayName.length > 60) {
          return json({ error: "Display name must be 1-60 characters" }, 400);
        }
        if (!/^\+[1-9][0-9]{7,14}$/.test(phone)) {
          return json({ error: "Enter a valid international phone number including its country code" }, 400);
        }
        if (await phoneAlreadyInUse(env, phone, currentUser.sub)) {
          return json({ error: "Phone number is already in use" }, 409);
        }
        const phoneConflict = phone ? phoneConflictCondition("phone", phone) : { sql: "0", bindings: [] };
        const updateResult = await env.DB.prepare(
          `UPDATE users SET display_name = ?, phone = ?
           WHERE id = ? AND NOT EXISTS (
             SELECT 1 FROM users
             WHERE id != ? AND ${phoneConflict.sql}
           )`
        ).bind(displayName, phone || null, currentUser.sub, currentUser.sub,
          ...phoneConflict.bindings).run();
        const user = await env.DB.prepare(
          `SELECT u.id, u.username, u.display_name, u.phone,
                  p.updated_at AS photo_updated_at
           FROM users u LEFT JOIN profile_photos p ON p.user_id = u.id
           WHERE u.id = ?`
        ).bind(currentUser.sub).first();
        if (!user) return json({ error: "User not found" }, 404);
        if (Number(updateResult?.meta?.changes || 0) !== 1) {
          return json({ error: "Phone number is already in use" }, 409);
        }
        return json({ user: cleanUser(user), message: "Profile updated" });
      }

      // Privacy settings for the authenticated account
      if ((method === "GET" || method === "POST") && path === "/api/privacy") {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS user_privacy (
            user_id TEXT PRIMARY KEY,
            searchable INTEGER NOT NULL DEFAULT 1,
            read_receipts INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        if (method === "POST") {
          const body = await readJsonRequestLimited(request);
          const existing = await env.DB.prepare(
            "SELECT searchable, read_receipts FROM user_privacy WHERE user_id = ?"
          ).bind(currentUser.sub).first();
          // Partial updates must never silently turn a disabled privacy option back on.
          const searchable = typeof body.searchable === "boolean"
            ? Number(body.searchable) : Number(existing?.searchable ?? 1);
          const readReceipts = typeof body.readReceipts === "boolean"
            ? Number(body.readReceipts) : Number(existing?.read_receipts ?? 1);
          await env.DB.prepare(`
            INSERT INTO user_privacy (user_id, searchable, read_receipts)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
              searchable = excluded.searchable,
              read_receipts = excluded.read_receipts,
              updated_at = CURRENT_TIMESTAMP
          `).bind(currentUser.sub, searchable, readReceipts).run();
        }
        const settings = await env.DB.prepare(
          "SELECT searchable, read_receipts FROM user_privacy WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        return json({
          privacy: {
            searchable: settings ? settings.searchable === 1 : true,
            readReceipts: settings ? settings.read_receipts === 1 : true
          }
        });
      }

      // Per-account notification preferences (delivery is handled by the push service).
      if ((method === "GET" || method === "POST") && path === "/api/notification-settings") {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS notification_preferences (
            user_id TEXT PRIMARY KEY,
            messages INTEGER NOT NULL DEFAULT 1,
            groups INTEGER NOT NULL DEFAULT 1,
            statuses INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        if (method === "POST") {
          const body = await readJsonRequestLimited(request);
          const existing = await env.DB.prepare(
            "SELECT messages, groups, statuses FROM notification_preferences WHERE user_id = ?"
          ).bind(currentUser.sub).first();
          const messages = typeof body.messages === "boolean"
            ? Number(body.messages) : Number(existing?.messages ?? 1);
          const groups = typeof body.groups === "boolean"
            ? Number(body.groups) : Number(existing?.groups ?? 1);
          const statuses = typeof body.statuses === "boolean"
            ? Number(body.statuses) : Number(existing?.statuses ?? 1);
          await env.DB.prepare(`
            INSERT INTO notification_preferences (user_id, messages, groups, statuses)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
              messages = excluded.messages,
              groups = excluded.groups,
              statuses = excluded.statuses,
              updated_at = CURRENT_TIMESTAMP
          `).bind(currentUser.sub, messages, groups, statuses).run();
        }
        const settings = await env.DB.prepare(
          "SELECT messages, groups, statuses FROM notification_preferences WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        return json({ settings: {
          messages: settings ? settings.messages === 1 : true,
          groups: settings ? settings.groups === 1 : true,
          statuses: settings ? settings.statuses === 1 : true
        }});
      }

      // Register or revoke this account's Firebase device token.
      if ((method === "POST" || method === "DELETE") && path === "/api/devices/token") {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS device_tokens (
            user_id TEXT NOT NULL,
            fcm_token TEXT PRIMARY KEY,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        const body = await readJsonRequestLimited(request);
        const fcmToken = String(body.fcmToken || "").trim();

        if (!fcmToken || fcmToken.length > 4096) {
          return json({ error: "Invalid device token" }, 400);
        }

        if (method === "DELETE") {
          const result = await env.DB.prepare(
            "DELETE FROM device_tokens WHERE user_id = ? AND fcm_token = ?"
          ).bind(currentUser.sub, fcmToken).run();
          return json({ message: "Device token unregistered", removed: Number(result?.meta?.changes || 0) });
        }

        await env.DB.prepare(
          `INSERT INTO device_tokens
           (user_id, fcm_token, updated_at)
           VALUES (?, ?, CURRENT_TIMESTAMP)
           ON CONFLICT(fcm_token)
           DO UPDATE SET
             user_id = excluded.user_id,
             updated_at = CURRENT_TIMESTAMP`
        ).bind(currentUser.sub, fcmToken).run();

        return json({ message: "Device token registered" });
      }
      // Current user
      if (method === "GET" && path === "/api/me") {
        await ensureProfilePhotos(env);
        const user = await env.DB.prepare(
          `SELECT u.id, u.username, u.display_name, u.phone,
                  p.updated_at AS photo_updated_at
           FROM users u
           LEFT JOIN profile_photos p ON p.user_id = u.id
           WHERE u.id = ?`
        ).bind(currentUser.sub).first();

        if (!user) {
          return json({ error: "User not found" }, 404);
        }

        return json({ user: cleanUser(user) });
      }

      // Publish a 24-hour SPARK image/video status using private Tigris storage.
      if (method === "POST" && path === "/api/statuses/media") {
        if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
          return json({ error: "Media storage credentials are not configured" }, 503);
        }
        const statusAllowed = await consumeLoginAttempt(env, "status", currentUser.sub, 10);
        if (!statusAllowed) {
          return new Response(JSON.stringify({ error: "Too many status posts. Please try again in 15 minutes." }), {
            status: 429, headers: { ...corsHeaders, "Retry-After": "900" }
          });
        }
        const contentType = (request.headers.get("Content-Type") || "").split(";")[0].toLowerCase();
        if (!/^(image\/(jpeg|png|webp|gif)|video\/(mp4|webm|quicktime))$/.test(contentType)) {
          return json({ error: "SPARK supports image and video media only" }, 415);
        }
        const declaredLength = Number(request.headers.get("Content-Length"));
        const maxStatusMediaBytes = 60 * 1024 * 1024;
        if (Number.isFinite(declaredLength) && declaredLength > maxStatusMediaBytes) {
          return json({ error: "SPARK media must not exceed 60 MB" }, 413);
        }
        const bytes = await readRequestBodyLimited(request, maxStatusMediaBytes);
        if (!bytes?.byteLength) return json({ error: "SPARK media is empty or too large" }, 413);
        // Never trust a client-supplied MIME type: validate the actual file signature
        // before storing it or serving it back to other accounts.
        if (detectSparkMediaType(bytes) !== contentType) {
          return json({ error: "SPARK file content does not match its declared media type" }, 415);
        }
        const caption = String(request.headers.get("X-Status-Caption") || "").trim();
        if (caption.length > 1000) return json({ error: "SPARK caption must not exceed 1000 characters" }, 400);

        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_posts (
            id TEXT PRIMARY KEY, user_id TEXT NOT NULL, content TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, expires_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_views (
            status_id TEXT NOT NULL, viewer_id TEXT NOT NULL,
            viewed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (status_id, viewer_id),
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
            FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_media (
            id TEXT PRIMARY KEY, status_id TEXT NOT NULL, object_key TEXT NOT NULL UNIQUE,
            file_name TEXT NOT NULL, content_type TEXT NOT NULL,
            size INTEGER NOT NULL, caption TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare("CREATE TABLE IF NOT EXISTS media_expirations (object_key TEXT PRIMARY KEY, expires_at TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)").run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS media_access (
            object_key TEXT PRIMARY KEY, owner_id TEXT NOT NULL, recipient_id TEXT,
            group_id TEXT, file_name TEXT NOT NULL, content_type TEXT NOT NULL, expires_at TEXT NOT NULL
          )
        `).run();

        const requestedStatusId = (request.headers.get("X-Status-Id") || "").trim();
        if (requestedStatusId.length > 128) return json({ error: "Invalid SPARK status identifier" }, 400);
        const id = requestedStatusId || crypto.randomUUID();
        let existingStatusExpiry = null;
        if (requestedStatusId) {
          const existingStatus = await env.DB.prepare(
            "SELECT user_id, expires_at FROM status_posts WHERE id = ?"
          ).bind(requestedStatusId).first();
          if (!existingStatus || existingStatus.user_id !== currentUser.sub ||
              Date.parse(existingStatus.expires_at) <= Date.now()) {
            return json({ error: "SPARK status not found or expired" }, 404);
          }
          existingStatusExpiry = existingStatus.expires_at;
          const existingMediaCount = await env.DB.prepare(
            "SELECT COUNT(*) AS count FROM status_media WHERE status_id = ?"
          ).bind(requestedStatusId).first();
          if (Number(existingMediaCount?.count || 0) >= 10) {
            return json({ error: "A SPARK status can contain at most 10 media files" }, 409);
          }
        }
        const mediaId = crypto.randomUUID();
        const objectKey = currentUser.sub + "/" + crypto.randomUUID();
        const suppliedName = safeFileName(request.headers.get("X-File-Name") || "spark-media");
        const expiresAt = existingStatusExpiry || new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
        const bucket = env.TIGRIS_BUCKET || "siraj-media";
        const objectPath = objectKey.split("/").map(encodeURIComponent).join("/");
        const storageUrl = "https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + objectPath;
        const storage = new AwsClient({
          accessKeyId: env.TIGRIS_ACCESS_KEY_ID, secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
          service: "s3", region: "auto", retries: 2
        });
        const putResponse = await storage.fetch(storageUrl, {
          method: "PUT",
          headers: {
            "Content-Type": contentType,
            "x-amz-meta-ownerid": currentUser.sub,
            "x-amz-meta-filename": encodeURIComponent(suppliedName),
            "x-amz-meta-contenttype": contentType,
            "x-amz-meta-expiresat": expiresAt,
            "x-amz-meta-category": "spark"
          },
          body: bytes
        });
        if (!putResponse.ok) {
          return json({ error: "SPARK media upload failed", storageStatus: putResponse.status }, 502);
        }
        try {
          const statements = [];
          if (!requestedStatusId) {
            statements.push(env.DB.prepare(
              "INSERT INTO status_posts (id, user_id, content, expires_at) VALUES (?, ?, ?, ?)"
            ).bind(id, currentUser.sub, caption, expiresAt));
          }
          const mediaInsertIndex = statements.length;
          statements.push(
            // Enforce the 10-file ceiling atomically in D1 as well as with the
            // early count check above, so concurrent uploads cannot exceed it.
            env.DB.prepare(
              "INSERT INTO status_media (id, status_id, object_key, file_name, content_type, size, caption, created_at) SELECT ?, ?, ?, ?, ?, ?, ?, ? WHERE (SELECT COUNT(*) FROM status_media WHERE status_id = ?) < 10"
            ).bind(mediaId, id, objectKey, suppliedName, contentType, bytes.byteLength, caption, new Date().toISOString(), id),
            env.DB.prepare(
              "INSERT INTO media_expirations (object_key, expires_at) SELECT ?, ? WHERE EXISTS (SELECT 1 FROM status_media WHERE object_key = ?)"
            ).bind(objectKey, expiresAt, objectKey),
            env.DB.prepare(
              "INSERT INTO media_access (object_key, owner_id, recipient_id, group_id, file_name, content_type, expires_at) SELECT ?, ?, NULL, NULL, ?, ?, ? WHERE EXISTS (SELECT 1 FROM status_media WHERE object_key = ?)"
            ).bind(objectKey, currentUser.sub, suppliedName, contentType, expiresAt, objectKey)
          );
          const savedRows = await env.DB.batch(statements);
          if (Number(savedRows?.[mediaInsertIndex]?.meta?.changes || 0) !== 1) {
            let deleted = false;
            try {
              const deletion = await storage.fetch(storageUrl, { method: "DELETE" });
              deleted = deletion.ok || deletion.status === 404;
            } catch (_) {}
            if (deleted) {
              try { await env.DB.prepare("DELETE FROM media_expirations WHERE object_key = ?").bind(objectKey).run(); } catch (_) {}
            }
            return json({ error: "A SPARK status can contain at most 10 media files" }, 409);
          }
        } catch (error) {
          let deleted = false;
          try {
            const deletion = await storage.fetch(storageUrl, { method: "DELETE" });
            deleted = deletion.ok || deletion.status === 404;
          } catch (_) {}
          if (deleted) {
            try { await env.DB.prepare("DELETE FROM media_expirations WHERE object_key = ?").bind(objectKey).run(); } catch (_) {}
          }
          throw error;
        }
        if (!requestedStatusId) {
          try {
            const recipients = await env.DB.prepare(
              `SELECT f.friend_id FROM friendships f
             WHERE f.user_id = ?
               AND EXISTS (
                 SELECT 1 FROM friendships reciprocal
                 WHERE reciprocal.user_id = f.friend_id AND reciprocal.friend_id = ?
               )`
            ).bind(currentUser.sub, currentUser.sub).all();
            await Promise.all((recipients.results || []).map(item =>
              sendSirajPush(env, item.friend_id, currentUser.sub,
                currentUser.username, "لحظة جديدة في SPARK", { category: "statuses" })
            ));
          } catch (notificationError) {
            console.error("SPARK media notification dispatch failed:", notificationError);
          }
        }
        return json({
          status: {
            id, userId: currentUser.sub, content: caption,
            createdAt: new Date().toISOString(), expiresAt,
            media: { id: mediaId, attachmentId: objectKey, fileName: suppliedName, contentType, size: bytes.byteLength, caption }
          }
        }, 201);
      }

      // Publish a 24-hour text status
      if (method === "POST" && path === "/api/statuses") {
        // Prevent authenticated accounts from flooding friends with statuses.
        const statusAllowed = await consumeLoginAttempt(env, "status", currentUser.sub, 10);
        if (!statusAllowed) {
          return new Response(JSON.stringify({ error: "Too many status posts. Please try again in 15 minutes." }), {
            status: 429,
            headers: { ...corsHeaders, "Retry-After": "900" }
          });
        }
        const body = await readJsonRequestLimited(request);
        const content = String(body.content || "").trim();

        if (!content || content.length > 1000) {
          return json({ error: "Status text must be between 1 and 1000 characters" }, 400);
        }

        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_posts (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            expires_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();

        const id = crypto.randomUUID();
        await env.DB.prepare(
          `INSERT INTO status_posts (id, user_id, content, expires_at)
           VALUES (?, ?, ?, datetime('now', '+24 hours'))`
        ).bind(id, currentUser.sub, content).run();

        // Status persistence is authoritative; push failures must not undo it.
        try {
          const recipients = await env.DB.prepare(
            `SELECT f.friend_id FROM friendships f
             WHERE f.user_id = ?
               AND EXISTS (
                 SELECT 1 FROM friendships reciprocal
                 WHERE reciprocal.user_id = f.friend_id AND reciprocal.friend_id = ?
               )`
          ).bind(currentUser.sub, currentUser.sub).all();
          await Promise.all((recipients.results || []).map(item =>
            sendSirajPush(env, item.friend_id, currentUser.sub,
              currentUser.username, "شارك لحظة جديدة في SPARK", { category: "statuses" })
          ));
        } catch (notificationError) {
          console.error("Status notification dispatch failed:", notificationError);
        }

        return json({
          status: { id, content, createdAt: new Date().toISOString(), expiresAt: new Date(Date.now() + 86400000).toISOString() }
        }, 201);
      }

      // List active statuses from the current user and their friends
      if (method === "GET" && path === "/api/statuses") {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_posts (
            id TEXT PRIMARY KEY,
            user_id TEXT NOT NULL,
            content TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            expires_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();

        await ensureProfilePhotos(env);
        // A first-ever SPARK feed request must not query status_views before
        // the table has been created by the viewer endpoint.
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_views (
            status_id TEXT NOT NULL,
            viewer_id TEXT NOT NULL,
            viewed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (status_id, viewer_id),
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
            FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        const result = await env.DB.prepare(
          `SELECT s.id, s.user_id AS userId, u.username,
                  u.display_name AS displayName, s.content,
                  s.created_at AS createdAt, s.expires_at AS expiresAt,
                  CASE WHEN pp.user_id IS NOT NULL
                    THEN '/api/profile/photo/' || u.id ELSE NULL END AS photoUrl,
                  pp.updated_at AS photoUpdatedAt,
                  (SELECT COUNT(*) FROM status_views sv WHERE sv.status_id = s.id) AS viewCount
           FROM status_posts s
           JOIN users u ON u.id = s.user_id
           LEFT JOIN profile_photos pp ON pp.user_id = u.id
           WHERE s.expires_at > CURRENT_TIMESTAMP
             AND (
               s.user_id = ?
               OR EXISTS (
                 SELECT 1 FROM friendships f
                 WHERE f.user_id = ? AND f.friend_id = s.user_id
                   AND EXISTS (
                     SELECT 1 FROM friendships reciprocal
                     WHERE reciprocal.user_id = s.user_id AND reciprocal.friend_id = ?
                   )
               )
             )
           ORDER BY s.created_at DESC
           LIMIT 100`
        ).bind(currentUser.sub, currentUser.sub, currentUser.sub).all();

        const statuses = result.results || [];
        if (statuses.length) {
          await env.DB.prepare(`
            CREATE TABLE IF NOT EXISTS status_media (
              id TEXT PRIMARY KEY, status_id TEXT NOT NULL, object_key TEXT NOT NULL UNIQUE,
              file_name TEXT NOT NULL, content_type TEXT NOT NULL,
              size INTEGER NOT NULL, caption TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
              FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE
            )
          `).run();
          const ids = statuses.map(item => item.id);
          const placeholders = ids.map(() => "?").join(",");
          const mediaResult = await env.DB.prepare(
            `SELECT status_id AS statusId, object_key AS attachmentId,
                    file_name AS fileName, content_type AS contentType,
                    size, caption, created_at AS createdAt
             FROM status_media WHERE status_id IN (${placeholders}) ORDER BY created_at ASC`
          ).bind(...ids).all();
          const mediaByStatus = new Map();
          for (const media of mediaResult.results || []) {
            const list = mediaByStatus.get(media.statusId) || [];
            list.push(media);
            mediaByStatus.set(media.statusId, list);
          }
          for (const item of statuses) item.media = mediaByStatus.get(item.id) || [];
        } else {
          for (const item of statuses) item.media = [];
        }
        return json({ statuses });
      }

      // Record unique SPARK viewers and expose the viewer list only to the status owner.
      const sparkViewerMatch = path.match(/^\/api\/statuses\/([^/]+)\/(view|viewers)$/);
      if (sparkViewerMatch) {
        let statusId;
        try { statusId = decodeURIComponent(sparkViewerMatch[1]); } catch (_) {
          return json({ error: "Invalid SPARK status identifier" }, 400);
        }
        const action = sparkViewerMatch[2];
        const status = await env.DB.prepare(
          "SELECT user_id FROM status_posts WHERE id = ? AND expires_at > CURRENT_TIMESTAMP"
        ).bind(statusId).first();
        if (!status) return json({ error: "SPARK status not found or expired" }, 404);
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_views (
            status_id TEXT NOT NULL, viewer_id TEXT NOT NULL,
            viewed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (status_id, viewer_id),
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
            FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        if (action === "view" && method === "POST") {
          if (status.user_id !== currentUser.sub) {
            const friendship = await env.DB.prepare(
              `SELECT 1 FROM friendships f
               WHERE f.user_id = ? AND f.friend_id = ?
                 AND EXISTS (
                   SELECT 1 FROM friendships reciprocal
                   WHERE reciprocal.user_id = ? AND reciprocal.friend_id = ?
                 )`
            ).bind(currentUser.sub, status.user_id, status.user_id, currentUser.sub).first();
            if (!friendship) return json({ error: "SPARK status access denied" }, 403);
            await env.DB.prepare(
              "INSERT OR IGNORE INTO status_views (status_id, viewer_id) VALUES (?, ?)"
            ).bind(statusId, currentUser.sub).run();
          }
          const count = await env.DB.prepare(
            "SELECT COUNT(*) AS count FROM status_views WHERE status_id = ?"
          ).bind(statusId).first();
          return json({ statusId, viewCount: Number(count?.count || 0) });
        }
        if (action === "viewers" && method === "GET") {
          if (status.user_id !== currentUser.sub) return json({ error: "Only the status owner can view this list" }, 403);
          const viewers = await env.DB.prepare(
            `SELECT sv.viewed_at AS viewedAt, u.id, u.display_name AS displayName, u.username
             FROM status_views sv JOIN users u ON u.id = sv.viewer_id
             WHERE sv.status_id = ? ORDER BY sv.viewed_at DESC LIMIT 100`
          ).bind(statusId).all();
          return json({ viewers: viewers.results || [] });
        }
        return json({ error: "Method not allowed" }, 405);
      }


      // Private voice replies for SPARK. Audio objects inherit the parent status expiry.
      const sparkAudioReplyMatch = path.match(/^\/api\/statuses\/([^/]+)\/audio-replies(?:\/([^/]+))?$/);
      if (sparkAudioReplyMatch) {
        let statusId, audioReplyId = null;
        try {
          statusId = decodeURIComponent(sparkAudioReplyMatch[1]);
          audioReplyId = sparkAudioReplyMatch[2] ? decodeURIComponent(sparkAudioReplyMatch[2]) : null;
        } catch (_) {
          return json({ error: "Invalid SPARK audio reply identifier" }, 400);
        }
        if (!statusId || statusId.length > 128 || (audioReplyId && audioReplyId.length > 128)) {
          return json({ error: "Invalid SPARK audio reply identifier" }, 400);
        }
        const status = await env.DB.prepare(
          "SELECT user_id, expires_at FROM status_posts WHERE id = ? AND expires_at > CURRENT_TIMESTAMP"
        ).bind(statusId).first();
        if (!status) return json({ error: "SPARK status not found or expired" }, 404);
        const isOwner = status.user_id === currentUser.sub;
        if (!isOwner) {
          const friendship = await env.DB.prepare(
            `SELECT 1 FROM friendships f
             WHERE f.user_id = ? AND f.friend_id = ?
               AND EXISTS (
                 SELECT 1 FROM friendships reciprocal
                 WHERE reciprocal.user_id = ? AND reciprocal.friend_id = ?
               )`
          ).bind(currentUser.sub, status.user_id, status.user_id, currentUser.sub).first();
          if (!friendship) return json({ error: "SPARK status access denied" }, 403);
        }
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_audio_replies (
            id TEXT PRIMARY KEY, status_id TEXT NOT NULL, user_id TEXT NOT NULL,
            object_key TEXT NOT NULL UNIQUE, content_type TEXT NOT NULL,
            size INTEGER NOT NULL, duration_ms INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        if (method === "POST" && !audioReplyId) {
          if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
            return json({ error: "Media storage credentials are not configured" }, 503);
          }
          if (!(await consumeLoginAttempt(env, "spark_audio_reply", currentUser.sub, 10))) {
            return new Response(JSON.stringify({ error: "Too many SPARK voice replies. Try again later." }), {
              status: 429, headers: { ...corsHeaders, "Retry-After": "900" }
            });
          }
          const contentType = (request.headers.get("Content-Type") || "").split(";")[0].trim().toLowerCase();
          if (contentType !== "audio/mp4") return json({ error: "SPARK voice replies must use AAC audio in an MP4 container" }, 415);
          const durationMs = Number(request.headers.get("X-Audio-Duration-Ms"));
          if (!Number.isInteger(durationMs) || durationMs < 1000 || durationMs > 60000) {
            return json({ error: "SPARK voice replies must be between 1 and 60 seconds" }, 400);
          }
          await env.DB.prepare("CREATE TABLE IF NOT EXISTS media_expirations (object_key TEXT PRIMARY KEY, expires_at TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)").run();
          const maxAudioReplyBytes = 5 * 1024 * 1024;
          const declaredLength = Number(request.headers.get("Content-Length"));
          if (Number.isFinite(declaredLength) && declaredLength > maxAudioReplyBytes) {
            return json({ error: "SPARK voice replies must not exceed 5 MB" }, 413);
          }
          const bytes = await readRequestBodyLimited(request, maxAudioReplyBytes);
          if (!bytes?.byteLength) return json({ error: "SPARK audio is empty or exceeds 5 MB" }, 413);
          const audioSignature = bytes.length >= 12
            ? String.fromCharCode(...bytes.slice(4, 8))
            : "";
          if (audioSignature !== "ftyp") return json({ error: "Invalid AAC audio file" }, 415);

          const audioReplyId = crypto.randomUUID();
          const objectKey = currentUser.sub + "/spark-audio/" + crypto.randomUUID();
          const expiresAt = status.expires_at;
          const bucket = env.TIGRIS_BUCKET || "siraj-media";
          const objectPath = objectKey.split("/").map(encodeURIComponent).join("/");
          const storageUrl = "https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + objectPath;
          const storage = new AwsClient({
            accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
            secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
            service: "s3",
            region: "auto",
            retries: 2
          });
          const putResponse = await storage.fetch(storageUrl, {
            method: "PUT",
            headers: {
              "Content-Type": contentType,
              "x-amz-meta-ownerid": currentUser.sub,
              "x-amz-meta-statusid": statusId,
              "x-amz-meta-expiresat": expiresAt,
              "x-amz-meta-category": "spark-audio-reply"
            },
            body: bytes
          });
          if (!putResponse.ok) return json({ error: "SPARK voice reply upload failed" }, 502);
          try {
            await env.DB.batch([
              env.DB.prepare(
                "INSERT INTO status_audio_replies (id, status_id, user_id, object_key, content_type, size, duration_ms, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
              ).bind(audioReplyId, statusId, currentUser.sub, objectKey, contentType, bytes.byteLength, durationMs, new Date().toISOString()),
              env.DB.prepare(
                "INSERT INTO media_expirations (object_key, expires_at) VALUES (?, ?)"
              ).bind(objectKey, expiresAt)
            ]);
          } catch (error) {
            try { await storage.fetch(storageUrl, { method: "DELETE" }); } catch (_) {}
            throw error;
          }
          if (!isOwner) {
            try {
              const sender = await env.DB.prepare("SELECT display_name FROM users WHERE id = ?").bind(currentUser.sub).first();
              await sendSirajPush(env, status.user_id, currentUser.sub,
                sender?.display_name || currentUser.username || "مستخدم برق",
                "رد صوتي جديد على SPARK", { category: "statuses" });
            } catch (notificationError) {
              console.error("SPARK audio reply notification failed:", notificationError);
            }
          }
          return json({ audioReply: {
            id: audioReplyId, statusId, userId: currentUser.sub,
            contentType, size: bytes.byteLength, durationMs,
            createdAt: new Date().toISOString()
          } }, 201);
        }
        if (method === "GET" && !audioReplyId) {
          const rows = await env.DB.prepare(
            `SELECT r.id, r.user_id AS userId, r.content_type AS contentType,
                    r.duration_ms AS durationMs, r.created_at AS createdAt,
                    u.display_name AS displayName, u.username
             FROM status_audio_replies r JOIN users u ON u.id = r.user_id
             WHERE r.status_id = ? ORDER BY r.created_at ASC LIMIT 100`
          ).bind(statusId).all();
          return json({ audioReplies: rows.results || [] });
        }
        if (method === "GET" && audioReplyId) {
          if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
            return json({ error: "Media storage credentials are not configured" }, 503);
          }
          const row = await env.DB.prepare(
            `SELECT object_key AS objectKey, content_type AS contentType, expires_at AS expiresAt
             FROM status_audio_replies r JOIN status_posts s ON s.id = r.status_id
             WHERE r.id = ? AND r.status_id = ? AND s.expires_at > CURRENT_TIMESTAMP LIMIT 1`
          ).bind(audioReplyId, statusId).first();
          if (!row) return json({ error: "SPARK audio reply not found or expired" }, 404);
          const bucket = env.TIGRIS_BUCKET || "siraj-media";
          const objectPath = row.objectKey.split("/").map(encodeURIComponent).join("/");
          const storageUrl = "https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + objectPath;
          const storage = new AwsClient({
            accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
            secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
            service: "s3",
            region: "auto",
            retries: 2
          });
          const media = await storage.fetch(storageUrl);
          if (!media.ok) return json({ error: "SPARK audio reply media unavailable" }, media.status === 404 ? 404 : 502);
          return new Response(media.body, {
            status: 200,
            headers: {
              ...corsHeaders,
              "Content-Type": row.contentType,
              "Cache-Control": "private, no-store",
              "X-Content-Type-Options": "nosniff",
              "Content-Disposition": "inline"
            }
          });
        }
        return json({ error: "Method not allowed" }, 405);
      }

      // SPARK replies and reactions are available only while the status is active and visible.
      const sparkInteractionMatch = path.match(/^\/api\/statuses\/([^/]+)\/(reactions|replies)$/);
      if (sparkInteractionMatch) {
        let statusId;
        try { statusId = decodeURIComponent(sparkInteractionMatch[1]); } catch (_) {
          return json({ error: "Invalid SPARK status identifier" }, 400);
        }
        const action = sparkInteractionMatch[2];
        const status = await env.DB.prepare(
          "SELECT user_id, expires_at FROM status_posts WHERE id = ? AND expires_at > CURRENT_TIMESTAMP"
        ).bind(statusId).first();
        if (!status) return json({ error: "SPARK status not found or expired" }, 404);
        const isOwner = status.user_id === currentUser.sub;
        if (!isOwner) {
          const friendship = await env.DB.prepare(
            `SELECT 1 FROM friendships f
             WHERE f.user_id = ? AND f.friend_id = ?
               AND EXISTS (
                 SELECT 1 FROM friendships reciprocal
                 WHERE reciprocal.user_id = ? AND reciprocal.friend_id = ?
               )`
          ).bind(currentUser.sub, status.user_id, status.user_id, currentUser.sub).first();
          if (!friendship) return json({ error: "SPARK status access denied" }, 403);
        }
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_reactions (
            status_id TEXT NOT NULL, user_id TEXT NOT NULL, emoji TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (status_id, user_id, emoji),
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_audio_replies (
            id TEXT PRIMARY KEY, status_id TEXT NOT NULL, user_id TEXT NOT NULL,
            object_key TEXT NOT NULL UNIQUE, content_type TEXT NOT NULL,
            size INTEGER NOT NULL, duration_ms INTEGER NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_replies (
            id TEXT PRIMARY KEY, status_id TEXT NOT NULL, user_id TEXT NOT NULL,
            body TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        if (action === "reactions") {
          if (method !== "POST" && method !== "DELETE") return json({ error: "Method not allowed" }, 405);
          const allowed = ["👍", "❤️", "😂", "😮", "😢", "😡", "🎉", "🔥"];
          const body = method === "POST" ? await readJsonRequestLimited(request) : null;
          const emoji = method === "POST" ? String(body.emoji || "") : (url.searchParams.get("emoji") || "");
          if (!allowed.includes(emoji)) return json({ error: "Unsupported reaction" }, 400);
          if (method === "POST") {
            await env.DB.prepare(
              "INSERT OR IGNORE INTO status_reactions (status_id, user_id, emoji) VALUES (?, ?, ?)"
            ).bind(statusId, currentUser.sub, emoji).run();
          } else {
            await env.DB.prepare(
              "DELETE FROM status_reactions WHERE status_id = ? AND user_id = ? AND emoji = ?"
            ).bind(statusId, currentUser.sub, emoji).run();
          }
          return json({ message: "SPARK reaction updated", statusId, emoji, active: method === "POST" });
        }
        if (method === "GET") {
          const replies = await env.DB.prepare(
            `SELECT r.id, r.body, r.created_at AS createdAt, r.user_id AS userId,
                    u.display_name AS displayName, u.username
             FROM status_replies r JOIN users u ON u.id = r.user_id
             WHERE r.status_id = ? ORDER BY r.created_at ASC LIMIT 100`
          ).bind(statusId).all();
          const audioReplies = await env.DB.prepare(
            `SELECT r.id, r.user_id AS userId, r.content_type AS contentType,
                    r.duration_ms AS durationMs, r.created_at AS createdAt,
                    u.display_name AS displayName, u.username
             FROM status_audio_replies r JOIN users u ON u.id = r.user_id
             WHERE r.status_id = ? ORDER BY r.created_at ASC LIMIT 100`
          ).bind(statusId).all();
          return json({ replies: replies.results || [], audioReplies: audioReplies.results || [] });
        }
        if (method === "POST") {
          const replyAllowed = await consumeLoginAttempt(env, "spark_reply", currentUser.sub, 20);
          if (!replyAllowed) return json({ error: "Too many SPARK replies. Try again later." }, 429);
          const body = await readJsonRequestLimited(request);
          const reply = String(body.body || "").trim();
          if (!reply || reply.length > 1000) return json({ error: "SPARK reply must be between 1 and 1000 characters" }, 400);
          const replyId = crypto.randomUUID();
          await env.DB.prepare(
            "INSERT INTO status_replies (id, status_id, user_id, body) VALUES (?, ?, ?, ?)"
          ).bind(replyId, statusId, currentUser.sub, reply).run();
          if (!isOwner) {
            try {
              const sender = await env.DB.prepare(
                "SELECT display_name FROM users WHERE id = ?"
              ).bind(currentUser.sub).first();
              await sendSirajPush(env, status.user_id, currentUser.sub,
                sender?.display_name || currentUser.username || "مستخدم برق",
                "رد جديد على SPARK", { category: "statuses" });
            } catch (notificationError) {
              console.error("SPARK reply notification failed:", notificationError);
            }
          }
          return json({ reply: { id: replyId, statusId, userId: currentUser.sub, body: reply } }, 201);
        }
        return json({ error: "Method not allowed" }, 405);
      }

      // Ensure privacy preferences table exists for all authenticated accounts.
      if (path === "/api/users/search" || path === "/api/messages") {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS user_privacy (
            user_id TEXT PRIMARY KEY,
            searchable INTEGER NOT NULL DEFAULT 1,
            read_receipts INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
      }

      // Search users
      if (method === "GET" && path === "/api/users/search") {
        const q = (url.searchParams.get("q") || "").trim();

        if (q.length < 2) {
          return json({ users: [] });
        }
        // Bound authenticated directory enumeration and repeated expensive LIKE queries.
        if (!(await consumeLoginAttempt(env, "user-search", currentUser.sub, 120))) {
          return new Response(JSON.stringify({ error: "Too many searches. Please try again in 15 minutes." }), {
            status: 429,
            headers: { ...corsHeaders, "Retry-After": "900" }
          });
        }

        const byId = new Map();
        const usernameMatches = await env.DB.prepare(
          `SELECT id, username, display_name, phone
           FROM users
           WHERE id != ?
             AND username LIKE ?
             AND COALESCE((SELECT searchable FROM user_privacy WHERE user_id = users.id), 1) = 1
           LIMIT 30`
        ).bind(currentUser.sub, "%" + q + "%").all();
        for (const candidate of usernameMatches.results || []) byId.set(candidate.id, candidate);

        // Phone lookup uses normalized digits so a Yemen local number can find
        // the same account saved with +967 / 00967, including Arabic/Persian digits.
        const normalizedQuery = q.replace(/[٠-٩۰-۹]/g, digit => {
          const code = digit.charCodeAt(0);
          return String(code >= 0x06f0 ? code - 0x06f0 : code - 0x0660);
        }).replace(/\D/g, "");
        if (normalizedQuery.length >= 2) {
          const variants = phoneVariants(q);
          const suffixes = [...new Set(variants.filter(value => value.length >= 9).map(value => value.slice(-9)))];
          const exactClause = variants.length ? ` OR ${normalizedPhoneSql("phone")} IN (${variants.map(() => "?").join(", ")})` : "";
          const suffixClause = suffixes.length ? ` OR substr(${normalizedPhoneSql("phone")}, -9) IN (${suffixes.map(() => "?").join(", ")})` : "";
          const phoneMatches = await env.DB.prepare(
            `SELECT id, username, display_name, phone
             FROM users
             WHERE id != ?
               AND (${normalizedPhoneSql("phone")} LIKE ?${exactClause}${suffixClause})
               AND COALESCE((SELECT searchable FROM user_privacy WHERE user_id = users.id), 1) = 1
             LIMIT 100`
          ).bind(currentUser.sub, "%" + normalizedQuery + "%", ...variants, ...suffixes).all();
          const localSearchDigits = normalizedQuery.startsWith("0")
            ? normalizedQuery.slice(1) : normalizedQuery;
          for (const candidate of phoneMatches.results || []) {
            const candidateDigits = String(candidate.phone || "").replace(/\D/g, "");
            if (phoneVariants(candidate.phone).some(value => variants.includes(value)) ||
                (localSearchDigits.length >= 2 && candidateDigits.includes(localSearchDigits))) {
              byId.set(candidate.id, candidate);
            }
          }
        }

        return json({ users: [...byId.values()].slice(0, 30).map(cleanUser) });
      }


      // Match phone contacts only after the client has obtained explicit permission.
      // Submitted phone numbers are processed in memory and are never persisted.
      if (method === "POST" && path === "/api/contacts/match") {
        const body = await readJsonRequestLimited(request);
        if (!Array.isArray(body.phones) || body.phones.length > 500) {
          return json({ error: "قائمة جهات الاتصال غير صالحة" }, 400);
        }
        // Contact matching performs several bounded database lookups; cap repeated bulk requests.
        if (!(await consumeLoginAttempt(env, "contact-match", currentUser.sub, 30))) {
          return new Response(JSON.stringify({ error: "Too many contact matching requests. Please try again in 15 minutes." }), {
            status: 429,
            headers: { ...corsHeaders, "Retry-After": "900" }
          });
        }
        const requested = new Set(
          body.phones.filter(value => typeof value === "string" && value.length <= 32)
            .flatMap(phoneVariants)
        );
        if (requested.size === 0) return json({ users: [] });
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS user_privacy (
            user_id TEXT PRIMARY KEY,
            searchable INTEGER NOT NULL DEFAULT 1,
            read_receipts INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        // Query only submitted phone variants in bounded batches. This avoids scanning
        // the first 10,000 accounts and keeps matching reliable as the user base grows.
        const variants = [...requested];
        const matchedById = new Map();
        for (let offset = 0; offset < variants.length; offset += 40) {
          const chunk = variants.slice(offset, offset + 40);
          const placeholders = chunk.map(() => "?").join(", ");
          const normalizedPhone = normalizedPhoneSql("phone");
          const suffixes = chunk.map(value => value.slice(-9)).filter(value => value.length === 9);
          const suffixPlaceholders = suffixes.map(() => "?").join(", ");
          const result = await env.DB.prepare(
            `SELECT id, username, display_name, phone
             FROM users
             WHERE id != ? AND (
               ${normalizedPhone} IN (${placeholders})
               OR substr(${normalizedPhone}, -9) IN (${suffixPlaceholders || "''"})
             )
               AND COALESCE((SELECT searchable FROM user_privacy WHERE user_id = users.id), 1) = 1`
          ).bind(currentUser.sub, ...chunk, ...suffixes).all();
          for (const candidate of result.results || []) {
            if (phoneVariants(candidate.phone).some(phone => requested.has(phone))) {
              matchedById.set(candidate.id, candidate);
            }
          }
        }
        return json({ users: [...matchedById.values()].map(cleanUser) });
      }

      // Add a contact directly (no friend-request workflow).
      if (method === "POST" && path === "/api/contacts") {
        const body = await readJsonRequestLimited(request);
        const userId = String(body.userId || "").trim();
        if (!userId || userId === currentUser.sub) {
          return json({ error: "Invalid contact" }, 400);
        }
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS user_privacy (
            user_id TEXT PRIMARY KEY,
            searchable INTEGER NOT NULL DEFAULT 1,
            read_receipts INTEGER NOT NULL DEFAULT 1,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        const target = await env.DB.prepare(
          `SELECT u.id,
                  COALESCE((SELECT searchable FROM user_privacy WHERE user_id = u.id), 1) AS searchable
           FROM users u WHERE u.id = ?`
        ).bind(userId).first();
        if (!target || target.searchable !== 1) {
          return json({ error: "User not found" }, 404);
        }
        await env.DB.batch([
          env.DB.prepare(
            "INSERT OR IGNORE INTO friendships (user_id, friend_id) VALUES (?, ?)"
          ).bind(currentUser.sub, userId),
          env.DB.prepare(
            "INSERT OR IGNORE INTO friendships (user_id, friend_id) VALUES (?, ?)"
          ).bind(userId, currentUser.sub)
        ]);
        return json({ message: "Contact added", userId }, 201);
      }

      // Friend requests are intentionally disabled in BARQ.
      // Users add contacts directly through POST /api/contacts.
      if (method === "POST" && path === "/api/friends/requests") {
        return json({ error: "Friend requests are not supported. Add the contact directly." }, 410);
      }

      if (method === "GET" && path === "/api/friends/requests") {
        return json({ incoming: [], outgoing: [] });
      }

      if (method === "POST" && path.startsWith("/api/friends/requests/")) {
        return json({ error: "Friend requests are not supported. Add the contact directly." }, 410);
      }

      // Get friends
      if (method === "GET" && path === "/api/friends") {
        await ensureProfilePhotos(env);
        const friends = await env.DB.prepare(
          `SELECT u.id, u.username, u.display_name, u.phone,
                  p.updated_at AS photo_updated_at
           FROM friendships f
           JOIN users u ON u.id = f.friend_id
           LEFT JOIN profile_photos p ON p.user_id = u.id
           WHERE f.user_id = ?
           ORDER BY u.display_name`
        ).bind(currentUser.sub).all();

        return json({
          friends: (friends.results || []).map(cleanUser)
        });
      }

      // Preview-safe message interaction tables; production is never migrated here.
      if (path === "/api/messages" || path.startsWith("/api/messages/") || path.startsWith("/api/groups/")) {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS message_reactions (
            scope_type TEXT NOT NULL CHECK (scope_type IN ('private', 'group')),
            scope_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            emoji TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (scope_type, scope_id, message_id, user_id, emoji)
          )
        `).run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS pinned_messages (
            scope_type TEXT NOT NULL CHECK (scope_type IN ('private', 'group')),
            scope_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            pinned_by TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (scope_type, scope_id, message_id, pinned_by)
          )
        `).run();
      }

      // Group chat tables and membership helpers.
      if (path === "/api/groups" || path.startsWith("/api/groups/")) {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS chat_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT NOT NULL DEFAULT '',
            owner_id TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (owner_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS group_members (
            group_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (group_id, user_id),
            FOREIGN KEY (group_id) REFERENCES chat_groups(id) ON DELETE CASCADE,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        // Optional admin assignments are stored separately so existing member
        // rows remain valid and default to the least-privileged "member" role.
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS group_member_roles (
            group_id TEXT NOT NULL,
            user_id TEXT NOT NULL,
            role TEXT NOT NULL CHECK (role IN ('admin', 'member')),
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (group_id, user_id),
            FOREIGN KEY (group_id, user_id)
              REFERENCES group_members(group_id, user_id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS group_messages (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            reply_to_id TEXT,
            reply_to_body TEXT,
            reply_to_sender_id TEXT,
            edited_at TEXT,
            FOREIGN KEY (group_id) REFERENCES chat_groups(id) ON DELETE CASCADE,
            FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
      }

      if (method === "GET" && path === "/api/groups") {
        const result = await env.DB.prepare(`
          SELECT g.id, g.name, g.description, g.owner_id,
                 g.created_at,
                 (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id) AS member_count,
                 CASE WHEN g.owner_id = ? THEN 'owner'
                      ELSE COALESCE(my_role.role, 'member') END AS current_role
          FROM chat_groups g
          JOIN group_members mine ON mine.group_id = g.id
          LEFT JOIN group_member_roles my_role
            ON my_role.group_id = g.id AND my_role.user_id = mine.user_id
          WHERE mine.user_id = ?
          ORDER BY g.created_at DESC
        `).bind(currentUser.sub, currentUser.sub).all();
        return json({ groups: result.results || [] });
      }

      if (method === "POST" && path === "/api/groups") {
        const body = await readJsonRequestLimited(request);
        const name = String(body.name || "").trim();
        const description = String(body.description || "").trim();
        if (!name || name.length > 80 || description.length > 300) {
          return json({ error: "Invalid group name or description" }, 400);
        }
        const id = crypto.randomUUID();
        await env.DB.batch([
          env.DB.prepare(
            "INSERT INTO chat_groups (id, name, description, owner_id) VALUES (?, ?, ?, ?)"
          ).bind(id, name, description, currentUser.sub),
          env.DB.prepare(
            "INSERT INTO group_members (group_id, user_id) VALUES (?, ?)"
          ).bind(id, currentUser.sub)
        ]);
        return json({ group: { id, name, description, owner_id: currentUser.sub, member_count: 1 } }, 201);
      }

      const groupMemberMatch = path.match(/^\/api\/groups\/([^/]+)\/members$/);
      if (method === "GET" && groupMemberMatch) {
        const groupId = groupMemberMatch[1];
        const member = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, currentUser.sub).first();
        if (!member) return json({ error: "Group not found" }, 404);
        await ensureProfilePhotos(env);
        const result = await env.DB.prepare(`
          SELECT u.id, u.username, u.display_name, u.phone, m.joined_at,
                 p.updated_at AS photo_updated_at,
                 CASE WHEN g.owner_id = u.id THEN 1 ELSE 0 END AS is_owner,
                 CASE WHEN g.owner_id = u.id THEN 'owner'
                      ELSE COALESCE(r.role, 'member') END AS role
          FROM group_members m
          JOIN users u ON u.id = m.user_id
          JOIN chat_groups g ON g.id = m.group_id
          LEFT JOIN profile_photos p ON p.user_id = u.id
          LEFT JOIN group_member_roles r
            ON r.group_id = m.group_id AND r.user_id = m.user_id
          WHERE m.group_id = ?
          ORDER BY is_owner DESC, role ASC, u.display_name ASC
        `).bind(groupId).all();
        return json({ members: result.results || [] });
      }

      if (method === "POST" && groupMemberMatch) {
        const groupId = groupMemberMatch[1];
        const body = await readJsonRequestLimited(request);
        const userId = String(body.userId || "").trim();
        // Owners and explicitly assigned admins may invite members. Ordinary
        // members cannot expand group access or invite arbitrary accounts.
        const group = await env.DB.prepare(
          "SELECT owner_id FROM chat_groups WHERE id = ?"
        ).bind(groupId).first();
        if (!group) return json({ error: "Group not found" }, 404);
        const actorRole = group.owner_id === currentUser.sub ? "owner" :
          (await env.DB.prepare(
            "SELECT role FROM group_member_roles WHERE group_id = ? AND user_id = ?"
          ).bind(groupId, currentUser.sub).first())?.role || "member";
        if (actorRole !== "owner" && actorRole !== "admin") {
          return json({ error: "Only group owners and admins can add members" }, 403);
        }
        if (!userId || userId.length > 128) return json({ error: "Invalid user id" }, 400);
        const target = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(userId).first();
        if (!target) return json({ error: "User not found" }, 404);
        await env.DB.prepare(
          "INSERT OR IGNORE INTO group_members (group_id, user_id) VALUES (?, ?)"
        ).bind(groupId, userId).run();
        return json({ message: "Member added", role: "member" }, 201);
      }

      // Only the owner can promote/demote admins. The owner role is implicit
      // and cannot be assigned or removed through this endpoint.
      const groupRoleMatch = path.match(/^\/api\/groups\/([^/]+)\/members\/([^/]+)\/role$/);
      if (method === "POST" && groupRoleMatch) {
        const groupId = groupRoleMatch[1];
        const targetUserId = groupRoleMatch[2];
        const body = await readJsonRequestLimited(request);
        const role = String(body.role || "").trim().toLowerCase();
        if (role !== "admin" && role !== "member") {
          return json({ error: "Role must be admin or member" }, 400);
        }
        const group = await env.DB.prepare(
          "SELECT owner_id FROM chat_groups WHERE id = ?"
        ).bind(groupId).first();
        if (!group) return json({ error: "Group not found" }, 404);
        if (group.owner_id !== currentUser.sub) {
          return json({ error: "Only the group owner can manage admin roles" }, 403);
        }
        if (targetUserId === group.owner_id) {
          return json({ error: "The group owner role cannot be changed" }, 400);
        }
        const targetMember = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, targetUserId).first();
        if (!targetMember) return json({ error: "Group member not found" }, 404);
        if (role === "admin") {
          await env.DB.prepare(`
            INSERT INTO group_member_roles (group_id, user_id, role, updated_at)
            VALUES (?, ?, 'admin', CURRENT_TIMESTAMP)
            ON CONFLICT(group_id, user_id)
            DO UPDATE SET role = 'admin', updated_at = CURRENT_TIMESTAMP
          `).bind(groupId, targetUserId).run();
        } else {
          await env.DB.prepare(
            "DELETE FROM group_member_roles WHERE group_id = ? AND user_id = ?"
          ).bind(groupId, targetUserId).run();
        }
        return json({ message: "Member role updated", userId: targetUserId, role });
      }

      // Only the current owner can transfer ownership to an existing group member.
      const groupOwnershipMatch = path.match(/^\/api\/groups\/([^/]+)\/owner$/);
      if (method === "POST" && groupOwnershipMatch) {
        const groupId = groupOwnershipMatch[1];
        const body = await readJsonRequestLimited(request);
        const targetUserId = String(body.userId || "").trim();
        if (!targetUserId || targetUserId.length > 128 || targetUserId === currentUser.sub) {
          return json({ error: "Choose another valid group member as the new owner" }, 400);
        }
        const results = await env.DB.batch([
          env.DB.prepare(
            `UPDATE chat_groups
             SET owner_id = ?
             WHERE id = ? AND owner_id = ?
               AND EXISTS (
                 SELECT 1 FROM group_members
                 WHERE group_id = ? AND user_id = ?
               )`
          ).bind(targetUserId, groupId, currentUser.sub, groupId, targetUserId),
          env.DB.prepare(
            `DELETE FROM group_member_roles
             WHERE group_id = ? AND user_id IN (?, ?)
               AND EXISTS (
                 SELECT 1 FROM chat_groups
                 WHERE id = ? AND owner_id = ?
               )`
          ).bind(groupId, currentUser.sub, targetUserId, groupId, targetUserId)
        ]);
        if (Number(results?.[0]?.meta?.changes || 0) !== 1) {
          return json({ error: "Group not found, ownership changed, or target is not a member" }, 409);
        }
        return json({ message: "Group ownership transferred", ownerId: targetUserId });
      }

      // Members may leave themselves; owners can remove any non-owner member,
      // while admins can remove ordinary members but not fellow admins.
      const groupMemberActionMatch = path.match(/^\/api\/groups\/([^/]+)\/members\/([^/]+)$/);
      if (method === "DELETE" && groupMemberActionMatch) {
        const groupId = groupMemberActionMatch[1];
        const targetUserId = groupMemberActionMatch[2];
        const group = await env.DB.prepare(
          "SELECT owner_id FROM chat_groups WHERE id = ?"
        ).bind(groupId).first();
        if (!group) return json({ error: "Group not found" }, 404);
        if (targetUserId === group.owner_id) {
          return json({ error: "The group owner cannot leave or be removed before ownership is transferred" }, 403);
        }
        const target = await env.DB.prepare(
          "SELECT role FROM group_member_roles WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, targetUserId).first();
        const targetExists = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, targetUserId).first();
        if (!targetExists) return json({ error: "Group member not found" }, 404);
        const actorRole = group.owner_id === currentUser.sub ? "owner" :
          (await env.DB.prepare(
            "SELECT role FROM group_member_roles WHERE group_id = ? AND user_id = ?"
          ).bind(groupId, currentUser.sub).first())?.role || "member";
        const selfLeave = targetUserId === currentUser.sub;
        if (!selfLeave && actorRole !== "owner" &&
            !(actorRole === "admin" && (target?.role || "member") === "member")) {
          return json({ error: "You do not have permission to remove this member" }, 403);
        }
        await env.DB.batch([
          env.DB.prepare(
            "DELETE FROM group_member_roles WHERE group_id = ? AND user_id = ?"
          ).bind(groupId, targetUserId),
          env.DB.prepare(
            "DELETE FROM group_members WHERE group_id = ? AND user_id = ?"
          ).bind(groupId, targetUserId)
        ]);
        return json({ message: selfLeave ? "You left the group" : "Member removed", userId: targetUserId });
      }

            // Group reactions and personal pins are available only to current group members.
      const groupInteractionMatch = path.match(/^\/api\/groups\/([^/]+)\/messages\/([^/]+)\/(reactions|pin)$/);
      if (groupInteractionMatch && (method === "POST" || method === "DELETE")) {
        const groupId = groupInteractionMatch[1];
        const messageId = groupInteractionMatch[2];
        const action = groupInteractionMatch[3];
        const member = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, currentUser.sub).first();
        if (!member) return json({ error: "Group not found" }, 404);
        const target = await env.DB.prepare(
          "SELECT id FROM group_messages WHERE id = ? AND group_id = ?"
        ).bind(messageId, groupId).first();
        if (!target) return json({ error: "Message not found" }, 404);
        if (action === "reactions") {
          const allowed = ["👍", "❤️", "😂", "😮", "😢", "😡", "🎉", "🔥"];
          let emoji = "";
          if (method === "POST") {
            const body = await readJsonRequestLimited(request);
            emoji = String(body.emoji || "");
          } else {
            emoji = url.searchParams.get("emoji") || "";
          }
          if (!allowed.includes(emoji)) return json({ error: "Unsupported reaction" }, 400);
          if (method === "POST") {
            await env.DB.prepare(
              "INSERT OR IGNORE INTO message_reactions (scope_type, scope_id, message_id, user_id, emoji) VALUES ('group', ?, ?, ?, ?)"
            ).bind(groupId, messageId, currentUser.sub, emoji).run();
          } else {
            await env.DB.prepare(
              "DELETE FROM message_reactions WHERE scope_type = 'group' AND scope_id = ? AND message_id = ? AND user_id = ? AND emoji = ?"
            ).bind(groupId, messageId, currentUser.sub, emoji).run();
          }
          return json({ message: "Reaction updated", messageId, emoji, active: method === "POST" });
        }
        if (method === "POST") {
          await env.DB.prepare(
            "INSERT OR IGNORE INTO pinned_messages (scope_type, scope_id, message_id, pinned_by) VALUES ('group', ?, ?, ?)"
          ).bind(groupId, messageId, currentUser.sub).run();
        } else {
          await env.DB.prepare(
            "DELETE FROM pinned_messages WHERE scope_type = 'group' AND scope_id = ? AND message_id = ? AND pinned_by = ?"
          ).bind(groupId, messageId, currentUser.sub).run();
        }
        return json({ message: method === "POST" ? "Message pinned" : "Pin removed", messageId, pinned: method === "POST" });
      }

      // Group members may delete only messages they authored.
      const groupMessageActionMatch = path.match(/^\/api\/groups\/([^/]+)\/messages\/([^/]+)$/);
      if ((method === "DELETE" || method === "PATCH") && groupMessageActionMatch) {
        const groupId = groupMessageActionMatch[1];
        const messageId = groupMessageActionMatch[2];
        const member = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, currentUser.sub).first();
        if (!member) return json({ error: "Group not found" }, 404);
        const owned = await env.DB.prepare(
          "SELECT id FROM group_messages WHERE id = ? AND group_id = ? AND sender_id = ?"
        ).bind(messageId, groupId, currentUser.sub).first();
        if (!owned) return json({ error: "Message not found or cannot be changed" }, 404);
        if (method === "PATCH") {
          const body = await readJsonRequestLimited(request);
          const message = String(body.body || "").trim();
          if (!message || message.length > 5000) return json({ error: "Invalid message" }, 400);
          await env.DB.prepare(
            "UPDATE group_messages SET body = ?, edited_at = CURRENT_TIMESTAMP WHERE id = ? AND group_id = ? AND sender_id = ?"
          ).bind(message, messageId, groupId, currentUser.sub).run();
          return json({ message: "Message updated", id: messageId, body: message, editedAt: true });
        }
        await env.DB.prepare(
          "DELETE FROM group_messages WHERE id = ? AND group_id = ? AND sender_id = ?"
        ).bind(messageId, groupId, currentUser.sub).run();
        return json({ message: "Message deleted", id: messageId });
      }

const groupMessageSearchMatch = path.match(/^\/api\/groups\/([^/]+)\/messages\/search$/);
      if (method === "GET" && groupMessageSearchMatch) {
        const groupId = groupMessageSearchMatch[1];
        const query = (url.searchParams.get("q") || "").trim();
        if (query.length < 2 || query.length > 100) {
          return json({ error: "Search query must be between 2 and 100 characters" }, 400);
        }
        const before = url.searchParams.get("before");
        const beforeId = url.searchParams.get("beforeId");
        if ((before && (!beforeId || before.length > 64 || beforeId.length > 128)) ||
            (!before && beforeId)) return json({ error: "Invalid search cursor" }, 400);
        const member = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, currentUser.sub).first();
        if (!member) return json({ error: "Group not found" }, 404);
        if (!(await consumeLoginAttempt(env, "message-search-group", currentUser.sub + ":" + groupId, 40))) {
          return new Response(JSON.stringify({ error: "Too many message searches. Please try again in 15 minutes." }), {
            status: 429, headers: { ...corsHeaders, "Retry-After": "900" }
          });
        }
        const requestedLimit = Number(url.searchParams.get("limit") || 30);
        const limit = Number.isInteger(requestedLimit) ? Math.min(50, Math.max(1, requestedLimit)) : 30;
        const cursorClause = before ? "AND (gm.created_at < ? OR (gm.created_at = ? AND gm.id < ?))" : "";
        await ensureProfilePhotos(env);
        const statement = env.DB.prepare(`
          SELECT gm.id, gm.group_id, gm.sender_id, gm.body, gm.created_at,
                 gm.reply_to_id, gm.reply_to_body, gm.reply_to_sender_id, gm.edited_at,
                 u.username, u.display_name, p.updated_at AS photo_updated_at
          FROM group_messages gm
          JOIN users u ON u.id = gm.sender_id
          LEFT JOIN profile_photos p ON p.user_id = gm.sender_id
          WHERE gm.group_id = ? AND instr(lower(gm.body), lower(?)) > 0 ${cursorClause}
          ORDER BY gm.created_at DESC, gm.id DESC
          LIMIT ?
        `);
        const result = before
          ? await statement.bind(groupId, query, before, before, beforeId, limit + 1).all()
          : await statement.bind(groupId, query, limit + 1).all();
        const rows = result.results || [];
        const hasMore = rows.length > limit;
        const messages = hasMore ? rows.slice(0, limit) : rows;
        const oldest = messages[messages.length - 1];
        return json({
          messages, query, hasMore,
          nextCursor: hasMore && oldest ? { before: oldest.created_at, beforeId: oldest.id } : null
        });
      }


      // On-demand group summary. Membership is checked before reading any message.
      const groupSummaryMatch = path.match(/^\/api\/groups\/([^/]+)\/summary$/);
      if (method === "POST" && groupSummaryMatch) {
        const groupId = groupSummaryMatch[1];
        const member = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, currentUser.sub).first();
        if (!member) return json({ error: "Group not found" }, 404);
        if (!(await consumeLoginAttempt(env, "conversation-summary", currentUser.sub, 5))) {
          return json({ error: "تم بلوغ حد الملخصات؛ حاول بعد 15 دقيقة." }, 429);
        }
        const result = await env.DB.prepare(`
          SELECT gm.sender_id, u.display_name, gm.body, gm.created_at
          FROM group_messages gm
          JOIN users u ON u.id = gm.sender_id
          WHERE gm.group_id = ?
          ORDER BY gm.created_at DESC, gm.id DESC
          LIMIT 60
        `).bind(groupId).all();
        return createConversationSummary(env, result.results || [], "محادثة جماعية");
      }

      const groupMessagesMatch = path.match(/^\/api\/groups\/([^/]+)\/messages$/);
      if (groupMessagesMatch) {
        const groupId = groupMessagesMatch[1];
        const member = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, currentUser.sub).first();
        if (!member) return json({ error: "Group not found" }, 404);
        if (method === "GET") {
          const requestedLimit = Number(url.searchParams.get("limit") || 100);
          const limit = Number.isInteger(requestedLimit)
            ? Math.min(100, Math.max(1, requestedLimit)) : 100;
          const before = url.searchParams.get("before");
          const beforeId = url.searchParams.get("beforeId");
          if ((before && (!beforeId || before.length > 64 || beforeId.length > 128)) ||
              (!before && beforeId)) {
            return json({ error: "Invalid message cursor" }, 400);
          }
          const cursorClause = before ? "AND (gm.created_at < ? OR (gm.created_at = ? AND gm.id < ?))" : "";
          await ensureProfilePhotos(env);
          const statement = env.DB.prepare(`
            SELECT * FROM (
              SELECT gm.id, gm.group_id, gm.sender_id, gm.body, gm.created_at,
                     gm.reply_to_id, gm.reply_to_body, gm.reply_to_sender_id, gm.edited_at,
                     u.username, u.display_name, p.updated_at AS photo_updated_at
              FROM group_messages gm
              JOIN users u ON u.id = gm.sender_id
              LEFT JOIN profile_photos p ON p.user_id = u.id
              WHERE gm.group_id = ? ${cursorClause}
              ORDER BY gm.created_at DESC, gm.id DESC
              LIMIT ?
            )
            ORDER BY created_at ASC, id ASC
          `);
          const result = before
            ? await statement.bind(groupId, before, before, beforeId, limit + 1).all()
            : await statement.bind(groupId, limit + 1).all();
          const rows = result.results || [];
          const hasMore = rows.length > limit;
          const messages = hasMore ? rows.slice(1) : rows;
          if (messages.length) {
            const ids = messages.map(item => item.id);
            const placeholders = ids.map(() => "?").join(",");
            const [reactionRows, pinRows] = await Promise.all([
              env.DB.prepare(`SELECT mr.message_id, mr.emoji, mr.user_id, u.display_name
                FROM message_reactions mr JOIN users u ON u.id = mr.user_id
                WHERE mr.scope_type = 'group' AND scope_id = ? AND message_id IN (${placeholders})`)
                .bind(groupId, ...ids).all(),
              env.DB.prepare(`SELECT message_id FROM pinned_messages
                WHERE scope_type = 'group' AND scope_id = ? AND pinned_by = ? AND message_id IN (${placeholders})`)
                .bind(groupId, currentUser.sub, ...ids).all()
            ]);
            const reactionMap = new Map();
            for (const reaction of reactionRows.results || []) {
              if (!reactionMap.has(reaction.message_id)) reactionMap.set(reaction.message_id, []);
              reactionMap.get(reaction.message_id).push({ emoji: reaction.emoji, user_id: reaction.user_id, display_name: reaction.display_name });
            }
            const pinnedIds = new Set((pinRows.results || []).map(item => item.message_id));
            for (const item of messages) {
              item.reactions = reactionMap.get(item.id) || [];
              item.is_pinned = pinnedIds.has(item.id);
            }
          }
          const oldest = messages[0];
          return json({
            messages,
            hasMore,
            nextCursor: hasMore && oldest
              ? { before: oldest.created_at, beforeId: oldest.id } : null
          });
        }
        if (method === "POST") {
          const body = await readJsonRequestLimited(request);
          const message = String(body.body || "").trim();
          if (!message || message.length > 5000) return json({ error: "Invalid message" }, 400);
          const replyToId = body.replyToId == null ? "" : String(body.replyToId).trim();
          let reply = { id: null, body: null, sender_id: null };
          if (replyToId) {
            if (replyToId.length > 128) return json({ error: "Invalid reply target" }, 400);
            const target = await env.DB.prepare(
              "SELECT id, body, sender_id FROM group_messages WHERE id = ? AND group_id = ?"
            ).bind(replyToId, groupId).first();
            if (!target) return json({ error: "Reply target not found in this group" }, 404);
            reply = { id: target.id, body: String(target.body || "").slice(0, 500), sender_id: target.sender_id };
          }
          const id = crypto.randomUUID();
          await env.DB.prepare(
            `INSERT INTO group_messages
             (id, group_id, sender_id, body, reply_to_id, reply_to_body, reply_to_sender_id)
             VALUES (?, ?, ?, ?, ?, ?, ?)`
          ).bind(id, groupId, currentUser.sub, message, reply.id, reply.body, reply.sender_id).run();
          try {
            const [group, recipients, sender] = await Promise.all([
              env.DB.prepare("SELECT name FROM chat_groups WHERE id = ?").bind(groupId).first(),
              env.DB.prepare("SELECT user_id FROM group_members WHERE group_id = ? AND user_id != ?")
                .bind(groupId, currentUser.sub).all(),
              env.DB.prepare("SELECT display_name FROM users WHERE id = ?").bind(currentUser.sub).first()
            ]);
            await Promise.all((recipients.results || []).map(item =>
              sendSirajPush(
                env, item.user_id, currentUser.sub,
                sender?.display_name || "مستخدم برق", message,
                { category: "groups", groupId, groupName: group?.name || "مجموعة برق" }
              )
            ));
          } catch (notificationError) {
            console.error("Group message notification dispatch failed:", notificationError);
          }
          return json({ message: "Message sent", id }, 201);
        }
      }

      // Send message
      if (method === "POST" && path === "/api/messages") {
        const body = await readJsonRequestLimited(request);

        const receiverId = String(body.receiverId || "").trim();
        const message = String(body.body || "").trim();

        if (!receiverId || !message) {
          return json({
            error: "Receiver and message are required"
          }, 400);
        }

        if (message.length > 5000) {
          return json({ error: "Message is too long" }, 400);
        }

        if (receiverId === currentUser.sub) {
          return json({ error: "Cannot message yourself" }, 400);
        }

        const friendship = await env.DB.prepare(
          `SELECT 1 FROM friendships
           WHERE user_id = ? AND friend_id = ?`
        ).bind(currentUser.sub, receiverId).first();

        if (!friendship) {
          return json({
            error: "You can only message friends"
          }, 403);
        }

        // The Android offline outbox retries with the same 128-bit client ID.
        // Persist that ID as the message primary key so a lost HTTP response
        // cannot create duplicate messages when the outbox retries.
        const clientMessageId = body.clientMessageId == null
          ? "" : String(body.clientMessageId).trim().toLowerCase();
        if (clientMessageId && !/^[a-f0-9]{32}$/.test(clientMessageId)) {
          return json({ error: "Invalid client message ID" }, 400);
        }
        const id = clientMessageId || crypto.randomUUID();

        const replyToId = body.replyToId == null ? "" : String(body.replyToId).trim();
        let reply = { id: null, body: null, sender_id: null };
        if (replyToId) {
          if (replyToId.length > 128) return json({ error: "Invalid reply target" }, 400);
          const target = await env.DB.prepare(
            `SELECT id, body, sender_id FROM messages
             WHERE id = ? AND (
               (sender_id = ? AND receiver_id = ?) OR
               (sender_id = ? AND receiver_id = ?)
             )`
          ).bind(replyToId, currentUser.sub, receiverId, receiverId, currentUser.sub).first();
          if (!target) return json({ error: "Reply target not found in this conversation" }, 404);
          reply = { id: target.id, body: String(target.body || "").slice(0, 500), sender_id: target.sender_id };
        }

        const inserted = await env.DB.prepare(
          `INSERT INTO messages
           (id, sender_id, receiver_id, body, reply_to_id, reply_to_body, reply_to_sender_id)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(id) DO NOTHING`
        ).bind(id, currentUser.sub, receiverId, message, reply.id, reply.body, reply.sender_id).run();

        if (Number(inserted?.meta?.changes || 0) === 0) {
          const existing = await env.DB.prepare(
            "SELECT sender_id, receiver_id, body, reply_to_id FROM messages WHERE id = ?"
          ).bind(id).first();
          if (!existing || existing.sender_id !== currentUser.sub ||
              existing.receiver_id !== receiverId || existing.body !== message ||
              (existing.reply_to_id || "") !== (reply.id || "")) {
            return json({ error: "Client message ID conflict" }, 409);
          }
          return json({ message: "Message already accepted", id, duplicate: true });
        }

        // Message persistence is authoritative; sender lookup or push delivery
        // must not turn a successfully stored message into an apparent failure.
        try {
          const sender = await env.DB.prepare(
            "SELECT display_name FROM users WHERE id = ?"
          ).bind(currentUser.sub).first();
          await sendSirajPush(
            env, receiverId, currentUser.sub,
            sender?.display_name || currentUser.username, message
          );
        } catch (notificationError) {
          console.error("Private message notification dispatch failed:", notificationError);
        }

        return json({
          message: "Message sent",
          id
        }, 201);
      }


      // On-demand private conversation summary. Only the two current contacts may request it.
      const privateSummaryMatch = path.match(/^\/api\/messages\/([^/]+)\/summary$/);
      if (method === "POST" && privateSummaryMatch) {
        let friendId;
        try { friendId = decodeURIComponent(privateSummaryMatch[1]); } catch (_) {
          return json({ error: "Invalid conversation identifier" }, 400);
        }
        if (!friendId || friendId.length > 128 || friendId === currentUser.sub) {
          return json({ error: "Invalid conversation identifier" }, 400);
        }
        const friendship = await env.DB.prepare(
          "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
        ).bind(currentUser.sub, friendId).first();
        if (!friendship) return json({ error: "Conversation access denied" }, 403);
        if (!(await consumeLoginAttempt(env, "conversation-summary", currentUser.sub, 5))) {
          return json({ error: "تم بلوغ حد الملخصات؛ حاول بعد 15 دقيقة." }, 429);
        }
        const result = await env.DB.prepare(`
          SELECT m.sender_id, u.display_name, m.body, m.created_at
          FROM messages m
          JOIN users u ON u.id = m.sender_id
          WHERE (m.sender_id = ? AND m.receiver_id = ?)
             OR (m.sender_id = ? AND m.receiver_id = ?)
          ORDER BY m.created_at DESC, m.id DESC
          LIMIT 60
        `).bind(currentUser.sub, friendId, friendId, currentUser.sub).all();
        return createConversationSummary(env, result.results || [], "محادثة فردية");
      }

      // Private reactions and pins are scoped to the two participants only.
      const privateInteractionMatch = path.match(/^\/api\/messages\/([^/]+)\/(reactions|pin)$/);
      if (privateInteractionMatch && (method === "POST" || method === "DELETE")) {
        const messageId = privateInteractionMatch[1];
        const action = privateInteractionMatch[2];
        const target = await env.DB.prepare(
          "SELECT sender_id, receiver_id FROM messages WHERE id = ? AND (sender_id = ? OR receiver_id = ?)"
        ).bind(messageId, currentUser.sub, currentUser.sub).first();
        if (!target) return json({ error: "Message not found" }, 404);
        const peerId = target.sender_id === currentUser.sub ? target.receiver_id : target.sender_id;
        const friendship = await env.DB.prepare(
          "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
        ).bind(currentUser.sub, peerId).first();
        if (!friendship) return json({ error: "Conversation access denied" }, 403);
        const scopeId = [target.sender_id, target.receiver_id].sort().join(":");
        if (action === "reactions") {
          const allowed = ["👍", "❤️", "😂", "😮", "😢", "😡", "🎉", "🔥"];
          const body = method === "POST" ? await readJsonRequestLimited(request) : null;
          const emoji = method === "POST" ? String(body.emoji || "") : (url.searchParams.get("emoji") || "");
          if (!allowed.includes(emoji)) return json({ error: "Unsupported reaction" }, 400);
          if (method === "POST") {
            await env.DB.prepare(
              "INSERT OR IGNORE INTO message_reactions (scope_type, scope_id, message_id, user_id, emoji) VALUES ('private', ?, ?, ?, ?)"
            ).bind(scopeId, messageId, currentUser.sub, emoji).run();
          } else {
            await env.DB.prepare(
              "DELETE FROM message_reactions WHERE scope_type = 'private' AND scope_id = ? AND message_id = ? AND user_id = ? AND emoji = ?"
            ).bind(scopeId, messageId, currentUser.sub, emoji).run();
          }
          return json({ message: "Reaction updated", messageId, emoji, active: method === "POST" });
        }
        if (method === "POST") {
          await env.DB.prepare(
            "INSERT OR IGNORE INTO pinned_messages (scope_type, scope_id, message_id, pinned_by) VALUES ('private', ?, ?, ?)"
          ).bind(scopeId, messageId, currentUser.sub).run();
        } else {
          await env.DB.prepare(
            "DELETE FROM pinned_messages WHERE scope_type = 'private' AND scope_id = ? AND message_id = ? AND pinned_by = ?"
          ).bind(scopeId, messageId, currentUser.sub).run();
        }
        return json({ message: method === "POST" ? "Message pinned" : "Pin removed", messageId, pinned: method === "POST" });
      }

      // A sender may delete only their own private message.
      const privateMessageActionMatch = path.match(/^\/api\/messages\/([^/]+)$/);
      if ((method === "DELETE" || method === "PATCH") && privateMessageActionMatch) {
        const messageId = privateMessageActionMatch[1];
        const owned = await env.DB.prepare(
          "SELECT id FROM messages WHERE id = ? AND sender_id = ?"
        ).bind(messageId, currentUser.sub).first();
        if (!owned) return json({ error: "Message not found or cannot be changed" }, 404);
        if (method === "PATCH") {
          const body = await readJsonRequestLimited(request);
          const message = String(body.body || "").trim();
          if (!message || message.length > 5000) return json({ error: "Invalid message" }, 400);
          await env.DB.prepare(
            "UPDATE messages SET body = ?, edited_at = CURRENT_TIMESTAMP WHERE id = ? AND sender_id = ?"
          ).bind(message, messageId, currentUser.sub).run();
          return json({ message: "Message updated", id: messageId, body: message, editedAt: true });
        }
        await env.DB.prepare(
          "DELETE FROM messages WHERE id = ? AND sender_id = ?"
        ).bind(messageId, currentUser.sub).run();
        return json({ message: "Message deleted", id: messageId });
      }

      // Search only within the authenticated private conversation.
      if (method === "GET" && path === "/api/messages/search") {
        const friendId = (url.searchParams.get("with") || "").trim();
        const query = (url.searchParams.get("q") || "").trim();
        if (!friendId) return json({ error: "Friend ID is required" }, 400);
        if (query.length < 2 || query.length > 100) {
          return json({ error: "Search query must be between 2 and 100 characters" }, 400);
        }
        const before = url.searchParams.get("before");
        const beforeId = url.searchParams.get("beforeId");
        if ((before && (!beforeId || before.length > 64 || beforeId.length > 128)) ||
            (!before && beforeId)) return json({ error: "Invalid search cursor" }, 400);
        const friendship = await env.DB.prepare(
          "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
        ).bind(currentUser.sub, friendId).first();
        if (!friendship) return json({ error: "You can only search chats with friends" }, 403);
        if (!(await consumeLoginAttempt(env, "message-search-private", currentUser.sub + ":" + friendId, 40))) {
          return new Response(JSON.stringify({ error: "Too many message searches. Please try again in 15 minutes." }), {
            status: 429, headers: { ...corsHeaders, "Retry-After": "900" }
          });
        }
        const requestedLimit = Number(url.searchParams.get("limit") || 30);
        const limit = Number.isInteger(requestedLimit) ? Math.min(50, Math.max(1, requestedLimit)) : 30;
        const cursorClause = before ? "AND (m.created_at < ? OR (m.created_at = ? AND m.id < ?))" : "";
        const statement = env.DB.prepare(`
          SELECT m.id, m.sender_id, m.receiver_id, m.body, m.created_at, m.read_at,
                 m.reply_to_id, m.reply_to_body, m.reply_to_sender_id, m.edited_at,
                 u.display_name, u.username
          FROM messages m
          JOIN users u ON u.id = m.sender_id
          WHERE ((m.sender_id = ? AND m.receiver_id = ?)
              OR (m.sender_id = ? AND m.receiver_id = ?))
            AND instr(lower(m.body), lower(?)) > 0 ${cursorClause}
          ORDER BY m.created_at DESC, m.id DESC
          LIMIT ?
        `);
        const result = before
          ? await statement.bind(currentUser.sub, friendId, friendId, currentUser.sub, query, before, before, beforeId, limit + 1).all()
          : await statement.bind(currentUser.sub, friendId, friendId, currentUser.sub, query, limit + 1).all();
        const rows = result.results || [];
        const hasMore = rows.length > limit;
        const messages = hasMore ? rows.slice(0, limit) : rows;
        const oldest = messages[messages.length - 1];
        return json({
          messages, query, hasMore,
          nextCursor: hasMore && oldest ? { before: oldest.created_at, beforeId: oldest.id } : null
        });
      }

      // Get conversation messages
      if (method === "GET" && path === "/api/messages") {
        const friendId = (
          url.searchParams.get("with") || ""
        ).trim();

        if (!friendId) {
          return json({
            error: "Friend ID is required"
          }, 400);
        }

        const friendship = await env.DB.prepare(
          `SELECT 1 FROM friendships
           WHERE user_id = ? AND friend_id = ?`
        ).bind(currentUser.sub, friendId).first();

        if (!friendship) {
          return json({
            error: "You can only view chats with friends"
          }, 403);
        }

        const requestedLimit = Number(url.searchParams.get("limit") || 100);
        const limit = Number.isInteger(requestedLimit)
          ? Math.min(100, Math.max(1, requestedLimit)) : 100;
        const before = url.searchParams.get("before");
        const beforeId = url.searchParams.get("beforeId");
        if ((before && (!beforeId || before.length > 64 || beforeId.length > 128)) ||
            (!before && beforeId)) {
          return json({ error: "Invalid message cursor" }, 400);
        }
        const cursorClause = before
          ? "AND (created_at < ? OR (created_at = ? AND id < ?))" : "";
        const result = before
          ? await env.DB.prepare(
              `SELECT * FROM (
                 SELECT id, sender_id, receiver_id, body, created_at, read_at,
                        reply_to_id, reply_to_body, reply_to_sender_id, edited_at
                 FROM messages
                 WHERE ((sender_id = ? AND receiver_id = ?)
                    OR (sender_id = ? AND receiver_id = ?))
                   ${cursorClause}
                 ORDER BY created_at DESC, id DESC
                 LIMIT ?
               )
               ORDER BY created_at ASC, id ASC`
            ).bind(currentUser.sub, friendId, friendId, currentUser.sub,
              before, before, beforeId, limit + 1).all()
          : await env.DB.prepare(
              `SELECT * FROM (
                 SELECT id, sender_id, receiver_id, body, created_at, read_at,
                        reply_to_id, reply_to_body, reply_to_sender_id, edited_at
                 FROM messages
                 WHERE (sender_id = ? AND receiver_id = ?)
                    OR (sender_id = ? AND receiver_id = ?)
                 ORDER BY created_at DESC, id DESC
                 LIMIT ?
               )
               ORDER BY created_at ASC, id ASC`
            ).bind(currentUser.sub, friendId, friendId, currentUser.sub, limit + 1).all();

        const rows = result.results || [];
        const hasMore = rows.length > limit;
        const messages = hasMore ? rows.slice(1) : rows;

        // Only mark messages in the page actually returned to this reader.
        // Older pages are marked when they are fetched, not prematurely.
        const privacy = await env.DB.prepare(
          "SELECT read_receipts FROM user_privacy WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        if ((!privacy || privacy.read_receipts === 1) && messages.length) {
          const ids = messages.filter(item =>
            item.sender_id === friendId && item.receiver_id === currentUser.sub && !item.read_at
          ).map(item => item.id);
          if (ids.length) {
            await env.DB.prepare(
              `UPDATE messages SET read_at = CURRENT_TIMESTAMP
               WHERE sender_id = ? AND receiver_id = ? AND read_at IS NULL
                 AND id IN (${ids.map(() => "?").join(", ")})`
            ).bind(friendId, currentUser.sub, ...ids).run();
          }
        }

        if (messages.length) {
          const ids = messages.map(item => item.id);
          const placeholders = ids.map(() => "?").join(",");
          const scopeId = [currentUser.sub, friendId].sort().join(":");
          const [reactionRows, pinRows] = await Promise.all([
            env.DB.prepare(`SELECT mr.message_id, mr.emoji, mr.user_id, u.display_name
              FROM message_reactions mr JOIN users u ON u.id = mr.user_id
              WHERE mr.scope_type = 'private' AND scope_id = ? AND message_id IN (${placeholders})`)
              .bind(scopeId, ...ids).all(),
            env.DB.prepare(`SELECT message_id FROM pinned_messages
              WHERE scope_type = 'private' AND scope_id = ? AND pinned_by = ? AND message_id IN (${placeholders})`)
              .bind(scopeId, currentUser.sub, ...ids).all()
          ]);
          const reactionMap = new Map();
          for (const reaction of reactionRows.results || []) {
            if (!reactionMap.has(reaction.message_id)) reactionMap.set(reaction.message_id, []);
            reactionMap.get(reaction.message_id).push({ emoji: reaction.emoji, user_id: reaction.user_id, display_name: reaction.display_name });
          }
          const pinnedIds = new Set((pinRows.results || []).map(item => item.message_id));
          for (const item of messages) {
            item.reactions = reactionMap.get(item.id) || [];
            item.is_pinned = pinnedIds.has(item.id);
          }
        }
        const oldest = messages[0];
        return json({
          messages,
          hasMore,
          nextCursor: hasMore && oldest
            ? { before: oldest.created_at, beforeId: oldest.id } : null
        });
      }

      // Private media storage backed by the existing Tigris bucket (S3-compatible).
      if (path === "/api/media" && method === "POST") {
        if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
          return json({ error: "Media storage credentials are not configured" }, 503);
        }
        const recipientId = (request.headers.get("X-Recipient-Id") || "").trim();
        const groupId = (request.headers.get("X-Group-Id") || "").trim();
        if ((recipientId ? 1 : 0) + (groupId ? 1 : 0) !== 1) {
          return json({ error: "Choose one conversation destination" }, 400);
        }
        if (recipientId) {
          const friendship = await env.DB.prepare(
            "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
          ).bind(currentUser.sub, recipientId).first();
          if (!friendship) return json({ error: "Contact not found" }, 403);
        } else {
          const member = await env.DB.prepare(
            "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
          ).bind(groupId, currentUser.sub).first();
          if (!member) return json({ error: "Group not found" }, 404);
        }
        const contentType = (request.headers.get("Content-Type") || "application/octet-stream").split(";")[0].toLowerCase();
        const allowedTypes = /^(image\/(jpeg|png|webp|gif)|video\/(mp4|webm|quicktime)|audio\/(mpeg|mp4|aac|wav|ogg|webm)|application\/(octet-stream|pdf|zip|msword|vnd\.ms-excel|vnd\.ms-powerpoint|vnd\.openxmlformats-officedocument\.[a-z0-9.]+)|text\/plain)$/;
        if (!allowedTypes.test(contentType)) return json({ error: "Unsupported media type" }, 415);
        const maxMediaBytes = 60 * 1024 * 1024;
        const declaredLength = Number(request.headers.get("Content-Length"));
        // Reject oversized uploads before buffering their body in Worker memory.
        if (Number.isFinite(declaredLength) && declaredLength > maxMediaBytes) {
          return json({ error: "File must be between 1 byte and 60 MB" }, 413);
        }
        const bytes = await readRequestBodyLimited(request, maxMediaBytes);
        if (!bytes || !bytes.byteLength) {
          return json({ error: "File must be between 1 byte and 60 MB" }, 413);
        }
        const suppliedName = safeFileName(request.headers.get("X-File-Name") || "attachment");
        const id = crypto.randomUUID();
        const key = currentUser.sub + "/" + id;
        const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString();
        await env.DB.prepare("CREATE TABLE IF NOT EXISTS media_expirations (object_key TEXT PRIMARY KEY, expires_at TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)").run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS media_access (
            object_key TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL,
            recipient_id TEXT,
            group_id TEXT,
            file_name TEXT NOT NULL,
            content_type TEXT NOT NULL,
            expires_at TEXT NOT NULL
          )
        `).run();
        const bucket = env.TIGRIS_BUCKET || "siraj-media";
        const objectPath = key.split("/").map(encodeURIComponent).join("/");
        const storageUrl = "https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + objectPath;
        const storage = new AwsClient({
          accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
          secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
          service: "s3",
          region: "auto",
          retries: 2
        });
        const putResponse = await storage.fetch(storageUrl, {
          method: "PUT",
          headers: {
            "Content-Type": contentType,
            "x-amz-meta-ownerid": currentUser.sub,
            "x-amz-meta-recipientid": recipientId,
            "x-amz-meta-groupid": groupId,
            "x-amz-meta-filename": encodeURIComponent(suppliedName),
            "x-amz-meta-contenttype": contentType,
            "x-amz-meta-expiresat": expiresAt
          },
          body: bytes
        });
        if (!putResponse.ok) {
          return json({ error: "Media storage upload failed", storageStatus: putResponse.status }, 502);
        }
        const attachmentBody = JSON.stringify({
          type: "attachment",
          attachmentId: key,
          fileName: suppliedName,
          contentType,
          size: bytes.byteLength
        });
        const messageId = crypto.randomUUID();
        try {
          await env.DB.prepare(
            "INSERT INTO media_expirations (object_key, expires_at) VALUES (?, ?)"
          ).bind(key, expiresAt).run();
          await env.DB.prepare(
            "INSERT INTO media_access (object_key, owner_id, recipient_id, group_id, file_name, content_type, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?)"
          ).bind(key, currentUser.sub, recipientId || null, groupId || null, suppliedName, contentType, expiresAt).run();
          if (recipientId) {
            await env.DB.prepare(
              "INSERT INTO messages (id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)"
            ).bind(messageId, currentUser.sub, recipientId, attachmentBody).run();
          } else {
            await env.DB.prepare(
              "INSERT INTO group_messages (id, group_id, sender_id, body) VALUES (?, ?, ?, ?)"
            ).bind(messageId, groupId, currentUser.sub, attachmentBody).run();
          }
        } catch (error) {
          // Revoke access immediately. Keep the expiration record unless storage confirms
          // deletion so the scheduled cleanup can retry an object that could not be removed.
          let objectDeleted = false;
          try {
            const deleteResponse = await storage.fetch(storageUrl, { method: "DELETE" });
            objectDeleted = deleteResponse.ok || deleteResponse.status === 404;
          } catch (_) {}
          try {
            await env.DB.prepare("DELETE FROM media_access WHERE object_key = ?").bind(key).run();
            if (objectDeleted) {
              await env.DB.prepare("DELETE FROM media_expirations WHERE object_key = ?").bind(key).run();
            }
          } catch (_) {}
          throw error;
        }

        // Deliver the same push notification behavior for attachment messages as for text.
        // Notification failures must never undo a successfully stored attachment message.
        try {
          const sender = await env.DB.prepare(
            "SELECT display_name FROM users WHERE id = ?"
          ).bind(currentUser.sub).first();
          const senderName = sender?.display_name || currentUser.username || "مستخدم برق";
          if (recipientId) {
            await sendSirajPush(env, recipientId, currentUser.sub, senderName, "أرسل مرفقًا");
          } else {
            const [group, recipients] = await Promise.all([
              env.DB.prepare("SELECT name FROM chat_groups WHERE id = ?").bind(groupId).first(),
              env.DB.prepare("SELECT user_id FROM group_members WHERE group_id = ? AND user_id != ?")
                .bind(groupId, currentUser.sub).all()
            ]);
            await Promise.all((recipients.results || []).map(item =>
              sendSirajPush(env, item.user_id, currentUser.sub, senderName, "أرسل مرفقًا", {
                category: "groups",
                groupId,
                groupName: group?.name || "مجموعة برق"
              })
            ));
          }
        } catch (notificationError) {
          console.error("Attachment notification dispatch failed:", notificationError);
        }

        return json({ attachment: { id: key, fileName: suppliedName, contentType, size: bytes.byteLength }, messageId }, 201);
      }

      const mediaMatch = path.match(/^\/api\/media\/(.+)$/);
      if (mediaMatch && method === "GET") {
        if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
          return json({ error: "Media storage credentials are not configured" }, 503);
        }
        let key;
        try { key = decodeURIComponent(mediaMatch[1]); } catch (_) {
          return json({ error: "Invalid attachment identifier" }, 400);
        }
        if (!key || key.length > 512 || key.startsWith("/") || key.includes("\\\\") ||
            key.split("/").some(part => !part || part === "." || part === "..")) {
          return json({ error: "Invalid attachment identifier" }, 400);
        }
        const bucket = env.TIGRIS_BUCKET || "siraj-media";
        const objectPath = key.split("/").map(encodeURIComponent).join("/");
        const storageUrl = "https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + objectPath;
        const storage = new AwsClient({
          accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
          secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
          service: "s3",
          region: "auto",
          retries: 2
        });
        // New uploads have an authorization record in D1, allowing access checks
        // before any request is made to object storage. Legacy objects fall back
        // to their existing signed metadata until they naturally expire.
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS media_access (
            object_key TEXT PRIMARY KEY,
            owner_id TEXT NOT NULL,
            recipient_id TEXT,
            group_id TEXT,
            file_name TEXT NOT NULL,
            content_type TEXT NOT NULL,
            expires_at TEXT NOT NULL
          )
        `).run();
        const accessRow = await env.DB.prepare(
          "SELECT owner_id, recipient_id, group_id, file_name, content_type, expires_at FROM media_access WHERE object_key = ?"
        ).bind(key).first();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_posts (
            id TEXT PRIMARY KEY, user_id TEXT NOT NULL, content TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, expires_at TEXT NOT NULL,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS status_media (
            id TEXT PRIMARY KEY, status_id TEXT NOT NULL, object_key TEXT NOT NULL UNIQUE,
            file_name TEXT NOT NULL, content_type TEXT NOT NULL,
            size INTEGER NOT NULL, caption TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (status_id) REFERENCES status_posts(id) ON DELETE CASCADE
          )
        `).run();
        const sparkMedia = await env.DB.prepare(
          `SELECT sm.status_id AS statusId, sp.user_id AS ownerId, sp.expires_at AS expiresAt
           FROM status_media sm JOIN status_posts sp ON sp.id = sm.status_id
           WHERE sm.object_key = ? LIMIT 1`
        ).bind(key).first();
        let permitted = false;
        if (sparkMedia) {
          // Expiry applies to the owner too: possession of the original status
          // must never keep its media readable after the 24-hour lifetime.
          const sparkExpiry = Date.parse(sparkMedia.expiresAt);
          if (!Number.isFinite(sparkExpiry) || sparkExpiry <= Date.now()) {
            return json({ error: "SPARK media not found or expired" }, 410);
          }
          permitted = sparkMedia.ownerId === currentUser.sub;
          if (!permitted) {
            const friendship = await env.DB.prepare(
              `SELECT 1 FROM friendships f
               WHERE f.user_id = ? AND f.friend_id = ?
                 AND EXISTS (
                   SELECT 1 FROM friendships reciprocal
                   WHERE reciprocal.user_id = ? AND reciprocal.friend_id = ?
                 )`
            ).bind(currentUser.sub, sparkMedia.ownerId, sparkMedia.ownerId, currentUser.sub).first();
            permitted = !!friendship;
          }
          if (!permitted) return json({ error: "SPARK media access denied" }, 403);
        }
        if (accessRow && !sparkMedia) {
          permitted = accessRow.owner_id === currentUser.sub;
          if (!permitted && accessRow.recipient_id === currentUser.sub && accessRow.owner_id) {
            const friendship = await env.DB.prepare(
              "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
            ).bind(currentUser.sub, accessRow.owner_id).first();
            permitted = !!friendship;
          }
          if (!permitted && accessRow.group_id) {
            const member = await env.DB.prepare(
              "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
            ).bind(accessRow.group_id, currentUser.sub).first();
            permitted = !!member;
          }
          if (!permitted) return json({ error: "Attachment access denied" }, 403);
        }
        const headResponse = await storage.fetch(storageUrl, { method: "HEAD" });
        if (headResponse.status === 404) return json({ error: "Attachment not found" }, 404);
        if (!headResponse.ok) return json({ error: "Media storage lookup failed", storageStatus: headResponse.status }, 502);
        if (!accessRow && !sparkMedia) {
          const ownerId = headResponse.headers.get("x-amz-meta-ownerid") || "";
          const recipientId = headResponse.headers.get("x-amz-meta-recipientid") || "";
          const groupId = headResponse.headers.get("x-amz-meta-groupid") || "";
          permitted = ownerId === currentUser.sub;
          if (!permitted && recipientId === currentUser.sub && ownerId) {
            const friendship = await env.DB.prepare(
              "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
            ).bind(currentUser.sub, ownerId).first();
            permitted = !!friendship;
          }
          if (!permitted && groupId) {
            const member = await env.DB.prepare(
              "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
            ).bind(groupId, currentUser.sub).first();
            permitted = !!member;
          }
          if (!permitted) return json({ error: "Attachment access denied" }, 403);
        }
        // Check expiry only after authorization so an unrelated account cannot
        // trigger deletion of another user's object by guessing its identifier.
        const expiresAt = sparkMedia?.expiresAt || accessRow?.expires_at || headResponse.headers.get("x-amz-meta-expiresat");
        if (expiresAt && Number.isFinite(Date.parse(expiresAt)) && Date.parse(expiresAt) <= Date.now()) {
          try {
            const deletion = await storage.fetch(storageUrl, { method: "DELETE" });
            // Keep the expiration row when storage deletion fails so the scheduled
            // cleanup can retry instead of permanently orphaning the object.
            if (deletion.ok || deletion.status === 404) {
              await env.DB.prepare("DELETE FROM media_access WHERE object_key = ?").bind(key).run();
              await env.DB.prepare("DELETE FROM media_expirations WHERE object_key = ? AND expires_at <= ?")
                .bind(key, new Date().toISOString()).run();
            } else {
              console.error("Expired attachment deletion failed:", deletion.status);
            }
          } catch (deletionError) {
            console.error("Expired attachment deletion request failed:", deletionError);
          }
          return json({ error: "Attachment has expired" }, 410);
        }
        const storageResponse = await storage.fetch(storageUrl, { method: "GET" });
        if (storageResponse.status === 404) return json({ error: "Attachment not found" }, 404);
        if (!storageResponse.ok) return json({ error: "Media storage download failed", storageStatus: storageResponse.status }, 502);
        const headers = new Headers(corsHeaders);
        headers.set("Content-Type", headResponse.headers.get("content-type") || accessRow?.content_type || "application/octet-stream");
        const encodedName = headResponse.headers.get("x-amz-meta-filename") ||
          (accessRow?.file_name ? encodeURIComponent(accessRow.file_name) : "attachment");
        let fileName = "attachment";
        try { fileName = decodeURIComponent(encodedName); } catch (_) { fileName = encodedName; }
        headers.set("Content-Disposition", "attachment; filename*=UTF-8''" + encodeURIComponent(safeFileName(fileName)));
        headers.set("Cache-Control", "private, no-store");
        return new Response(storageResponse.body, { status: 200, headers });
      }

      return json({ error: "Route not found" }, 404);

    } catch (error) {
      if (error?.status === 413) {
        return json({ error: "JSON request body is too large" }, 413);
      }
      // Malformed client JSON is a request error, not an internal server failure.
      if (error instanceof SyntaxError) {
        return json({ error: "Invalid JSON body" }, 400);
      }

      if (
        error &&
        /UNIQUE constraint failed/i.test(error.message || "")
      ) {
        return json({
          error: "Username or phone number is already registered"
        }, 409);
      }

      return json({
        error: "Internal server error"
      }, 500);
    }
  }
};
