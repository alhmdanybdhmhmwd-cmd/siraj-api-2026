import { AwsClient } from "aws4fetch";


const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-File-Name, X-Recipient-Id, X-Group-Id",
  "Content-Type": "application/json; charset=utf-8"
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders
  });

const encoder = new TextEncoder();
const RECOVERY_CODE_TTL_SECONDS = 90 * 24 * 60 * 60;

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

async function signToken(user, secret) {
  const header = base64url(
    encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" }))
  );

  const payload = base64url(
    encoder.encode(JSON.stringify({
      sub: user.id,
      username: user.username,
      iat_ms: Date.now(),
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
    const parts = token.split(".");
    if (parts.length !== 3) return null;

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
  if (!payload) return null;

  const revocation = await env.DB.prepare(
    "SELECT revoked_at_ms FROM recovery_token_revocations WHERE user_id = ?"
  ).bind(payload.sub).first();
  if (revocation && Number(payload.iat_ms || 0) <= Number(revocation.revoked_at_ms)) {
    return null;
  }
  return payload;
}

function cleanUser(user) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.display_name,
    phone: user.phone || null
  };
}


async function sendSirajPush(env, recipientId, senderId, senderName, messageText) {
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
      "SELECT messages FROM notification_preferences WHERE user_id = ?"
    ).bind(recipientId).first();
    if (pref && pref.messages === 0) return;

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
                title: "رسالة من " + String(senderName || "مستخدم سراج").slice(0, 80),
                body: preview || "لديك رسالة جديدة"
              },
              data: { type: "direct_message", senderId: String(senderId || "") },
              android: { priority: "HIGH", notification: { channel_id: "siraj_messages" } }
            }
          })
        }
      );
      if (response.status === 404 || response.status === 400) {
        const detail = await response.clone().text();
        if (/UNREGISTERED|INVALID_ARGUMENT/i.test(detail)) {
          await env.DB.prepare("DELETE FROM device_tokens WHERE fcm_token = ?")
            .bind(device.fcm_token).run();
        }
      }
    }));
  } catch (error) {
    console.error("Siraj push delivery failed:", error);
  }
}

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
  await env.DB.prepare("INSERT INTO recovery_codes (user_id, code_hash, code_salt, expires_at, consumed_at, created_at) VALUES (?, ?, ?, ?, NULL, ?) ON CONFLICT(user_id) DO UPDATE SET code_hash = excluded.code_hash, code_salt = excluded.code_salt, expires_at = excluded.expires_at, consumed_at = NULL, created_at = excluded.created_at")
    .bind(userId, recovery.codeHash, recovery.salt, now + RECOVERY_CODE_TTL_SECONDS, now).run();
}

async function consumeRecoveryAttempt(env, scope, identifier, maxAttempts = 5) {
  const normalized = String(identifier).toLowerCase().replace(/[\s()+.-]/g, "");
  const bucketKey = await sha256Hex("recovery:" + scope + ":" + normalized);
  const now = Math.floor(Date.now() / 1000);
  const windowStart = now - 15 * 60;
  await env.DB.prepare("INSERT INTO recovery_rate_limits (bucket_key, window_started, attempts) VALUES (?, ?, 1) ON CONFLICT(bucket_key) DO UPDATE SET window_started = CASE WHEN recovery_rate_limits.window_started <= ? THEN excluded.window_started ELSE recovery_rate_limits.window_started END, attempts = CASE WHEN recovery_rate_limits.window_started <= ? THEN 1 ELSE recovery_rate_limits.attempts + 1 END")
    .bind(bucketKey, now, windowStart, windowStart).run();
  const row = await env.DB.prepare("SELECT attempts FROM recovery_rate_limits WHERE bucket_key = ?").bind(bucketKey).first();
  return Number(row?.attempts || 0) <= maxAttempts;
}

export default {
  async fetch(request, env) {
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

        const id = crypto.randomUUID();
        const salt = base64url(
          crypto.getRandomValues(new Uint8Array(16))
        );
        const passwordHash = await hashPassword(password, salt);
        const recovery = await generateRecoveryCode();
        const createdAt = Math.floor(Date.now() / 1000);
        await env.DB.batch([
          env.DB.prepare(`INSERT INTO users (id, username, display_name, password_hash, password_salt, phone) VALUES (?, ?, ?, ?, ?, ?)`)
            .bind(id, username, displayName, passwordHash, salt, phone || null),
          env.DB.prepare(`INSERT INTO recovery_codes (user_id, code_hash, code_salt, expires_at, consumed_at, created_at) VALUES (?, ?, ?, ?, NULL, ?)`)
            .bind(id, recovery.codeHash, recovery.salt, createdAt + RECOVERY_CODE_TTL_SECONDS, createdAt)
        ]);

        const user = {
          id,
          username,
          display_name: displayName,
          phone
        };

        const token = await signToken(user, env.JWT_SECRET);

        return json({
          user: cleanUser(user),
          token,
          recoveryCode: recovery.code
        }, 201);
      }

      // One-time recovery code password reset; does not use SMS or email.
      if (method === "POST" && path === "/api/password/recover") {
        const body = await request.json();
        const identifier = String(body.identifier || body.username || body.phone || "").trim().toLowerCase();
        const recoveryCode = String(body.recoveryCode || "").replace(/[\s-]/g, "").toUpperCase();
        const newPassword = String(body.newPassword || "");
        if (!identifier || !/^[A-F0-9]{40}$/.test(recoveryCode)) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }
        if (newPassword.length < 8 || newPassword.length > 128) {
          return json({ error: "كلمة المرور يجب أن تكون بين 8 و128 حرفًا" }, 400);
        }
        if (!(await consumeRecoveryAttempt(env, "identifier", identifier))) {
          return json({ error: "محاولات كثيرة. انتظر 15 دقيقة ثم حاول مجددًا." }, 429);
        }
        const user = await env.DB.prepare("SELECT id FROM users WHERE username = ? OR phone = ? LIMIT 1").bind(identifier, identifier).first();
        if (!user) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }
        // Also limit by account ID so switching between phone and username cannot bypass the limit.
        if (!(await consumeRecoveryAttempt(env, "account", user.id))) {
          return json({ error: "محاولات كثيرة. انتظر 15 دقيقة ثم حاول مجددًا." }, 429);
        }
        const stored = await env.DB.prepare("SELECT code_hash, code_salt, consumed_at, expires_at FROM recovery_codes WHERE user_id = ?").bind(user.id).first();
        if (!stored || (stored.consumed_at !== null && stored.consumed_at !== undefined)) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }
        const suppliedHash = await sha256Hex(stored.code_salt + ":" + recoveryCode);
        const now = Math.floor(Date.now() / 1000);
        if (!constantTimeHexEqual(suppliedHash, stored.code_hash) || (stored.expires_at !== null && stored.expires_at !== undefined && Number(stored.expires_at) <= now)) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }
        const newSalt = base64url(crypto.getRandomValues(new Uint8Array(16)));
        const newHash = await hashPassword(newPassword, newSalt);
        const results = await env.DB.batch([
          env.DB.prepare("UPDATE users SET password_hash = ?, password_salt = ? WHERE id = ? AND EXISTS (SELECT 1 FROM recovery_codes WHERE user_id = ? AND code_hash = ? AND consumed_at IS NULL AND (expires_at IS NULL OR expires_at > ?))")
            .bind(newHash, newSalt, user.id, user.id, stored.code_hash, now),
          env.DB.prepare("UPDATE recovery_codes SET consumed_at = ? WHERE user_id = ? AND code_hash = ? AND consumed_at IS NULL")
            .bind(now, user.id, stored.code_hash),
          env.DB.prepare("INSERT INTO recovery_token_revocations (user_id, revoked_at_ms) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET revoked_at_ms = excluded.revoked_at_ms")
            .bind(user.id, Date.now())
        ]);
        if (Number(results?.[0]?.meta?.changes || 0) !== 1 || Number(results?.[1]?.meta?.changes || 0) !== 1 || Number(results?.[2]?.meta?.changes || 0) !== 1) {
          return json({ error: "تعذر استرداد الحساب. تحقق من البيانات وحاول مجددًا." }, 400);
        }
        return json({ message: "Password updated" });
      }

      // Login
      if (method === "POST" && path === "/api/login") {
        const body = await request.json();

        const username = String(body.username || "").trim().toLowerCase();
        const password = String(body.password || "");

        const user = await env.DB.prepare(
          "SELECT * FROM users WHERE username = ? OR phone = ? LIMIT 1"
        ).bind(username, username).first();

        if (
          !user ||
          await hashPassword(password, user.password_salt) !== user.password_hash
        ) {
          return json({
            error: "Incorrect username or password"
          }, 401);
        }

        const token = await signToken(user, env.JWT_SECRET);

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

      // Issue a new recovery code only after confirming the current password.
      if (method === "POST" && path === "/api/recovery-code") {
        const body = await request.json();
        const password = String(body.password || "");
        const user = await env.DB.prepare("SELECT password_hash, password_salt FROM users WHERE id = ?").bind(currentUser.sub).first();
        if (!user || !password || await hashPassword(password, user.password_salt) !== user.password_hash) {
          return json({ error: "كلمة المرور الحالية غير صحيحة" }, 401);
        }
        const recovery = await generateRecoveryCode();
        await saveRecoveryCode(env, currentUser.sub, recovery);
        return json({ recoveryCode: recovery.code, message: "احفظ رمز الاسترداد في مكان آمن؛ لن يظهر مرة أخرى." });
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
        await env.DB.prepare(
          "UPDATE users SET display_name = ?, phone = ? WHERE id = ?"
        ).bind(displayName, phone || null, currentUser.sub).run();
        const user = await env.DB.prepare(
          "SELECT id, username, display_name, phone FROM users WHERE id = ?"
        ).bind(currentUser.sub).first();
        if (!user) return json({ error: "User not found" }, 404);
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
          const searchable = body.searchable === false ? 0 : 1;
          const readReceipts = body.readReceipts === false ? 0 : 1;
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
          await env.DB.prepare(`
            INSERT INTO notification_preferences (user_id, messages, groups, statuses)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
              messages = excluded.messages,
              groups = excluded.groups,
              statuses = excluded.statuses,
              updated_at = CURRENT_TIMESTAMP
          `).bind(currentUser.sub, body.messages === false ? 0 : 1,
            body.groups === false ? 0 : 1, body.statuses === false ? 0 : 1).run();
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

      // Register Firebase device token
      if (method === "POST" && path === "/api/devices/token") {
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

        const users = await env.DB.prepare(
          `SELECT id, username, display_name, phone
           FROM users
           WHERE id != ?
           AND (username LIKE ? OR phone LIKE ?)
           AND COALESCE((SELECT searchable FROM user_privacy WHERE user_id = users.id), 1) = 1
           LIMIT 30`
        ).bind(
          currentUser.sub,
          "%" + q + "%",
          "%" + q + "%"
        ).all();

        return json({
          users: (users.results || []).map(cleanUser)
        });
      }

      // Add a contact directly (no friend-request workflow).
      if (method === "POST" && path === "/api/contacts") {
        const body = await request.json();
        const userId = String(body.userId || "").trim();
        if (!userId || userId === currentUser.sub) {
          return json({ error: "Invalid contact" }, 400);
        }
        const target = await env.DB.prepare(
          "SELECT id FROM users WHERE id = ?"
        ).bind(userId).first();
        if (!target) return json({ error: "User not found" }, 404);
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

      // Send friend request
      if (method === "POST" && path === "/api/friends/requests") {
        const body = await request.json();

        const target = String(
          body.username || body.phone || body.target || ""
        ).trim();

        if (!target) {
          return json({
            error: "Enter a username or phone number"
          }, 400);
        }

        const receiver = await env.DB.prepare(
          "SELECT id FROM users WHERE username = ? OR phone = ? LIMIT 1"
        ).bind(target.toLowerCase(), target).first();

        if (!receiver) {
          return json({ error: "User not found" }, 404);
        }

        if (receiver.id === currentUser.sub) {
          return json({ error: "Cannot add yourself" }, 400);
        }

        const existing = await env.DB.prepare(
          `SELECT id, status FROM friend_requests
           WHERE (sender_id = ? AND receiver_id = ?)
           OR (sender_id = ? AND receiver_id = ?)
           LIMIT 1`
        ).bind(
          currentUser.sub,
          receiver.id,
          receiver.id,
          currentUser.sub
        ).first();

        if (existing && existing.status === "accepted") {
          return json({ error: "Already friends" }, 409);
        }

        if (existing && existing.status === "pending") {
          return json({ error: "A request already exists" }, 409);
        }

        const id = crypto.randomUUID();

        await env.DB.prepare(
          `INSERT INTO friend_requests
           (id, sender_id, receiver_id, status)
           VALUES (?, ?, ?, 'pending')`
        ).bind(id, currentUser.sub, receiver.id).run();

        return json({
          message: "Friend request sent",
          id
        }, 201);
      }

      // Get friend requests
      if (method === "GET" && path === "/api/friends/requests") {
        const incoming = await env.DB.prepare(
          `SELECT r.id, r.status, r.created_at,
                  u.id AS user_id, u.username, u.display_name
           FROM friend_requests r
           JOIN users u ON u.id = r.sender_id
           WHERE r.receiver_id = ? AND r.status = 'pending'
           ORDER BY r.created_at DESC`
        ).bind(currentUser.sub).all();

        const outgoing = await env.DB.prepare(
          `SELECT r.id, r.status, r.created_at,
                  u.id AS user_id, u.username, u.display_name
           FROM friend_requests r
           JOIN users u ON u.id = r.receiver_id
           WHERE r.sender_id = ? AND r.status = 'pending'
           ORDER BY r.created_at DESC`
        ).bind(currentUser.sub).all();

        return json({
          incoming: incoming.results || [],
          outgoing: outgoing.results || []
        });
      }

      // Accept or reject friend request
      const actionMatch = path.match(
        /^\/api\/friends\/requests\/([^/]+)\/(accept|reject)$/
      );

      if (method === "POST" && actionMatch) {
        const requestId = actionMatch[1];
        const action = actionMatch[2];

        const friendRequest = await env.DB.prepare(
          `SELECT * FROM friend_requests
           WHERE id = ?
           AND receiver_id = ?
           AND status = 'pending'`
        ).bind(requestId, currentUser.sub).first();

        if (!friendRequest) {
          return json({ error: "Request not found" }, 404);
        }

        if (action === "reject") {
          await env.DB.prepare(
            `UPDATE friend_requests
             SET status = 'rejected',
                 updated_at = CURRENT_TIMESTAMP
             WHERE id = ?`
          ).bind(requestId).run();

          return json({ message: "Request rejected" });
        }

        await env.DB.batch([
          env.DB.prepare(
            `UPDATE friend_requests
             SET status = 'accepted',
                 updated_at = CURRENT_TIMESTAMP
             WHERE id = ? AND status = 'pending'`
          ).bind(requestId),

          env.DB.prepare(
            `INSERT OR IGNORE INTO friendships (user_id, friend_id)
             VALUES (?, ?)`
          ).bind(currentUser.sub, friendRequest.sender_id),

          env.DB.prepare(
            `INSERT OR IGNORE INTO friendships (user_id, friend_id)
             VALUES (?, ?)`
          ).bind(friendRequest.sender_id, currentUser.sub)
        ]);

        return json({ message: "Friend request accepted" });
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
      if (method === "POST" && groupMemberMatch) {
        const groupId = groupMemberMatch[1];
        const body = await request.json();
        const userId = String(body.userId || "").trim();
        const member = await env.DB.prepare(
          "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
        ).bind(groupId, currentUser.sub).first();
        const target = await env.DB.prepare("SELECT id FROM users WHERE id = ?").bind(userId).first();
        if (!member) return json({ error: "Group not found" }, 404);
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
          const result = await env.DB.prepare(`
            SELECT gm.id, gm.group_id, gm.sender_id, gm.body, gm.created_at,
                   u.username, u.display_name
            FROM group_messages gm
            JOIN users u ON u.id = gm.sender_id
            WHERE gm.group_id = ?
            ORDER BY gm.created_at ASC LIMIT 100
          `).bind(groupId).all();
          return json({ messages: result.results || [] });
        }
        if (method === "POST") {
          const body = await request.json();
          const message = String(body.body || "").trim();
          if (!message || message.length > 5000) return json({ error: "Invalid message" }, 400);
          const id = crypto.randomUUID();
          await env.DB.prepare(
            "INSERT INTO group_messages (id, group_id, sender_id, body) VALUES (?, ?, ?, ?)"
          ).bind(id, groupId, currentUser.sub, message).run();
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

        const sender = await env.DB.prepare(
          "SELECT display_name FROM users WHERE id = ?"
        ).bind(currentUser.sub).first();
        await sendSirajPush(env, receiverId, currentUser.sub, sender?.display_name || currentUser.username, message);

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

        const privacy = await env.DB.prepare(
          "SELECT read_receipts FROM user_privacy WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        if (!privacy || privacy.read_receipts === 1) {
          await env.DB.prepare(
            `UPDATE messages
             SET read_at = CURRENT_TIMESTAMP
             WHERE sender_id = ?
             AND receiver_id = ?
             AND read_at IS NULL`
          ).bind(friendId, currentUser.sub).run();
        }

        const result = await env.DB.prepare(
          `SELECT id, sender_id, receiver_id,
                  body, created_at, read_at
           FROM messages
           WHERE (sender_id = ? AND receiver_id = ?)
              OR (sender_id = ? AND receiver_id = ?)
           ORDER BY created_at ASC
           LIMIT 100`
        ).bind(
          currentUser.sub,
          friendId,
          friendId,
          currentUser.sub
        ).all();

        return json({
          messages: result.results || []
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
        const bytes = await request.arrayBuffer();
        if (!bytes.byteLength || bytes.byteLength > 20 * 1024 * 1024) {
          return json({ error: "File must be between 1 byte and 20 MB" }, 413);
        }
        const suppliedName = decodeURIComponent(request.headers.get("X-File-Name") || "attachment").replace(/[\\/\\r\\n]/g, "_").slice(0, 180);
        const id = crypto.randomUUID();
        const key = currentUser.sub + "/" + id;
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
            "x-amz-meta-contenttype": contentType
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
        if (recipientId) {
          await env.DB.prepare(
            "INSERT INTO messages (id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)"
          ).bind(messageId, currentUser.sub, recipientId, attachmentBody).run();
        } else {
          await env.DB.prepare(
            "INSERT INTO group_messages (id, group_id, sender_id, body) VALUES (?, ?, ?, ?)"
          ).bind(messageId, groupId, currentUser.sub, attachmentBody).run();
        }
        return json({ attachment: { id: key, fileName: suppliedName, contentType, size: bytes.byteLength }, messageId }, 201);
      }

      const mediaMatch = path.match(/^\/api\/media\/(.+)$/);
      if (mediaMatch && method === "GET") {
        if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
          return json({ error: "Media storage credentials are not configured" }, 503);
        }
        const key = decodeURIComponent(mediaMatch[1]);
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
        const storageResponse = await storage.fetch(storageUrl, { method: "GET" });
        if (storageResponse.status === 404) return json({ error: "Attachment not found" }, 404);
        if (!storageResponse.ok) return json({ error: "Media storage download failed", storageStatus: storageResponse.status }, 502);
        const ownerId = storageResponse.headers.get("x-amz-meta-ownerid") || "";
        const recipientId = storageResponse.headers.get("x-amz-meta-recipientid") || "";
        const groupId = storageResponse.headers.get("x-amz-meta-groupid") || "";
        let permitted = ownerId === currentUser.sub;
        if (!permitted && recipientId === currentUser.sub) {
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
        const headers = new Headers(corsHeaders);
        headers.set("Content-Type", storageResponse.headers.get("content-type") || "application/octet-stream");
        const encodedName = storageResponse.headers.get("x-amz-meta-filename") || "attachment";
        let fileName = "attachment";
        try { fileName = decodeURIComponent(encodedName); } catch (_) { fileName = encodedName; }
        headers.set("Content-Disposition", "attachment; filename*=UTF-8''" + encodeURIComponent(fileName));
        headers.set("Cache-Control", "private, no-store");
        return new Response(storageResponse.body, { status: 200, headers });
      }

      return json({ error: "Route not found" }, 404);

    } catch (error) {
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
