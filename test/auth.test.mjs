import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const workerPath = new URL("../src/src/index.js", import.meta.url);
let workerSource = await readFile(workerPath, "utf8");
workerSource = workerSource.replace('import { AwsClient } from "aws4fetch";', `
class AwsClient {
  async fetch(url, options) {
    return globalThis.__fakeTigrisHandler(url, options);
  }
}
`);
workerSource += "\nexport { signToken, verifyToken, authenticate, hashPassword };";
const worker = await import("data:text/javascript;base64," + Buffer.from(workerSource).toString("base64"));

const secret = "unit-test-secret-that-is-long-enough";
const user = {
  id: "user-1",
  username: "tester",
  display_name: "Tester",
  phone: "+967700000001",
  password_salt: "AAECAwQFBgcICQoLDA0ODw",
  password_hash: "old-hash"
};

class FakeDB {
  constructor() {
    this.user = { ...user };
    this.users = [this.user];
    this.recovery = null;
    this.sessionVersion = 0;
    this.recoveryAttempts = new Map();
    this.loginAttempts = new Map();
    this.contactCandidates = [];
    this.privacySettings = null;
    this.notificationSettings = null;
  }

  prepare(sql) {
    const db = this;
    return {
      sql,
      params: [],
      bind(...params) { this.params = params; return this; },
      async first() {
        if (sql.includes("SELECT session_version FROM account_security")) {
          return { session_version: db.sessionVersion };
        }
        if (sql.includes("SELECT searchable, read_receipts FROM user_privacy")) {
          return db.privacySettings ? { ...db.privacySettings } : null;
        }
        if (sql.includes("SELECT messages, groups, statuses FROM notification_preferences")) {
          return db.notificationSettings ? { ...db.notificationSettings } : null;
        }
        if (sql.includes("COALESCE((SELECT searchable FROM user_privacy")) {
          return db.targetUser ? { id: db.targetUser.id, searchable: db.targetUser.searchable ? 1 : 0 } : null;
        }
        if (sql.includes("SELECT id FROM users WHERE phone = ? AND id != ?")) {
          return db.existingPhone && db.existingPhone.phone === this.params[0] &&
            db.existingPhone.id !== this.params[1] ? { id: db.existingPhone.id } : null;
        }
        if (sql.includes("SELECT * FROM users") && sql.includes("username = ? OR phone = ?")) {
          const identifier = String(this.params[0]).toLowerCase();
          const phoneCandidates = this.params.slice(2).map(String);
          const storedDigits = String(db.user.phone).replace(/\\D/g, "");
          return identifier === db.user.username || identifier === db.user.phone ||
            phoneCandidates.some(value => value === storedDigits || value === storedDigits.slice(-9))
            ? { ...db.user } : null;
        }
        if (sql.includes("SELECT id FROM users WHERE username = ? OR phone = ?")) {
          const identifier = String(this.params[0]).toLowerCase();
          const phoneCandidates = this.params.slice(2).map(String);
          const storedDigits = String(db.user.phone).replace(/\D/g, "");
          return identifier === db.user.username || identifier === db.user.phone ||
            phoneCandidates.some(value => value === storedDigits || value === storedDigits.slice(-9))
            ? { id: db.user.id } : null;
        }
        if (sql.includes("SELECT password_hash, password_salt FROM users WHERE id = ?")) {
          return { password_hash: db.user.password_hash, password_salt: db.user.password_salt };
        }
        if (sql.includes("SELECT code_hash, code_salt, consumed_at, expires_at FROM recovery_codes")) {
          return db.recovery ? { ...db.recovery } : null;
        }
        if (sql.includes("SELECT attempts FROM recovery_rate_limits")) {
          return { attempts: db.recoveryAttempts.get(this.params[0]) || 0 };
        }
        if (sql.includes("SELECT attempts FROM login_rate_limits")) {
          return { attempts: db.loginAttempts.get(this.params[0]) || 0 };
        }
        return null;
      },
      async all() {
        if (sql.includes("LIKE ?") && sql.includes("FROM users") && sql.includes("user_privacy")) {
          db.userSearchQueries = (db.userSearchQueries || 0) + 1;
          db.lastUserSearchSql = sql;
          return { results: db.searchCandidates || [] };
        }
        if (sql.includes("SELECT id, phone FROM users")) {
          db.phoneLookupQueries = (db.phoneLookupQueries || 0) + 1;
          db.lastPhoneLookupSql = sql;
          return { results: db.phoneCandidates || [] };
        }
        if (sql.includes("substr(") && sql.includes("user_privacy")) {
          db.contactLookupQueries = (db.contactLookupQueries || 0) + 1;
          return { results: db.contactCandidates };
        }
        return { results: [] };
      },
      async run() {
        if (sql.includes("INSERT OR IGNORE INTO account_security")) db.sessionVersion ??= 0;
        if (sql.includes("INSERT INTO user_privacy")) {
          db.privacySettings = { searchable: this.params[1], read_receipts: this.params[2] };
        }
        if (sql.includes("INSERT INTO notification_preferences")) {
          db.notificationSettings = { messages: this.params[1], groups: this.params[2], statuses: this.params[3] };
        }
        if (sql.includes("INSERT INTO recovery_rate_limits")) {
          const key = this.params[0];
          db.recoveryAttempts.set(key, (db.recoveryAttempts.get(key) || 0) + 1);
        }
        if (sql.includes("INSERT INTO login_rate_limits")) {
          const key = this.params[0];
          db.loginAttempts.set(key, (db.loginAttempts.get(key) || 0) + 1);
        }
        if (sql.includes("INSERT INTO recovery_codes")) {
          db.recovery = { code_hash: this.params[1], code_salt: this.params[2], expires_at: this.params[3], consumed_at: null };
        }
        return { meta: { changes: 1 } };
      }
    };
  }

  async batch(statements) {
    if (statements[0].sql.includes("INSERT INTO users")) {
      // Model SQLite's atomic INSERT ... SELECT ... WHERE NOT EXISTS guard.
      const userParams = statements[0].params;
      const phone = userParams[5];
      const digits = value => String(value || "").replace(/[٠-٩۰-۹]/g, digit => {
        const code = digit.charCodeAt(0);
        return String(code >= 0x06f0 ? code - 0x06f0 : code - 0x0660);
      }).replace(/\D/g, "");
      const variants = value => {
        const raw = digits(value);
        const set = new Set([raw]);
        const international = raw.startsWith("00") ? raw.slice(2) : raw;
        set.add(international);
        if (international.startsWith("967") && international.length >= 10) set.add(international.slice(3));
        if (international.startsWith("0") && international.length >= 8) set.add(international.slice(1));
        return [...set].filter(item => item.length >= 7 && item.length <= 15);
      };
      const conflict = phone && this.users.some(existing =>
        variants(existing.phone).some(value => variants(phone).includes(value))
      );
      if (conflict) return [{ meta: { changes: 0 } }, { meta: { changes: 0 } }];
      const recoveryParams = statements[1].params;
      this.user = {
        id: userParams[0], username: userParams[1], display_name: userParams[2],
        password_hash: userParams[3], password_salt: userParams[4], phone: userParams[5]
      };
      this.users.push(this.user);
      this.recovery = {
        code_hash: recoveryParams[1], code_salt: recoveryParams[2],
        expires_at: recoveryParams[3], consumed_at: null
      };
      return [{ meta: { changes: 1 } }, { meta: { changes: 1 } }];
    }
    const [updatePassword, consumeCode, incrementVersion] = statements;
    const [newHash, newSalt, userId, recoveryUserId, expectedHash, now] = updatePassword.params;
    if (!this.recovery || this.recovery.code_hash !== expectedHash ||
        this.recovery.consumed_at !== null || this.recovery.expires_at <= now ||
        this.user.id !== userId || recoveryUserId !== userId) {
      return [{ meta: { changes: 0 } }, { meta: { changes: 0 } }, { meta: { changes: 0 } }];
    }
    this.user.password_hash = newHash;
    this.user.password_salt = newSalt;
    this.recovery.consumed_at = now;
    this.sessionVersion += 1;
    return [{ meta: { changes: 1 } }, { meta: { changes: 1 } }, { meta: { changes: 1 } }];
  }
}

test("JWTs are rejected after the account session version is incremented", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const request = new Request("https://api.example.test/private", {
    headers: { Authorization: "Bearer " + token }
  });
  assert.ok(await worker.authenticate(request, { DB: db, JWT_SECRET: secret }));
  db.sessionVersion = 1;
  assert.equal(await worker.authenticate(request, { DB: db, JWT_SECRET: secret }), null);
});

test("authentication rejects tokens without an explicit session version", async () => {
  const token = await worker.signToken(user, secret, 0);
  const parts = token.split(".");
  const payload = JSON.parse(new TextDecoder().decode(Buffer.from(parts[1], "base64url")));
  delete payload.sv;
  const unsigned = parts[0] + "." + Buffer.from(JSON.stringify(payload)).toString("base64url");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(unsigned));
  const legacyToken = unsigned + "." + Buffer.from(signature).toString("base64url");
  const db = { prepare() { return { bind() { return this; }, async first() { return { session_version: 0 }; } }; } };
  const request = new Request("https://api.example.test/private", {
    headers: { Authorization: "Bearer " + legacyToken }
  });
  assert.equal(await worker.authenticate(request, { DB: db, JWT_SECRET: secret }), null);
});

test("authentication rejects tokens when the account security row is missing", async () => {
  const token = await worker.signToken(user, secret, 0);
  const missingSecurityDB = {
    prepare() {
      return { bind() { return this; }, async first() { return null; } };
    }
  };
  const request = new Request("https://api.example.test/private", {
    headers: { Authorization: "Bearer " + token }
  });
  assert.equal(await worker.authenticate(request, {
    DB: missingSecurityDB,
    JWT_SECRET: secret
  }), null);
});

test("authentication fails closed when session security storage is unavailable", async () => {
  const token = await worker.signToken(user, secret, 0);
  const brokenDB = {
    prepare() { throw new Error("database unavailable"); }
  };
  const request = new Request("https://api.example.test/private", {
    headers: { Authorization: "Bearer " + token }
  });
  assert.equal(await worker.authenticate(request, {
    DB: brokenDB,
    JWT_SECRET: secret
  }), null);
});

test("registration issues a one-time 160-bit recovery code and stores only its salted digest", async () => {
  const db = new FakeDB();
  const response = await worker.default.fetch(new Request("https://api.example.test/api/register", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ displayName: "New User", username: "new_user", password: "new-secure-password" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 201);
  const data = await response.json();
  assert.match(data.recoveryCode, /^[A-F0-9]{40}$/);
  assert.ok(db.recovery.code_hash);
  assert.notEqual(db.recovery.code_hash, data.recoveryCode);
  assert.equal(db.recovery.expires_at > Math.floor(Date.now() / 1000), true);
});

test("concurrent registrations cannot claim equivalent Yemen local and international phone formats", async () => {
  const db = new FakeDB();
  db.users = [];
  const register = (username, phone) => worker.default.fetch(new Request("https://api.example.test/api/register", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ displayName: username, username, password: "new-secure-password", phone })
  }), { DB: db, JWT_SECRET: secret });
  const responses = await Promise.all([
    register("local_user", "0770000002"),
    register("intl_user", "+967770000002")
  ]);
  assert.deepEqual(responses.map(response => response.status).sort(), [201, 409]);
  assert.equal(db.users.length, 1);
});
 
test("login accepts a Yemen local phone when the account is stored internationally", async () => {
  const db = new FakeDB();
  db.user.password_hash = await worker.hashPassword("correct-password", db.user.password_salt);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username: "0700000001", password: "correct-password" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.equal(data.user.id, db.user.id);
  assert.ok(data.token);
});

test("recovery-code rotation requires the current password and replaces the previous code", async () => {
  const db = new FakeDB();
  db.user.password_hash = await worker.hashPassword("correct-password", db.user.password_salt);
  db.recovery = { code_hash: "old", code_salt: "salt", expires_at: 1, consumed_at: null };
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/recovery-code", {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: JSON.stringify({ password: "correct-password" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.match(data.recoveryCode, /^[A-F0-9]{40}$/);
  assert.notEqual(db.recovery.code_hash, "old");
});

test("password recovery consumes an expiring 160-bit code and invalidates the old session", async () => {
  const db = new FakeDB();
  const code = "A1B2C3D4E5F60718293A4B5C6D7E8F9012345678";
  const recoverySalt = "0123456789abcdef0123456789abcdef";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(recoverySalt + ":" + code));
  const codeHash = Array.from(new Uint8Array(digest)).map(value => value.toString(16).padStart(2, "0")).join("");
  db.recovery = { code_hash: codeHash, code_salt: recoverySalt, expires_at: Math.floor(Date.now() / 1000) + 3600, consumed_at: null };
  const token = await worker.signToken(user, secret, 0);
  const request = () => new Request("https://api.example.test/api/password/recover", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ identifier: "0700000001", recoveryCode: code.match(/.{1,4}/g).join(" "), newPassword: "new-secure-password" })
  });
  const env = { DB: db, JWT_SECRET: secret };
  const response = await worker.default.fetch(request(), env);
  assert.equal(response.status, 200);
  assert.ok(db.recovery.consumed_at);
  assert.equal(db.sessionVersion, 1);
  assert.notEqual(db.user.password_hash, user.password_hash);
  assert.equal(await worker.authenticate(new Request("https://api.example.test/private", {
    headers: { Authorization: "Bearer " + token }
  }), env), null);
  assert.equal((await worker.default.fetch(request(), env)).status, 400);
});

test("password recovery rejects expired recovery codes", async () => {
  const db = new FakeDB();
  const code = "A1B2C3D4E5F60718293A4B5C6D7E8F9012345678";
  const recoverySalt = "0123456789abcdef0123456789abcdef";
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(recoverySalt + ":" + code));
  const codeHash = Array.from(new Uint8Array(digest)).map(value => value.toString(16).padStart(2, "0")).join("");
  db.recovery = { code_hash: codeHash, code_salt: recoverySalt, expires_at: 1, consumed_at: null };
  const response = await worker.default.fetch(new Request("https://api.example.test/api/password/recover", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ identifier: user.username, recoveryCode: code, newPassword: "new-secure-password" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 400);
  assert.equal(db.sessionVersion, 0);
});

test("password recovery rate limits repeated attempts", async () => {
  const db = new FakeDB();
  const env = { DB: db, JWT_SECRET: secret };
  let status = 0;
  for (let i = 0; i < 6; i++) {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/password/recover", {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ identifier: user.username, recoveryCode: "A".repeat(40), newPassword: "new-secure-password" })
    }), env);
    status = response.status;
  }
  assert.equal(status, 429);
});

test("failed attachment message persistence deletes the uploaded Tigris object", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => sql.includes("SELECT 1 FROM friendships")
      ? { 1: 1 } : first();
    statement.run = async () => {
      if (sql.includes("INSERT INTO messages")) throw new Error("simulated message database failure");
      return run();
    };
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  const calls = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    calls.push(options.method);
    return new Response(null, { status: options.method === "PUT" ? 200 : 204 });
  };
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "image/jpeg",
        "X-Recipient-Id": "friend-1",
        "X-File-Name": "photo.jpg"
      },
      body: new Uint8Array([1, 2, 3])
    }), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 500);
    assert.deepEqual(calls, ["PUT", "DELETE"]);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("media download checks authorization before fetching object bytes", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const calls = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    calls.push(options.method);
    return new Response(null, {
      status: 200,
      headers: {
        "content-type": "image/jpeg",
        "x-amz-meta-ownerid": "another-user",
        "x-amz-meta-recipientid": "someone-else",
        "x-amz-meta-groupid": ""
      }
    });
  };
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media/another-user%2Ffile-1", {
      headers: { Authorization: "Bearer " + token }
    }), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 403);
    assert.deepEqual(calls, ["HEAD"]);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("authorized media download fetches bytes only after owner metadata is verified", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const calls = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    calls.push(options.method);
    if (options.method === "HEAD") {
      return new Response(null, {
        status: 200,
        headers: {
          "content-type": "image/jpeg",
          "x-amz-meta-ownerid": user.id,
          "x-amz-meta-filename": "photo%20one.jpg"
        }
      });
    }
    return new Response("image-bytes", { status: 200 });
  };
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media/user-1%2Ffile-1", {
      headers: { Authorization: "Bearer " + token }
    }), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 200);
    assert.deepEqual(calls, ["HEAD", "GET"]);
    assert.equal(response.headers.get("content-type"), "image/jpeg");
    assert.match(response.headers.get("content-disposition"), /photo%20one\.jpg/);
    assert.equal(await response.text(), "image-bytes");
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("media filenames are safely decoded and cannot contain path separators or control characters", () => {
  assert.equal(worker.safeFileName("..%2F..%5Csecret%0Aname.jpg"), ".._.._secret_name.jpg");
  assert.equal(worker.safeFileName("%E0%A4%A"), "%E0%A4%A");
  assert.equal(worker.safeFileName(""), "attachment");
});

test("phone normalization matches local and Yemen international forms", () => {
  const variants = worker.phoneVariants("+967 77 123 4567");
  assert.ok(variants.includes("967771234567"));
  assert.ok(variants.includes("771234567"));
  const internationalPrefix = worker.phoneVariants("00967 77 123 4567");
  assert.ok(internationalPrefix.includes("967771234567"));
  assert.ok(internationalPrefix.includes("771234567"));
  assert.deepEqual(worker.phoneVariants("invalid"), []);
  assert.ok(worker.phoneVariants("٠٧٧١٢٣٤٥٦٧").includes("0771234567"));
  assert.ok(worker.phoneVariants("۰۷۷۱۲۳۴۵۶۷").includes("0771234567"));
});


test("user search finds a Yemen account saved internationally when searched by local phone", async () => {
  const db = new FakeDB();
  db.searchCandidates = [{
    id: "searched-user",
    username: "yemen_user",
    display_name: "Yemen User",
    phone: "+967 77 123 4567"
  }];
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/users/search?q=0771234567",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.deepEqual(data.users.map(item => item.id), ["searched-user"]);
  assert.ok(db.userSearchQueries > 0);
  assert.match(db.lastUserSearchSql, /substr\(/);
});

test("phone search strips formatting from partial international numbers", async () => {
  const db = new FakeDB();
  db.searchCandidates = [{
    id: "formatted-search-user",
    username: "formatted_user",
    display_name: "Formatted User",
    phone: "+967 77 123 4567"
  }];
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/users/search?q=%2B967-77",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.deepEqual(data.users.map(item => item.id), ["formatted-search-user"]);
});

test("phone contact matching returns registered searchable accounts only", async () => {
  const db = new FakeDB();
  db.contactCandidates = [
    { id: "matched-user", username: "matched", display_name: "Matched", phone: "+967 77 123 4567" },
    { id: "other-user", username: "other", display_name: "Other", phone: "+967 71 555 4444" }
  ];
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/contacts/match", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ phones: ["0771234567"] })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.deepEqual(data.users.map(item => item.id), ["matched-user"]);
  assert.equal(db.contactLookupQueries, 1);
});

test("phone contact matching uses bounded queries beyond the former 10,000-user scan", async () => {
  const db = new FakeDB();
  db.contactCandidates = [
    { id: "late-match", username: "late", display_name: "Late", phone: "+967 77 123 4567" }
  ];
  const token = await worker.signToken(user, secret, 0);
  const phones = Array.from({ length: 500 }, (_, index) => "077" + String(index).padStart(7, "0"));
  phones[499] = "0771234567";
  const response = await worker.default.fetch(new Request("https://api.example.test/api/contacts/match", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ phones })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.deepEqual(data.users.map(item => item.id), ["late-match"]);
  assert.ok(db.contactLookupQueries > 1);
});

class FakeGroupDB extends FakeDB {
  constructor(member = true) {
    super();
    this.isGroupMember = member;
    this.groupMessages = [];
    this.failGroupNotificationLookup = false;
    this.groupHistoryQuery = "";
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const originalFirst = statement.first.bind(statement);
    const originalAll = statement.all.bind(statement);
    const originalRun = statement.run.bind(statement);
    statement.first = async () => {
      if (sql.includes("SELECT 1 FROM group_members WHERE group_id = ? AND user_id = ?")) {
        return this.isGroupMember ? { ok: 1 } : null;
      }
      if (sql.includes("SELECT name FROM chat_groups WHERE id = ?")) {
        if (this.failGroupNotificationLookup) throw new Error("notification lookup unavailable");
        return { name: "Test group" };
      }
      if (sql.includes("SELECT display_name FROM users WHERE id = ?")) return { display_name: "Tester" };
      return originalFirst();
    };
    statement.all = async () => {
      if (sql.includes("FROM (") && sql.includes("group_messages")) {
        this.groupHistoryQuery = sql;
        return { results: [] };
      }
      if (sql.includes("SELECT user_id FROM group_members WHERE group_id = ? AND user_id != ?")) {
        return { results: [{ user_id: "member-2" }] };
      }
      return originalAll();
    };
    statement.run = async () => {
      if (sql.includes("INSERT INTO group_messages")) this.groupMessages.push(statement.params);
      return originalRun();
    };
    return statement;
  }
}

test("group messages are accepted only from members and persisted", async () => {
  const db = new FakeGroupDB(true);
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/groups/group-1/messages", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ body: "Hello group" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 201);
  assert.equal(db.groupMessages.length, 1);
  assert.equal(db.groupMessages[0][1], "group-1");
  assert.equal(db.groupMessages[0][3], "Hello group");

  const outsider = new FakeGroupDB(false);
  const denied = await worker.default.fetch(new Request("https://api.example.test/api/groups/group-1/messages", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ body: "Should not pass" })
  }), { DB: outsider, JWT_SECRET: secret });
  assert.equal(denied.status, 404);
  assert.equal(outsider.groupMessages.length, 0);
});

class FakePrivateHistoryDB extends FakeDB {
  constructor() {
    super();
    this.privateHistoryQuery = "";
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const originalFirst = statement.first.bind(statement);
    const originalAll = statement.all.bind(statement);
    statement.first = async () => {
      if (sql.includes("SELECT 1 FROM friendships")) return { ok: 1 };
      if (sql.includes("SELECT read_receipts FROM user_privacy")) return { read_receipts: 0 };
      return originalFirst();
    };
    statement.all = async () => {
      if (sql.includes("FROM (") && sql.includes("receiver_id")) {
        this.privateHistoryQuery = sql;
        return { results: [] };
      }
      return originalAll();
    };
    return statement;
  }
}

class PrivateMessageFailureDB extends FakeDB {
  constructor() {
    super();
    this.savedMessages = 0;
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => {
      if (sql.includes("SELECT 1 FROM friendships")) return { ok: 1 };
      if (sql.includes("SELECT display_name FROM users")) throw new Error("sender lookup unavailable");
      return first();
    };
    statement.run = async () => {
      if (sql.includes("INSERT INTO messages")) this.savedMessages++;
      return run();
    };
    return statement;
  }
}

class FakeReadReceiptDB extends FakeDB {
  constructor(readReceipts) {
    super();
    this.readReceipts = readReceipts;
    this.readUpdates = 0;
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    const all = statement.all.bind(statement);
    statement.first = async () => {
      if (sql.includes("SELECT 1 FROM friendships")) return { ok: 1 };
      if (sql.includes("SELECT read_receipts FROM user_privacy")) return { read_receipts: this.readReceipts ? 1 : 0 };
      return first();
    };
    statement.run = async () => {
      if (sql.includes("UPDATE messages") && sql.includes("SET read_at")) this.readUpdates++;
      return run();
    };
    statement.all = async () => sql.includes("FROM (") && sql.includes("receiver_id")
      ? { results: [] } : all();
    return statement;
  }
}

test("profile updates reject an existing phone written in an equivalent local format", async () => {
  const db = new FakeDB();
  db.phoneCandidates = [{ id: "other-user", phone: "+967700000002" }];
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/profile", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ displayName: "Tester", phone: "٠٧٠٠٠٠٠٠٠٢" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 409);
  assert.ok(db.phoneLookupQueries > 0);
  assert.match(db.lastPhoneLookupSql, /replace\(phone, '٠', '0'\)/);
});

test("registration rejects an existing Yemen phone in local and international formats", async () => {
  const db = new FakeDB();
  db.phoneCandidates = [{ id: "registered-user", phone: "+967700000002" }];
  const response = await worker.default.fetch(new Request("https://api.example.test/api/register", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      displayName: "New User",
      username: "new_user",
      password: "secure-password-123",
      phone: "0700000002"
    })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 409);
  assert.ok(db.phoneLookupQueries > 0);
});

test("private read receipts respect the reader's privacy preference", async () => {
  for (const enabled of [false, true]) {
    const db = new FakeReadReceiptDB(enabled);
    const token = await worker.signToken(user, secret, 0);
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/messages?with=friend-1",
      { headers: { Authorization: "Bearer " + token } }
    ), { DB: db, JWT_SECRET: secret });
    assert.equal(response.status, 200);
    assert.equal(db.readUpdates, enabled ? 1 : 0);
  }
});

test("private history fetches the newest 100 messages in chronological order", async () => {
  const db = new FakePrivateHistoryDB();
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/messages?with=friend-2", {
    headers: { Authorization: "Bearer " + token }
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.match(db.privateHistoryQuery, /ORDER BY created_at DESC, id DESC\s+LIMIT 100/i);
  assert.match(db.privateHistoryQuery, /ORDER BY created_at ASC, id ASC/i);
});

test("group history fetches the newest 100 messages in chronological order", async () => {
  const db = new FakeGroupDB(true);
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/groups/group-1/messages", {
    headers: { Authorization: "Bearer " + token }
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.match(db.groupHistoryQuery, /ORDER BY gm\.created_at DESC, gm\.id DESC\s+LIMIT 100/i);
  assert.match(db.groupHistoryQuery, /ORDER BY created_at ASC, id ASC/i);
});

test("private message remains successful when notification sender lookup fails", async () => {
  const db = new PrivateMessageFailureDB();
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/messages", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ receiverId: "friend-1", body: "Persist this message" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 201);
  assert.equal(db.savedMessages, 1);
});

test("private message remains successful when FCM credentials are invalid", async () => {
  const db = new PrivateMessageFailureDB();
  // Allow sender lookup so dispatch reaches the FCM configuration parser.
  const originalPrepare = db.prepare.bind(db);
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const first = statement.first.bind(statement);
    statement.first = async () => sql.includes("SELECT display_name FROM users")
      ? { display_name: "Tester" } : first();
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/messages", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ receiverId: "friend-1", body: "Keep this message" })
  }), {
    DB: db,
    JWT_SECRET: secret,
    FCM_SERVICE_ACCOUNT_JSON: "not-valid-json"
  });
  assert.equal(response.status, 201);
  assert.equal(db.savedMessages, 1);
});

class PrivateMessageFcmHttpFailureDB extends FakeDB {
  constructor() {
    super();
    this.savedMessages = 0;
    this.deletedTokens = 0;
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const first = statement.first.bind(statement);
    const all = statement.all.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => {
      if (sql.includes("SELECT 1 FROM friendships")) return { ok: 1 };
      if (sql.includes("SELECT display_name FROM users")) return { display_name: "Tester" };
      return first();
    };
    statement.all = async () => sql.includes("SELECT fcm_token FROM device_tokens")
      ? { results: [{ fcm_token: "test-device-token" }] } : all();
    statement.run = async () => {
      if (sql.includes("INSERT INTO messages")) this.savedMessages++;
      if (sql.includes("DELETE FROM device_tokens")) this.deletedTokens++;
      return run();
    };
    return statement;
  }
}

test("private message remains successful when FCM returns an HTTP server error", async () => {
  const db = new PrivateMessageFcmHttpFailureDB();
  const token = await worker.signToken(user, secret, 0);
  const pair = await crypto.subtle.generateKey({
    name: "RSASSA-PKCS1-v1_5",
    modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]),
    hash: "SHA-256"
  }, true, ["sign", "verify"]);
  const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  const pem = "-----BEGIN PRIVATE KEY-----\\n" +
    Buffer.from(pkcs8).toString("base64").match(/.{1,64}/g).join("\\n") +
    "\\n-----END PRIVATE KEY-----";
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const logged = [];
  globalThis.fetch = async url => String(url).includes("oauth.example.test")
    ? new Response(JSON.stringify({ access_token: "test-access-token" }), {
        status: 200, headers: { "Content-Type": "application/json" }
      })
    : new Response("temporary FCM outage", { status: 503 });
  console.error = (...args) => logged.push(args);
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/messages", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ receiverId: "friend-1", body: "Persist despite FCM outage" })
    }), {
      DB: db,
      JWT_SECRET: secret,
      FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({
        client_email: "barq-test@example.test",
        private_key: pem,
        token_uri: "https://oauth.example.test/token",
        project_id: "barq-test"
      })
    });
    assert.equal(response.status, 201);
    assert.equal(db.savedMessages, 1);
    assert.equal(db.deletedTokens, 0);
    assert.ok(logged.some(args => args[0] === "FCM message send failed:" && args[1] === 503));
  } finally {
    globalThis.fetch = originalFetch;
    console.error = originalError;
  }
});

test("group message remains successful when FCM credentials are invalid", async () => {
  const db = new FakeGroupDB(true);
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/groups/group-1/messages", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ body: "Persist group message despite push config failure" })
  }), {
    DB: db,
    JWT_SECRET: secret,
    FCM_SERVICE_ACCOUNT_JSON: "not-valid-json"
  });
  assert.equal(response.status, 201);
  assert.equal(db.groupMessages.length, 1);
  assert.equal(db.groupMessages[0][1], "group-1");
  assert.equal(db.groupMessages[0][3], "Persist group message despite push config failure");
});

test("group message remains successful when push recipient lookup fails", async () => {
  const db = new FakeGroupDB(true);
  db.failGroupNotificationLookup = true;
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/groups/group-1/messages", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ body: "Saved even if notifications fail" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 201);
  assert.equal(db.groupMessages.length, 1);
});

test("BARQ does not create or expose friend requests; direct contacts remain separate", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const env = { DB: db, JWT_SECRET: secret };
  const headers = {
    Authorization: "Bearer " + token,
    "Content-Type": "application/json"
  };
  const send = await worker.default.fetch(new Request("https://api.example.test/api/friends/requests", {
    method: "POST",
    headers,
    body: JSON.stringify({ username: "matched" })
  }), env);
  assert.equal(send.status, 410);
  const list = await worker.default.fetch(new Request("https://api.example.test/api/friends/requests", {
    headers
  }), env);
  assert.equal(list.status, 200);
  assert.deepEqual(await list.json(), { incoming: [], outgoing: [] });
});

test("direct contact adding respects the target user's searchable privacy setting", async () => {
  const db = new FakeDB();
  db.targetUser = { id: "hidden-user", searchable: false };
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/contacts", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ userId: "hidden-user" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 404);
});


test("recovery migrations create only additive recovery tables", async () => {
  const migration = await readFile(new URL("../migrations/0001_recovery_codes.sql", import.meta.url), "utf8");
  assert.match(migration, /CREATE TABLE IF NOT EXISTS recovery_codes/i);
  assert.match(migration, /CREATE TABLE IF NOT EXISTS recovery_rate_limits/i);
  assert.match(migration, /CREATE INDEX IF NOT EXISTS idx_recovery_rate_limits_window/i);
  assert.match(migration, /FOREIGN KEY \(user_id\) REFERENCES users\(id\) ON DELETE CASCADE/i);
  assert.doesNotMatch(migration, /\b(DROP TABLE|DELETE FROM|ALTER TABLE)\b/i);
});

test("Wrangler is configured to discover D1 migrations", async () => {
  const config = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");
  assert.match(config, /migrations_dir\s*=\s*"migrations"/);
});

test("malformed JSON request bodies return 400 instead of 500", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/contacts/match", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: "{"
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "Invalid JSON body" });
});

test("oversized media Content-Length is rejected before Tigris upload", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const first = statement.first.bind(statement);
    statement.first = async () => sql.includes("SELECT 1 FROM friendships")
      ? { 1: 1 } : first();
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  const calls = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    calls.push(options.method);
    return new Response(null, { status: 200 });
  };
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "image/jpeg",
        "Content-Length": String(20 * 1024 * 1024 + 1),
        "X-Recipient-Id": "friend-1"
      },
      body: new Uint8Array([1, 2, 3])
    }), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 413);
    assert.deepEqual(await response.json(), { error: "File must be between 1 byte and 20 MB" });
    assert.deepEqual(calls, []);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});


class GroupInvitePermissionDB extends FakeDB {
  constructor(ownerId) {
    super();
    this.ownerId = ownerId;
    this.insertedMembers = 0;
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => {
      if (sql.includes("SELECT owner_id FROM chat_groups WHERE id = ?")) {
        return this.ownerId ? { owner_id: this.ownerId } : null;
      }
      if (sql.includes("SELECT id FROM users WHERE id = ?")) return { id: "new-member" };
      return first();
    };
    statement.run = async () => {
      if (sql.includes("INSERT OR IGNORE INTO group_members")) this.insertedMembers++;
      return run();
    };
    return statement;
  }
}

test("only the group owner can add members", async () => {
  const token = await worker.signToken(user, secret, 0);
  const request = () => new Request("https://api.example.test/api/groups/group-1/members", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ userId: "new-member" })
  });

  const nonOwnerDb = new GroupInvitePermissionDB("another-owner");
  const denied = await worker.default.fetch(request(), { DB: nonOwnerDb, JWT_SECRET: secret });
  assert.equal(denied.status, 403);
  assert.equal(nonOwnerDb.insertedMembers, 0);

  const ownerDb = new GroupInvitePermissionDB(user.id);
  const allowed = await worker.default.fetch(request(), { DB: ownerDb, JWT_SECRET: secret });
  assert.equal(allowed.status, 201);
  assert.equal(ownerDb.insertedMembers, 1);
});


test("login rate limit blocks repeated attempts by identifier and client", async () => {
  const db = new FakeDB();
  const wrongLogin = () => worker.default.fetch(new Request("https://api.example.test/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.10" },
    body: JSON.stringify({ username: "tester", password: "incorrect-password" })
  }), { DB: db, JWT_SECRET: secret });

  for (let i = 0; i < 10; i++) {
    assert.equal((await wrongLogin()).status, 401);
  }
  const blocked = await wrongLogin();
  assert.equal(blocked.status, 429);
  assert.equal(blocked.headers.get("Retry-After"), "900");
});

test("login rate limit separates client IP buckets", async () => {
  const db = new FakeDB();
  const attempt = (ip, username) => worker.default.fetch(new Request("https://api.example.test/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify({ username, password: "incorrect-password" })
  }), { DB: db, JWT_SECRET: secret });
  // Use a different identifier each time so this exercises only the client-IP bucket.
  for (let i = 0; i < 10; i++) await attempt("203.0.113.11", "unknown-" + i);
  assert.equal((await attempt("203.0.113.12", "unknown-final")).status, 401);
});


test("JWT verification rejects unsupported algorithms and oversized tokens", async () => {
  const token = await worker.signToken(user, secret, 0);
  const parts = token.split(".");
  const unsupportedHeader = Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url");
  const unsigned = unsupportedHeader + "." + parts[1];
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(unsigned));
  const forgedProfile = unsigned + "." + Buffer.from(signature).toString("base64url");
  assert.equal(await worker.verifyToken(forgedProfile, secret), null);
  assert.equal(await worker.verifyToken("x".repeat(8193), secret), null);
  assert.ok(await worker.verifyToken(token, secret));
});


test("password recovery also limits attempts across many identifiers from one client", async () => {
  const db = new FakeDB();
  const env = { DB: db, JWT_SECRET: secret };
  const attempt = (identifier, ip) => worker.default.fetch(new Request("https://api.example.test/api/password/recover", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify({ identifier, recoveryCode: "A".repeat(40), newPassword: "new-secure-password" })
  }), env);
  for (let i = 0; i < 20; i++) {
    const response = await attempt("unknown-account-" + i, "203.0.113.30");
    assert.equal(response.status, 400);
  }
  assert.equal((await attempt("another-unknown-account", "203.0.113.30")).status, 429);
  assert.equal((await attempt("different-client-account", "203.0.113.31")).status, 400);
});


test("registration rate limit blocks mass account creation from one client", async () => {
  const db = new FakeDB();
  const env = { DB: db, JWT_SECRET: secret };
  const register = username => worker.default.fetch(new Request("https://api.example.test/api/register", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.40" },
    body: JSON.stringify({ displayName: "New User", username, password: "secure-password-123" })
  }), env);
  for (let i = 0; i < 20; i++) {
    assert.equal((await register("newuser" + i)).status, 201);
  }
  const blocked = await register("newuserfinal");
  assert.equal(blocked.status, 429);
  assert.equal(blocked.headers.get("Retry-After"), "900");
});


test("partial privacy updates preserve previously disabled settings", async () => {
  const db = new FakeDB();
  db.privacySettings = { searchable: 1, read_receipts: 0 };
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/privacy", {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: JSON.stringify({ searchable: false })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.deepEqual(db.privacySettings, { searchable: 0, read_receipts: 0 });
});


test("partial notification updates preserve previously disabled categories", async () => {
  const db = new FakeDB();
  db.notificationSettings = { messages: 1, groups: 0, statuses: 0 };
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/notification-settings", {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: JSON.stringify({ messages: false })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.deepEqual(db.notificationSettings, { messages: 0, groups: 0, statuses: 0 });
});
