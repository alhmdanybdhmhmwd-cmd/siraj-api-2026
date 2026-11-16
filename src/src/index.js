
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Content-Type": "application/json; charset=utf-8"
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: corsHeaders });

const encoder = new TextEncoder();

function base64url(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeBase64url(value) {
  const s = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(s + "=".repeat((4 - s.length % 4) % 4));
  return Uint8Array.from(binary, c => c.charCodeAt(0));
}

async function signToken(user, secret) {
  const header = base64url(encoder.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const payload = base64url(encoder.encode(JSON.stringify({
    sub: user.id,
    username: user.username,
    exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30
  })));
  const data = header + "." + payload;
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(data));
  return data + "." + base64url(new Uint8Array(signature));
}

async function verifyToken(token, secret) {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const key = await crypto.subtle.importKey(
      "raw", encoder.encode(secret),
      { name: "HMAC", hash: "SHA-256" }, false, ["verify"]
    );
    const valid = await crypto.subtle.verify(
      "HMAC", key, decodeBase64url(parts[2]),
      encoder.encode(parts[0] + "." + parts[1])
    );
    if (!valid) return null;
    const payload = JSON.parse(new TextDecoder().decode(decodeBase64url(parts[1])));
    if (!payload.sub || payload.exp < Math.floor(Date.now() / 1000)) return null;
    return payload;
  } catch {
    return null;
  }
}

async function hashPassword(password, salt) {
  const key = await crypto.subtle.importKey(
    "raw", encoder.encode(password), "PBKDF2", false, ["deriveBits"]
  );
  const bits = await crypto.subtle.deriveBits({
    name: "PBKDF2",
    salt: decodeBase64url(salt),
    iterations: 100000,
    hash: "SHA-256"
  }, key, 256);
  return base64url(new Uint8Array(bits));
}

async function authenticate(request, env) {
  const auth = request.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
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
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    try {
      if (!env.DB || !env.JWT_SECRET) {
        return json({ error: "Server configuration is incomplete" }, 500);
      }

      const url = new URL(request.url);
      const path = url.pathname.replace(/\/+$/, "") || "/";
      const method = request.method;

      if (method === "GET" && path === "/") {
        return json({ name: "Siraj API", status: "ready" });
      }

      if (method === "POST" && path === "/api/register") {
        const body = await request.json();
        const displayName = String(body.displayName || "").trim();
        const username = String(body.username || "").trim().toLowerCase();
        const password = String(body.password || "");
        const phone = String(body.phone || "").trim();

        if (!displayName || !username || !password) {
          return json({ error: "Name, username and password are required" }, 400);
        }
        if (!/^[a-zA-Z0-9_.]{3,30}$/.test(username)) {
          return json({ error: "Username must be 3-30 characters: letters, numbers, _ or ." }, 400);
        }
        if (password.length < 8 || password.length > 128) {
          return json({ error: "Password must be at least 8 characters" }, 400);
        }
        if (phone && phone.length > 25) {
          return json({ error: "Invalid phone number" }, 400);
        }

        const id = crypto.randomUUID();
        const salt = base64url(crypto.getRandomValues(new Uint8Array(16)));
        const passwordHash = await hashPassword(password, salt);

        await env.DB.prepare(
          `INSERT INTO users (id, username, display_name, password_hash, password_salt, phone)
           VALUES (?, ?, ?, ?, ?, ?)`
        ).bind(id, username, displayName, passwordHash, salt, phone || null).run();

        const user = { id, username, display_name: displayName, phone };
        const token = await signToken(user, env.JWT_SECRET);
        return json({ user: cleanUser(user), token }, 201);
      }

      if (method === "POST" && path === "/api/login") {
        const body = await request.json();
        const username = String(body.username || "").trim().toLowerCase();
        const password = String(body.password || "");

        const user = await env.DB.prepare(
          "SELECT * FROM users WHERE username = ? OR phone = ? LIMIT 1"
        ).bind(username, username).first();

        if (!user || await hashPassword(password, user.password_salt) !== user.password_hash) {
          return json({ error: "Incorrect username or password" }, 401);
        }

        const token = await signToken(user, env.JWT_SECRET);
        return json({ user: cleanUser(user), token });
      }

      const currentUser = await authenticate(request, env);
      if (!currentUser) return json({ error: "Unauthorized" }, 401);

      if (method === "GET" && path === "/api/me") {
        const user = await env.DB.prepare(
          "SELECT id, username, display_name, phone FROM users WHERE id = ?"
        ).bind(currentUser.sub).first();
        if (!user) return json({ error: "User not found" }, 404);
        return json({ user: cleanUser(user) });
      }

      if (method === "GET" && path === "/api/users/search") {
        const q = (url.searchParams.get("q") || "").trim();
        if (q.length < 2) return json({ users: [] });

        const users = await env.DB.prepare(
          `SELECT id, username, display_name, phone
           FROM users
           WHERE id != ? AND (username LIKE ? OR phone LIKE ?)
           LIMIT 30`
        ).bind(currentUser.sub, "%" + q + "%", "%" + q + "%").all();

        return json({ users: (users.results || []).map(cleanUser) });
      }

      if (method === "POST" && path === "/api/friends/requests") {
        const body = await request.json();
        const target = String(body.username || body.phone || body.target || "").trim();
        if (!target) return json({ error: "Enter a username or phone number" }, 400);

        const receiver = await env.DB.prepare(
          "SELECT id FROM users WHERE username = ? OR phone = ? LIMIT 1"
        ).bind(target.toLowerCase(), target).first();

        if (!receiver) return json({ error: "User not found" }, 404);
        if (receiver.id === currentUser.sub) return json({ error: "Cannot add yourself" }, 400);

        const existing = await env.DB.prepare(
          `SELECT id, status FROM friend_requests
           WHERE (sender_id = ? AND receiver_id = ?)
           OR (sender_id = ? AND receiver_id = ?)
           LIMIT 1`
        ).bind(currentUser.sub, receiver.id, receiver.id, currentUser.sub).first();

        if (existing && existing.status === "accepted") {
          return json({ error: "Already friends" }, 409);
        }
        if (existing && existing.status === "pending") {
          return json({ error: "A request already exists" }, 409);
        }

        const id = crypto.randomUUID();
        await env.DB.prepare(
          `INSERT INTO friend_requests (id, sender_id, receiver_id, status)
           VALUES (?, ?, ?, 'pending')`
        ).bind(id, currentUser.sub, receiver.id).run();

        return json({ message: "Friend request sent", id }, 201);
      }

      if (method === "GET" && path === "/api/friends/requests") {
        const incoming = await env.DB.prepare(
          `SELECT r.id, r.status, r.created_at,
                  u.id AS user_id, u.username, u.display_name
           FROM friend_requests r JOIN users u ON u.id = r.sender_id
           WHERE r.receiver_id = ? AND r.status = 'pending'
           ORDER BY r.created_at DESC`
        ).bind(currentUser.sub).all();

        const outgoing = await env.DB.prepare(
          `SELECT r.id, r.status, r.created_at,
                  u.id AS user_id, u.username, u.display_name
           FROM friend_requests r JOIN users u ON u.id = r.receiver_id
           WHERE r.sender_id = ? AND r.status = 'pending'
           ORDER BY r.created_at DESC`
        ).bind(currentUser.sub).all();

        return json({
          incoming: incoming.results || [],
          outgoing: outgoing.results || []
        });
      }

      const actionMatch = path.match(/^\/api\/friends\/requests\/([^/]+)\/(accept|reject)$/);
      if (method === "POST" && actionMatch) {
        const requestId = actionMatch[1];
        const action = actionMatch[2];

        const friendRequest = await env.DB.prepare(
          `SELECT * FROM friend_requests
           WHERE id = ? AND receiver_id = ? AND status = 'pending'`
        ).bind(requestId, currentUser.sub).first();

        if (!friendRequest) return json({ error: "Request not found" }, 404);

        if (action === "reject") {
          await env.DB.prepare(
            "UPDATE friend_requests SET status = 'rejected', updated_at = CURRENT_TIMESTAMP WHERE id = ?"
          ).bind(requestId).run();
          return json({ message: "Request rejected" });
        }

        await env.DB.batch([
          env.DB.prepare(
            "UPDATE friend_requests SET status = 'accepted', updated_at = CURRENT_TIMESTAMP WHERE id = ? AND status = 'pending'"
          ).bind(requestId),
          env.DB.prepare(
            "INSERT OR IGNORE INTO friendships (user_id, friend_id) VALUES (?, ?)"
          ).bind(currentUser.sub, friendRequest.sender_id),
          env.DB.prepare(
            "INSERT OR IGNORE INTO friendships (user_id, friend_id) VALUES (?, ?)"
          ).bind(friendRequest.sender_id, currentUser.sub)
        ]);

        return json({ message: "Friend request accepted" });
      }

      if (method === "GET" && path === "/api/friends") {
        const friends = await env.DB.prepare(
          `SELECT u.id, u.username, u.display_name, u.phone
           FROM friendships f JOIN users u ON u.id = f.friend_id
           WHERE f.user_id = ?
           ORDER BY u.display_name`
        ).bind(currentUser.sub).all();

        return json({ friends: (friends.results || []).map(cleanUser) });
      }

      return json({ error: "Route not found" }, 404);

    } catch (error) {
      if (error && /UNIQUE constraint failed/i.test(error.message || "")) {
        return json({ error: "Username or phone number is already registered" }, 409);
      }
      return json({ error: "Internal server error" }, 500);
    }
  }
};
