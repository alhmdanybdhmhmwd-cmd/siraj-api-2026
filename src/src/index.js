import { AwsClient } from "aws4fetch";


const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-File-Name, X-Recipient-Id, X-Group-Id",
  "Access-Control-Expose-Headers": "Content-Disposition, Content-Length",
  "Content-Type": "application/json; charset=utf-8"
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: corsHeaders
  });

const encoder = new TextEncoder();

function hex(bytes) { return [...new Uint8Array(bytes)].map(b => b.toString(16).padStart(2, "0")).join(""); }
async function sha256Hex(data) { return hex(await crypto.subtle.digest("SHA-256", data)); }
async function hmac(key, value) {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", k, encoder.encode(value)));
}
async function tigrisRequest(env, method, objectKey, body = undefined, contentType = "") {
  const accessKeyId = env.TIGRIS_ACCESS_KEY_ID;
  const secretAccessKey = env.TIGRIS_SECRET_ACCESS_KEY;
  const bucket = env.TIGRIS_BUCKET || "siraj-media";
  if (!accessKeyId || !secretAccessKey || !bucket) {
    throw new Error("Tigris storage credentials are not configured");
  }
  const objectPath = objectKey.split("/").map(encodeURIComponent).join("/");
  const storageUrl = "https://" + encodeURIComponent(bucket) + ".t3.storage.dev/" + objectPath;
  const storage = new AwsClient({
    accessKeyId,
    secretAccessKey,
    service: "s3",
    region: "auto",
    retries: 2
  });
  const headers = {};
  if (contentType) headers["Content-Type"] = contentType;
  return storage.fetch(storageUrl, { method, headers, body });
}
async function deleteTigrisObject(env, objectKey) {
  const response = await tigrisRequest(env, "DELETE", objectKey);
  if (!response.ok && response.status !== 404) throw new Error("Tigris delete failed: " + response.status);
}
async function finishMediaDownload(env, asset, userId) {
  await env.DB.prepare(
    "INSERT OR IGNORE INTO media_downloads (media_id, user_id) VALUES (?, ?)"
  ).bind(asset.id, userId).run();
  const counts = await env.DB.prepare(
    "SELECT (SELECT COUNT(*) FROM media_recipients WHERE media_id = ?) AS total, (SELECT COUNT(*) FROM media_downloads WHERE media_id = ?) AS done"
  ).bind(asset.id, asset.id).first();
  if (counts && counts.total > 0 && counts.done >= counts.total) {
    await deleteTigrisObject(env, asset.object_key);
    await env.DB.prepare(
      "UPDATE media_assets SET storage_deleted = 1 WHERE id = ?"
    ).bind(asset.id).run();
  }
}
async function cleanupExpiredMedia(env) {
  const now = new Date().toISOString();
  const expired = await env.DB.prepare(
    "SELECT id, object_key FROM media_assets WHERE storage_deleted = 0 AND expires_at <= ? LIMIT 100"
  ).bind(now).all();
  for (const asset of expired.results || []) {
    try {
      await deleteTigrisObject(env, asset.object_key);
      await env.DB.prepare("UPDATE media_assets SET storage_deleted = 1 WHERE id = ?").bind(asset.id).run();
    } catch (error) {
      console.error("Siraj media cleanup failed", asset.id, error);
    }
  }
}


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

  return verifyToken(token, env.JWT_SECRET);
}

function cleanUser(user) {
  return {
    id: user.id,
    username: user.username,
    displayName: user.display_name,
    phone: user.phone || null
  };
}

export default {
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(cleanupExpiredMedia(env));
  },
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

        await env.DB.prepare(
          `INSERT INTO users
           (id, username, display_name, password_hash, password_salt, phone)
           VALUES (?, ?, ?, ?, ?, ?)`
        ).bind(
          id,
          username,
          displayName,
          passwordHash,
          salt,
          phone || null
        ).run();

        const user = {
          id,
          username,
          display_name: displayName,
          phone
        };

        const token = await signToken(user, env.JWT_SECRET);

        return json({
          user: cleanUser(user),
          token
        }, 201);
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
      // Update profile fields used by the Flutter client.
      if (method === "POST" && path === "/api/profile") {
        const body = await request.json();
        const displayName = String(body.displayName || "").trim();
        const phone = String(body.phone || "").trim();
        if (!displayName || displayName.length > 60) return json({ error: "Display name must be 1-60 characters" }, 400);
        if (phone.length > 25) return json({ error: "Phone number is too long" }, 400);
        await env.DB.prepare(
          "UPDATE users SET display_name = ?, phone = ? WHERE id = ?"
        ).bind(displayName, phone || null, currentUser.sub).run();
        const user = await env.DB.prepare(
          "SELECT id, username, display_name, phone FROM users WHERE id = ?"
        ).bind(currentUser.sub).first();
        if (!user) return json({ error: "User not found" }, 404);
        return json({ user: cleanUser(user), message: "Profile updated" });
      }

      // Privacy preferences are stored per account and default to enabled.
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
          await env.DB.prepare(`
            INSERT INTO user_privacy (user_id, searchable, read_receipts)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
              searchable = excluded.searchable,
              read_receipts = excluded.read_receipts,
              updated_at = CURRENT_TIMESTAMP
          `).bind(currentUser.sub, body.searchable === false ? 0 : 1,
            body.readReceipts === false ? 0 : 1).run();
        }
        const settings = await env.DB.prepare(
          "SELECT searchable, read_receipts FROM user_privacy WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        return json({ privacy: {
          searchable: settings ? settings.searchable === 1 : true,
          readReceipts: settings ? settings.read_receipts === 1 : true
        }});
      }

      // Per-account notification preferences.
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

      // Register Firebase device token.
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

      // Publish and list 24-hour text statuses.
      if ((method === "GET" || method === "POST") && path === "/api/statuses") {
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
        if (method === "POST") {
          const body = await request.json();
          const content = String(body.content || "").trim();
          if (!content || content.length > 1000) return json({ error: "Status text must be between 1 and 1000 characters" }, 400);
          const id = crypto.randomUUID();
          const createdAt = new Date().toISOString();
          const expiresAt = new Date(Date.now() + 86400000).toISOString();
          await env.DB.prepare(
            "INSERT INTO status_posts (id, user_id, content, expires_at) VALUES (?, ?, ?, datetime('now', '+24 hours'))"
          ).bind(id, currentUser.sub, content, expiresAt).run();
          return json({ status: { id, content, createdAt, expiresAt } }, 201);
        }
        const result = await env.DB.prepare(`
          SELECT s.id, s.user_id AS userId, u.username,
                 u.display_name AS displayName, s.content,
                 s.created_at AS createdAt, s.expires_at AS expiresAt
          FROM status_posts s
          JOIN users u ON u.id = s.user_id
          WHERE s.expires_at > CURRENT_TIMESTAMP
            AND (s.user_id = ? OR EXISTS (
              SELECT 1 FROM friendships f
              WHERE f.user_id = ? AND f.friend_id = s.user_id
            ))
          ORDER BY s.created_at DESC
          LIMIT 100
        `).bind(currentUser.sub, currentUser.sub).all();
        return json({ statuses: result.results || [] });
      }

      // Search users
      if (method === "GET" && path === "/api/users/search") {
        const q = (url.searchParams.get("q") || "").trim();

        if (q.length < 2) {
          return json({ users: [] });
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

      // Add contact directly (without a friend-request workflow)
      if (method === "POST" && path === "/api/contacts") {
        const body = await request.json();
        const target = String(
          body.username || body.phone || body.target || body.userId || body.user_id || ""
        ).trim();

        if (!target || target.length > 100) {
          return json({ error: "Enter a valid username or phone number" }, 400);
        }

        const receiver = await env.DB.prepare(
          `SELECT id, username, display_name, phone
           FROM users
           WHERE username = ? OR phone = ? OR id = ?
           LIMIT 1`
        ).bind(target.toLowerCase(), target, target).first();

        if (!receiver) {
          return json({ error: "User not found" }, 404);
        }

        if (receiver.id === currentUser.sub) {
          return json({ error: "Cannot add yourself" }, 400);
        }

        await env.DB.batch([
          env.DB.prepare(
            `INSERT OR IGNORE INTO friendships (user_id, friend_id)
             VALUES (?, ?)`
          ).bind(currentUser.sub, receiver.id),
          env.DB.prepare(
            `INSERT OR IGNORE INTO friendships (user_id, friend_id)
             VALUES (?, ?)`
          ).bind(receiver.id, currentUser.sub)
        ]);

        return json({
          message: "Contact added",
          user: cleanUser(receiver)
        }, 200);
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


      // Private attachments stored in Tigris S3-compatible object storage.
      if (method === "POST" && path === "/api/media") {
        if (!env.TIGRIS_ACCESS_KEY_ID || !env.TIGRIS_SECRET_ACCESS_KEY) {
          return json({ error: "Tigris storage is not configured yet" }, 503);
        }
        const recipientId = (request.headers.get("X-Recipient-Id") || "").trim();
        const groupId = (request.headers.get("X-Group-Id") || "").trim();
        if (!!recipientId === !!groupId) return json({ error: "Choose exactly one recipient or group" }, 400);

        if (recipientId) {
          const friendship = await env.DB.prepare(
            "SELECT 1 FROM friendships WHERE user_id = ? AND friend_id = ?"
          ).bind(currentUser.sub, recipientId).first();
          if (!friendship) return json({ error: "You can only send attachments to contacts" }, 403);
        } else {
          const membership = await env.DB.prepare(
            "SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?"
          ).bind(groupId, currentUser.sub).first();
          if (!membership) return json({ error: "Group not found" }, 404);
        }

        const contentType = (request.headers.get("Content-Type") || "application/octet-stream").split(";")[0].trim().toLowerCase();
        const allowedType = contentType.startsWith("image/") || contentType.startsWith("video/") ||
          contentType.startsWith("audio/") || ["application/pdf", "application/zip", "application/msword",
          "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.ms-excel",
          "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "application/vnd.ms-powerpoint",
          "application/vnd.openxmlformats-officedocument.presentationml.presentation", "text/plain", "text/csv",
          "application/rtf", "application/octet-stream"].includes(contentType);
        if (!allowedType) return json({ error: "This file type is not allowed" }, 415);

        const declaredSize = Number(request.headers.get("Content-Length") || 0);
        if (declaredSize > 20 * 1024 * 1024) return json({ error: "Maximum attachment size is 20 MB" }, 413);
        const bytes = await request.arrayBuffer();
        if (!bytes.byteLength || bytes.byteLength > 20 * 1024 * 1024) {
          return json({ error: "File is empty or exceeds 20 MB" }, 413);
        }

        let fileName = request.headers.get("X-File-Name") || "attachment";
        try { fileName = decodeURIComponent(fileName); } catch {}
        fileName = fileName.replace(/[\\\/\r\n\0]/g, "_").slice(0, 180) || "attachment";
        const id = crypto.randomUUID();
        const objectKey = "private/" + id;
        const upload = await tigrisRequest(env, "PUT", objectKey, bytes, contentType);
        if (!upload.ok) {
          const detail = await upload.text();
          console.error("Tigris upload failed", upload.status, detail.slice(0, 500));
          return json({ error: "Could not upload attachment to storage" }, 502);
        }

        const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
        const attachmentBody = JSON.stringify({
          type: "attachment", attachmentId: id, fileName, contentType, sizeBytes: bytes.byteLength
        });
        try {
          const statements = [
            env.DB.prepare(
              "INSERT INTO media_assets (id, owner_id, recipient_id, group_id, object_key, file_name, content_type, size_bytes, expires_at, storage_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)"
            ).bind(id, currentUser.sub, recipientId || null, groupId || null, objectKey, fileName, contentType, bytes.byteLength, expiresAt)
          ];
          if (recipientId) {
            statements.push(env.DB.prepare(
              "INSERT INTO media_recipients (media_id, user_id) VALUES (?, ?)"
            ).bind(id, recipientId));
            statements.push(env.DB.prepare(
              "INSERT INTO messages (id, sender_id, receiver_id, body) VALUES (?, ?, ?, ?)"
            ).bind(crypto.randomUUID(), currentUser.sub, recipientId, attachmentBody));
          } else {
            statements.push(env.DB.prepare(
              "INSERT INTO media_recipients (media_id, user_id) SELECT ?, user_id FROM group_members WHERE group_id = ? AND user_id != ?"
            ).bind(id, groupId, currentUser.sub));
            statements.push(env.DB.prepare(
              "INSERT INTO group_messages (id, group_id, sender_id, body) VALUES (?, ?, ?, ?)"
            ).bind(crypto.randomUUID(), groupId, currentUser.sub, attachmentBody));
            statements.push(env.DB.prepare("UPDATE groups SET updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(groupId));
          }
          await env.DB.batch(statements);
        } catch (error) {
          try { await deleteTigrisObject(env, objectKey); } catch (cleanupError) { console.error("Tigris rollback cleanup failed", cleanupError); }
          throw error;
        }
        return json({
          attachment: { id, fileName, contentType, sizeBytes: bytes.byteLength, downloadPath: "/api/media/" + id, expiresAt },
          message: "Attachment sent"
        }, 201);
      }

      const mediaMatch = path.match(/^\/api\/media\/([^/]+)$/);
      if (method === "GET" && mediaMatch) {
        const asset = await env.DB.prepare(
          "SELECT id, owner_id, recipient_id, group_id, object_key, file_name, content_type, size_bytes, storage_deleted FROM media_assets WHERE id = ?"
        ).bind(mediaMatch[1]).first();
        if (!asset || asset.storage_deleted) return json({ error: "Attachment has expired or was already downloaded" }, 404);

        const recipient = await env.DB.prepare(
          "SELECT 1 FROM media_recipients WHERE media_id = ? AND user_id = ?"
        ).bind(asset.id, currentUser.sub).first();
        const allowed = asset.owner_id === currentUser.sub || !!recipient;
        if (!allowed) return json({ error: "Attachment not found" }, 404);

        const object = await tigrisRequest(env, "GET", asset.object_key);
        if (!object.ok) {
          if (object.status === 404) return json({ error: "Attachment data is missing" }, 404);
          console.error("Tigris download failed", object.status, (await object.text()).slice(0, 300));
          return json({ error: "Could not download attachment" }, 502);
        }
        const safeName = asset.file_name.replace(/["\r\n]/g, "_");
        const headers = {
          ...corsHeaders, "Content-Type": asset.content_type, "Content-Length": String(asset.size_bytes),
          "Content-Disposition": "attachment; filename*=UTF-8''" + encodeURIComponent(safeName),
          "Cache-Control": "private, no-store"
        };
        const reader = object.body.getReader();
        const stream = new ReadableStream({
          async pull(controller) {
            try {
              const part = await reader.read();
              if (part.done) {
                controller.close();
                if (recipient) {
                  try { await finishMediaDownload(env, asset, currentUser.sub); }
                  catch (error) { console.error("Siraj download receipt failed", error); }
                }
              } else controller.enqueue(part.value);
            } catch (error) { controller.error(error); }
          },
          async cancel(reason) { try { await reader.cancel(reason); } catch {} }
        });
        return new Response(stream, { headers });
      }

      // Group conversations (requires migrations/0001_groups_media.sql)
      if (method === "GET" && path === "/api/groups") {
        const result = await env.DB.prepare(
          `SELECT g.id, g.name, g.description, g.created_by, g.created_at,
                  (SELECT COUNT(*) FROM group_members gm2
                   WHERE gm2.group_id = g.id) AS member_count
           FROM groups g
           INNER JOIN group_members gm ON gm.group_id = g.id
           WHERE gm.user_id = ?
           ORDER BY g.updated_at DESC`
        ).bind(currentUser.sub).all();

        return json({ groups: result.results || [] });
      }

      if (method === "POST" && path === "/api/groups") {
        const body = await request.json();
        const name = String(body.name || "").trim();
        const description = String(body.description || "").trim();

        if (!name || name.length > 80 || description.length > 500) {
          return json({ error: "Group name (1-80) and description (up to 500) are required" }, 400);
        }

        const id = crypto.randomUUID();
        await env.DB.batch([
          env.DB.prepare(
            `INSERT INTO groups (id, name, description, created_by)
             VALUES (?, ?, ?, ?)`
          ).bind(id, name, description, currentUser.sub),
          env.DB.prepare(
            `INSERT INTO group_members (group_id, user_id, role)
             VALUES (?, ?, 'owner')`
          ).bind(id, currentUser.sub)
        ]);

        return json({
          group: {
            id, name, description, created_by: currentUser.sub,
            member_count: 1
          }
        }, 201);
      }

      const groupMemberMatch = path.match(/^\/api\/groups\/([^/]+)\/members$/);
      if (method === "POST" && groupMemberMatch) {
        const groupId = groupMemberMatch[1];
        const body = await request.json();
        const targetId = String(body.userId || body.user_id || "").trim();

        if (!targetId) return json({ error: "User ID is required" }, 400);

        const actor = await env.DB.prepare(
          `SELECT role FROM group_members
           WHERE group_id = ? AND user_id = ?`
        ).bind(groupId, currentUser.sub).first();

        if (!actor || !["owner", "admin"].includes(actor.role)) {
          return json({ error: "Only group admins can add members" }, 403);
        }

        const target = await env.DB.prepare(
          "SELECT id FROM users WHERE id = ?"
        ).bind(targetId).first();
        if (!target) return json({ error: "User not found" }, 404);

        await env.DB.prepare(
          `INSERT OR IGNORE INTO group_members (group_id, user_id, role)
           VALUES (?, ?, 'member')`
        ).bind(groupId, targetId).run();

        return json({ message: "Member added" });
      }

      const groupMessagesMatch = path.match(/^\/api\/groups\/([^/]+)\/messages$/);
      if (groupMessagesMatch) {
        const groupId = groupMessagesMatch[1];
        const membership = await env.DB.prepare(
          `SELECT 1 FROM group_members
           WHERE group_id = ? AND user_id = ?`
        ).bind(groupId, currentUser.sub).first();

        if (!membership) return json({ error: "Group not found" }, 404);

        if (method === "GET") {
          const result = await env.DB.prepare(
            `SELECT gm.id, gm.group_id, gm.sender_id, gm.body, gm.created_at,
                    u.username, u.display_name
             FROM group_messages gm
             INNER JOIN users u ON u.id = gm.sender_id
             WHERE gm.group_id = ?
             ORDER BY gm.created_at ASC
             LIMIT 200`
          ).bind(groupId).all();

          return json({ messages: result.results || [] });
        }

        if (method === "POST") {
          const body = await request.json();
          const message = String(body.body || "").trim();

          if (!message || message.length > 5000) {
            return json({ error: "Message must be 1-5000 characters" }, 400);
          }

          const id = crypto.randomUUID();
          await env.DB.prepare(
            `INSERT INTO group_messages (id, group_id, sender_id, body)
             VALUES (?, ?, ?, ?)`
          ).bind(id, groupId, currentUser.sub, message).run();

          await env.DB.prepare(
            "UPDATE groups SET updated_at = CURRENT_TIMESTAMP WHERE id = ?"
          ).bind(groupId).run();

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
          "SELECT read_receipts FROM user_privacy WHERE user_id = ?"
        ).bind(currentUser.sub).first();
        if (!privacy || privacy.read_receipts === 1) {
          await env.DB.prepare(
            `UPDATE messages SET read_at = CURRENT_TIMESTAMP
             WHERE sender_id = ? AND receiver_id = ? AND read_at IS NULL`
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
