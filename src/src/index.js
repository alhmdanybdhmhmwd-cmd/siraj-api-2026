import { AwsClient } from "aws4fetch";


const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-File-Name, X-Recipient-Id, X-Group-Id",
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
    phone: user.phone || null
  };
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
                    ? "حالة جديدة من " + String(senderName || "مستخدم برق").slice(0, 80)
                    : "رسالة من " + String(senderName || "مستخدم برق").slice(0, 80),
                body: category === "statuses" ? "شارك حالة جديدة" : preview || "لديك رسالة جديدة"
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
  return { checked: (expired.results || []).length, deleted };
}

async function cleanupExpiredEphemeralMessages(env, now = Date.now()) {
  const cutoff = Math.floor(now / 1000);
  try {
    const result = await env.DB.prepare(
      "DELETE FROM ephemeral_messages WHERE expires_at <= ? OR (delete_at IS NOT NULL AND delete_at <= ?)"
    ).bind(cutoff, cutoff).run();
    return Number(result?.meta?.changes || 0);
  } catch (error) {
    // The table is created lazily by the authenticated endpoint.
    if (!/no such table/i.test(String(error?.message || error))) {
      console.error("Ephemeral message cleanup failed:", error);
    }
    return 0;
  }
}

async function cleanupExpiredRateLimits(env, now = Date.now()) {
  const cutoff = Math.floor(now / 1000) - 24 * 60 * 60;
  const results = {};
  for (const table of ["login_rate_limits", "recovery_rate_limits"]) {
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

export { phoneVariants, safeFileName, cleanupExpiredMedia, cleanupExpiredRateLimits };

export default {
  async scheduled(_controller, env) {
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
      const deleted = await cleanupExpiredEphemeralMessages(env);
      console.log("Ephemeral message cleanup:", deleted);
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
        const body = await request.json();

        const displayName = String(body.displayName || "").trim();
        const username = String(body.username || "").trim().toLowerCase();
        const password = String(body.password || "");
        const phone = String(body.phone || "").trim();

        if (!displayName || !username || !password) {
          return json({
            error: "Name, username and password are required"
          }, 400);
        }

        if (!/^[a-zA-Z0-9_.]{3,30}$/.test(username)) {
          return json({
            error: "Username must be 3-30 characters: letters, numbers, _ or ."
          }, 400);
        }

        if (password.length < 8 || password.length > 128) {
          return json({
            error: "Password must be 8-128 characters"
          }, 400);
        }

        if (phone.length > 25) {
          return json({ error: "Invalid phone number" }, 400);
        }
        if (phone && await phoneAlreadyInUse(env, phone)) {
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

        const id = crypto.randomUUID();
        const salt = base64url(
          crypto.getRandomValues(new Uint8Array(16))
        );

        const passwordHash = await hashPassword(password, salt);

        const recovery = await generateRecoveryCode();
        const createdAt = Math.floor(Date.now() / 1000);
        const registrationResults = await env.DB.batch([
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
        ]);
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
        const body = await request.json();
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
        const body = await request.json();

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

      // Ephemeral private messages: never write to the ordinary messages table or send FCM.
      // A message is removed ten seconds after the recipient first reads it.
      if (path === "/api/ephemeral-messages") {
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS ephemeral_messages (
            id TEXT PRIMARY KEY,
            sender_id TEXT NOT NULL,
            receiver_id TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            read_at INTEGER,
            delete_at INTEGER,
            expires_at INTEGER NOT NULL,
            FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE,
            FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
        const now = Math.floor(Date.now() / 1000);
        await env.DB.prepare(
          "DELETE FROM ephemeral_messages WHERE expires_at <= ? OR (delete_at IS NOT NULL AND delete_at <= ?)"
        ).bind(now, now).run();

        if (method === "POST") {
          const body = await request.json();
          const receiverId = String(body.receiverId || "").trim();
          const message = String(body.body || "").trim();
          if (!receiverId || receiverId === currentUser.sub || !message || message.length > 5000) {
            return json({ error: "Invalid temporary message" }, 400);
          }
          const friendship = await env.DB.prepare(
            "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
          ).bind(currentUser.sub, receiverId).first();
          if (!friendship) return json({ error: "Contact not found" }, 403);
          const id = crypto.randomUUID();
          await env.DB.prepare(
            "INSERT INTO ephemeral_messages (id, sender_id, receiver_id, body, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)"
          ).bind(id, currentUser.sub, receiverId, message, now, now + 7 * 24 * 60 * 60).run();
          // Deliberately no FCM notification and no write to messages.
          return json({ message: "Temporary message sent", id, createdAt: now }, 201);
        }

        if (method === "GET") {
          const friendId = String(url.searchParams.get("with") || "").trim();
          if (!friendId || friendId === currentUser.sub) return json({ error: "Friend ID is required" }, 400);
          const friendship = await env.DB.prepare(
            "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
          ).bind(currentUser.sub, friendId).first();
          if (!friendship) return json({ error: "Contact not found" }, 403);
          const result = await env.DB.prepare(
            `SELECT id, sender_id, receiver_id, body, created_at, read_at, delete_at
             FROM ephemeral_messages
             WHERE ((sender_id = ? AND receiver_id = ?) OR (sender_id = ? AND receiver_id = ?))
               AND expires_at > ?
               AND (delete_at IS NULL OR delete_at > ?)
             ORDER BY created_at ASC, id ASC`
          ).bind(currentUser.sub, friendId, friendId, currentUser.sub, now, now).all();
          const rows = result.results || [];
          const incomingIds = rows.filter(item =>
            item.sender_id === friendId && item.receiver_id === currentUser.sub && item.read_at == null
          ).map(item => item.id);
          if (incomingIds.length) {
            const deleteAt = now + 10;
            await env.DB.prepare(
              `UPDATE ephemeral_messages SET read_at = ?, delete_at = ?
               WHERE receiver_id = ? AND sender_id = ? AND read_at IS NULL
                 AND id IN (${incomingIds.map(() => "?").join(", ")})`
            ).bind(now, deleteAt, currentUser.sub, friendId, ...incomingIds).run();
            for (const item of rows) {
              if (incomingIds.includes(item.id)) {
                item.read_at = now;
                item.delete_at = deleteAt;
              }
            }
            // Keep the response available to the reader, then delete from D1 after ten seconds.
            if (ctx && typeof ctx.waitUntil === "function") {
              ctx.waitUntil((async () => {
                await new Promise(resolve => setTimeout(resolve, 10_100));
                const deletionTime = Math.floor(Date.now() / 1000);
                await env.DB.prepare(
                  `DELETE FROM ephemeral_messages
                   WHERE receiver_id = ? AND sender_id = ? AND delete_at IS NOT NULL AND delete_at <= ?
                     AND id IN (${incomingIds.map(() => "?").join(", ")})`
                ).bind(currentUser.sub, friendId, deletionTime, ...incomingIds).run();
              })());
            }
          }
          return json({ messages: rows });
        }
        return json({ error: "Method not allowed" }, 405);
      }

      // Rotate the one-time recovery code after verifying the current password.
      if (method === "POST" && path === "/api/recovery-code") {
        const body = await request.json();
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

      // Update current user's editable profile fields
      if (method === "POST" && path === "/api/profile") {
        const body = await request.json();
        const displayName = String(body.displayName || "").trim();
        const phone = String(body.phone || "").trim();
        if (!displayName || displayName.length > 60) {
          return json({ error: "Display name must be 1-60 characters" }, 400);
        }
        if (phone.length > 25) {
          return json({ error: "Phone number is too long" }, 400);
        }
        if (phone && await phoneAlreadyInUse(env, phone, currentUser.sub)) {
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
          "SELECT id, username, display_name, phone FROM users WHERE id = ?"
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
          const body = await request.json();
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
          const body = await request.json();
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
        const body = await request.json();
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
        const user = await env.DB.prepare(
          `SELECT id, username, display_name, phone
           FROM users WHERE id = ?`
        ).bind(currentUser.sub).first();

        if (!user) {
          return json({ error: "User not found" }, 404);
        }

        return json({ user: cleanUser(user) });
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
        const body = await request.json();
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
            "SELECT friend_id FROM friendships WHERE user_id = ?"
          ).bind(currentUser.sub).all();
          await Promise.all((recipients.results || []).map(item =>
            sendSirajPush(env, item.friend_id, currentUser.sub,
              currentUser.username, "شارك حالة جديدة", { category: "statuses" })
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

        const result = await env.DB.prepare(
          `SELECT s.id, s.user_id AS userId, u.username,
                  u.display_name AS displayName, s.content,
                  s.created_at AS createdAt, s.expires_at AS expiresAt
           FROM status_posts s
           JOIN users u ON u.id = s.user_id
           WHERE s.expires_at > CURRENT_TIMESTAMP
             AND (
               s.user_id = ?
               OR EXISTS (
                 SELECT 1 FROM friendships f
                 WHERE f.user_id = ? AND f.friend_id = s.user_id
               )
             )
           ORDER BY s.created_at DESC
           LIMIT 100`
        ).bind(currentUser.sub, currentUser.sub).all();

        return json({ statuses: result.results || [] });
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
        const body = await request.json();
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
        const body = await request.json();
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
        const friends = await env.DB.prepare(
          `SELECT u.id, u.username, u.display_name, u.phone
           FROM friendships f
           JOIN users u ON u.id = f.friend_id
           WHERE f.user_id = ?
           ORDER BY u.display_name`
        ).bind(currentUser.sub).all();

        return json({
          friends: (friends.results || []).map(cleanUser)
        });
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
        await env.DB.prepare(`
          CREATE TABLE IF NOT EXISTS group_messages (
            id TEXT PRIMARY KEY,
            group_id TEXT NOT NULL,
            sender_id TEXT NOT NULL,
            body TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            FOREIGN KEY (group_id) REFERENCES chat_groups(id) ON DELETE CASCADE,
            FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
          )
        `).run();
      }

      if (method === "GET" && path === "/api/groups") {
        const result = await env.DB.prepare(`
          SELECT g.id, g.name, g.description, g.owner_id,
                 g.created_at,
                 (SELECT COUNT(*) FROM group_members m WHERE m.group_id = g.id) AS member_count
          FROM chat_groups g
          JOIN group_members mine ON mine.group_id = g.id
          WHERE mine.user_id = ?
          ORDER BY g.created_at DESC
        `).bind(currentUser.sub).all();
        return json({ groups: result.results || [] });
      }

      if (method === "POST" && path === "/api/groups") {
        const body = await request.json();
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
        const result = await env.DB.prepare(`
          SELECT u.id, u.username, u.display_name, u.phone, m.joined_at,
                 CASE WHEN g.owner_id = u.id THEN 1 ELSE 0 END AS is_owner
          FROM group_members m
          JOIN users u ON u.id = m.user_id
          JOIN chat_groups g ON g.id = m.group_id
          WHERE m.group_id = ?
          ORDER BY is_owner DESC, u.display_name ASC
        `).bind(groupId).all();
        return json({ members: result.results || [] });
      }

      if (method === "POST" && groupMemberMatch) {
        const groupId = groupMemberMatch[1];
        const body = await request.json();
        const userId = String(body.userId || "").trim();
        // Only the group owner may add members. Membership alone must not
        // grant an account the ability to invite arbitrary users.
        const group = await env.DB.prepare(
          "SELECT owner_id FROM chat_groups WHERE id = ?"
        ).bind(groupId).first();
        if (!group) return json({ error: "Group not found" }, 404);
        if (group.owner_id !== currentUser.sub) {
          return json({ error: "Only the group owner can add members" }, 403);
        }
        const target = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(userId).first();
        if (!target) return json({ error: "User not found" }, 404);
        await env.DB.prepare(
          "INSERT OR IGNORE INTO group_members (group_id, user_id) VALUES (?, ?)"
        ).bind(groupId, userId).run();
        return json({ message: "Member added" }, 201);
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
          const statement = env.DB.prepare(`
            SELECT * FROM (
              SELECT gm.id, gm.group_id, gm.sender_id, gm.body, gm.created_at,
                     u.username, u.display_name
              FROM group_messages gm
              JOIN users u ON u.id = gm.sender_id
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
          const oldest = messages[0];
          return json({
            messages,
            hasMore,
            nextCursor: hasMore && oldest
              ? { before: oldest.created_at, beforeId: oldest.id } : null
          });
        }
        if (method === "POST") {
          const body = await request.json();
          const message = String(body.body || "").trim();
          if (!message || message.length > 5000) return json({ error: "Invalid message" }, 400);
          const id = crypto.randomUUID();
          await env.DB.prepare(
            "INSERT INTO group_messages (id, group_id, sender_id, body) VALUES (?, ?, ?, ?)"
          ).bind(id, groupId, currentUser.sub, message).run();
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
        const body = await request.json();

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

        const id = crypto.randomUUID();

        await env.DB.prepare(
          `INSERT INTO messages
           (id, sender_id, receiver_id, body)
           VALUES (?, ?, ?, ?)`
        ).bind(
          id,
          currentUser.sub,
          receiverId,
          message
        ).run();

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
                 SELECT id, sender_id, receiver_id, body, created_at, read_at
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
                 SELECT id, sender_id, receiver_id, body, created_at, read_at
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
        const bytes = await request.arrayBuffer();
        if (!bytes.byteLength || bytes.byteLength > maxMediaBytes) {
          return json({ error: "File must be between 1 byte and 60 MB" }, 413);
        }
        const suppliedName = safeFileName(request.headers.get("X-File-Name") || "attachment");
        const id = crypto.randomUUID();
        const key = currentUser.sub + "/" + id;
        const expiresAt = new Date(Date.now() + 72 * 60 * 60 * 1000).toISOString();
        await env.DB.prepare("CREATE TABLE IF NOT EXISTS media_expirations (object_key TEXT PRIMARY KEY, expires_at TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP)").run();
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
          // Avoid leaving an unreachable object or expiration record behind if persistence fails.
          try { await storage.fetch(storageUrl, { method: "DELETE" }); } catch (_) {}
          try {
            await env.DB.prepare("DELETE FROM media_expirations WHERE object_key = ?").bind(key).run();
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
        // Read only object metadata first; never download bytes before authorization.
        const headResponse = await storage.fetch(storageUrl, { method: "HEAD" });
        if (headResponse.status === 404) return json({ error: "Attachment not found" }, 404);
        if (!headResponse.ok) return json({ error: "Media storage lookup failed", storageStatus: headResponse.status }, 502);
        const ownerId = headResponse.headers.get("x-amz-meta-ownerid") || "";
        const recipientId = headResponse.headers.get("x-amz-meta-recipientid") || "";
        const groupId = headResponse.headers.get("x-amz-meta-groupid") || "";
        let permitted = ownerId === currentUser.sub;
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
        // Check expiry only after authorization so an unrelated account cannot
        // trigger deletion of another user's object by guessing its identifier.
        const expiresAt = headResponse.headers.get("x-amz-meta-expiresat");
        if (expiresAt && Number.isFinite(Date.parse(expiresAt)) && Date.parse(expiresAt) <= Date.now()) {
          try {
            const deletion = await storage.fetch(storageUrl, { method: "DELETE" });
            // Keep the expiration row when storage deletion fails so the scheduled
            // cleanup can retry instead of permanently orphaning the object.
            if (deletion.ok || deletion.status === 404) {
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
        headers.set("Content-Type", headResponse.headers.get("content-type") || "application/octet-stream");
        const encodedName = headResponse.headers.get("x-amz-meta-filename") || "attachment";
        let fileName = "attachment";
        try { fileName = decodeURIComponent(encodedName); } catch (_) { fileName = encodedName; }
        headers.set("Content-Disposition", "attachment; filename*=UTF-8''" + encodeURIComponent(safeFileName(fileName)));
        headers.set("Cache-Control", "private, no-store");
        return new Response(storageResponse.body, { status: 200, headers });
      }

      return json({ error: "Route not found" }, 404);

    } catch (error) {
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
