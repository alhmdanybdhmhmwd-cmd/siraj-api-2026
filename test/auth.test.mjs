import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const workerPath = new URL("../src/src/index.js", import.meta.url);
let workerSource = await readFile(workerPath, "utf8");
const summarySource = await readFile(new URL("../src/src/conversation_summary.js", import.meta.url), "utf8");
const adapterSource = await readFile(new URL("../src/src/runtime_adapters.js", import.meta.url), "utf8");
const notificationSource = await readFile(new URL("../src/src/notification_service.js", import.meta.url), "utf8");
workerSource = workerSource.replace(
  'import { prepareConversationSummaryTranscript, buildConversationSummaryMessages, extractConversationSummaryText } from "./conversation_summary.js";',
  summarySource
);
const runtimeAdapterImport = workerSource.split("\n").find(line => line.includes("runtime_adapters.js"));
workerSource = workerSource.replace(runtimeAdapterImport, adapterSource.replaceAll("export function ", "function "));
workerSource = workerSource.replace(
  'import { sendBarqPushNotification } from "./notification_service.js";',
  notificationSource
    .replace('import { createPushProvider } from "./runtime_adapters.js";', '')
    .replaceAll("export async function ", "async function ")
);
workerSource = workerSource.replace('import { AwsClient } from "aws4fetch";', `
class AwsClient {
  async fetch(url, options) {
    return globalThis.__fakeTigrisHandler(url, options);
  }
}
`);
workerSource = workerSource.replace(
  'import { handleResumableMediaUpload, cleanupExpiredUploadSessions } from "./media_multipart_routes.js";',
  'const handleResumableMediaUpload = async () => null; const cleanupExpiredUploadSessions = async () => ({ expired: 0 });'
);
const workerModulePath = `/tmp/barq-auth-worker-${process.pid}.mjs`;
await writeFile(workerModulePath, workerSource, "utf8");
const worker = await import(pathToFileURL(workerModulePath).href);

test("profile image validation accepts JPEG, PNG, and WebP signatures", () => {
  assert.equal(worker.detectProfileImageType(Uint8Array.from([0xff, 0xd8, 0xff, 0x00])), "image/jpeg");
  assert.equal(worker.detectProfileImageType(Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])), "image/png");
  assert.equal(worker.detectProfileImageType(Uint8Array.from([
    0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50
  ])), "image/webp");
  assert.equal(worker.detectProfileImageType(Uint8Array.from([0x3c, 0x73, 0x76, 0x67])), null);
  assert.equal(worker.detectProfileImageType(new Uint8Array()), null);
});

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
    this.transcriptionRateLimit = null;

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
        if (sql.includes("SELECT 1 AS ok")) {
          if (db.readinessProbeThrows) throw new Error("simulated D1 outage");
          return db.readinessProbeResult === undefined ? { ok: 1 } : db.readinessProbeResult;
        }
        if (sql.includes("SELECT session_version FROM account_security")) {
          return { session_version: db.sessionVersion };
        }
        if (sql.includes("SELECT 1 FROM revoked_sessions")) {
          db.lastRevocationQuery = sql;
          db.lastRevocationParams = this.params;
          return db.revokedSessions?.has(this.params[0]) ? { 1: 1 } : null;
        }
        if (sql.includes("SELECT 1 FROM friendships")) {
          return db.friendshipAllowed === false ? null : { 1: 1 };
        }
        if (sql.includes("FROM group_members mine")) {
          return db.sharedGroupAllowed === true ? { 1: 1 } : null;
        }
        if (sql.includes("SELECT object_key, content_type, updated_at FROM profile_photos")) {
          return db.profilePhoto ? { ...db.profilePhoto } : null;
        }
        if (sql.includes("SELECT 1 FROM group_members")) return { 1: 1 };
        if (sql.includes("SELECT searchable FROM user_privacy WHERE user_id = ?")) {
          return db.targetPrivacy ? { ...db.targetPrivacy } : null;
        }
        if (sql.includes("SELECT searchable, read_receipts FROM user_privacy")) {
          return db.privacySettings ? { ...db.privacySettings } : null;
        }
        if (sql.includes("SELECT messages, groups, statuses FROM notification_preferences")) {
          return db.notificationSettings ? { ...db.notificationSettings } : null;
        }
        if (sql.includes("AS enabled FROM notification_preferences")) {
          const category = sql.includes("SELECT statuses AS enabled") ? "statuses"
            : sql.includes("SELECT groups AS enabled") ? "groups" : "messages";
          return db.notificationSettings ? { enabled: db.notificationSettings[category] } : null;
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
        if (sql.includes("SELECT attempts FROM transcription_rate_limits")) {
          return { attempts: db.transcriptionRateLimit?.attempts || 0 };
        }
        return null;
      },
      async all() {
        if (sql.includes("FROM ephemeral_messages")) {
          return { results: db.ephemeralRows || [] };
        }
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
          db.lastContactLookupSql = sql;
          db.lastContactLookupParams = this.params;
          return { results: db.contactCandidates };
        }
        if (sql.includes("FROM friendships f") && sql.includes("JOIN users u")) {
          return { results: db.friendList || [] };
        }
        if (sql.includes("SELECT fcm_token FROM device_tokens")) {
          return { results: db.deviceTokenRows || [] };
        }
        if (sql.includes("FROM messages") && sql.includes("ORDER BY created_at DESC")) {
          db.lastMessageQuery = sql;
          db.lastMessageParams = this.params;
          return { results: db.messageRows || [] };
        }
        if (sql.includes("FROM group_messages") && sql.includes("ORDER BY gm.created_at DESC")) {
          db.lastGroupMessageQuery = sql;
          db.lastGroupMessageParams = this.params;
          return { results: db.groupMessageRows || [] };
        }
        return { results: [] };
      },
      async run() {
        if (sql.includes("INSERT INTO ephemeral_messages")) {
          db.ephemeralRows ??= [];
          const [id, senderId, receiverId, body] = this.params;
          db.ephemeralRows.push({
            id, sender_id: senderId, receiver_id: receiverId, body,
            created_at: Math.floor(Date.now() / 1000), read_at: null, delete_at: null
          });
        }
        if (sql.includes("UPDATE ephemeral_messages") && sql.includes("SET read_at")) {
          const now = Math.floor(Date.now() / 1000);
          db.ephemeralRows = (db.ephemeralRows || []).map(row =>
            row.sender_id === this.params[0] && row.receiver_id === this.params[1] && row.read_at == null
              ? { ...row, read_at: now, delete_at: now + 10 }
              : row
          );
          return { meta: { changes: 1 } };
        }
        if (sql.includes("DELETE FROM ephemeral_messages WHERE id = ?")) {
          assert.ok(sql.includes("delete_at <= unixepoch()"));
          const before = (db.ephemeralRows || []).length;
          db.ephemeralRows = (db.ephemeralRows || []).filter(row => row.id !== this.params[0]);
          return { meta: { changes: before - db.ephemeralRows.length } };
        }
        if (sql.includes("DELETE FROM ephemeral_messages WHERE delete_at IS NOT NULL")) {
          db.ephemeralCleanupCutoff = this.params[0];
          return { meta: { changes: db.expiredEphemeralCount || 0 } };
        }
        if (sql.includes("DELETE FROM revoked_sessions WHERE expires_at <= ?")) {
          db.revokedSessionCleanupCutoff = this.params[0];
          return { meta: { changes: db.expiredRevokedSessionsCount || 0 } };
        }
        if (sql.includes("INSERT INTO status_posts")) {
          db.statusPosts ??= [];
          db.statusPosts.push(this.params);
        }
        if (sql.includes("INSERT INTO device_tokens")) {
          db.deviceTokens ??= new Map();
          db.deviceTokens.set(this.params[1], this.params[0]);
        }
        if (sql.includes("DELETE FROM device_tokens")) {
          db.deviceTokens ??= new Map();
          if (db.deviceTokens.get(this.params[1]) === this.params[0]) {
            db.deviceTokens.delete(this.params[1]);
            return { meta: { changes: 1 } };
          }
          return { meta: { changes: 0 } };
        }
        if (sql.includes("UPDATE messages SET read_at")) {
          db.readReceiptUpdate = { sql, params: this.params };
        }
        if (sql.includes("INSERT OR IGNORE INTO account_security")) db.sessionVersion ??= 0;
        if (sql.includes("INSERT OR IGNORE INTO revoked_sessions")) {
          db.revokedSessions ??= new Set();
          db.revokedSessions.add(this.params[0]);
        }
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
        if (sql.includes("INSERT INTO transcription_rate_limits")) {
          const [userId, now, windowStart] = this.params;
          const current = db.transcriptionRateLimit;
          db.transcriptionRateLimit = !current || current.windowStarted <= windowStart
            ? { userId, windowStarted: now, attempts: 1 }
            : { ...current, attempts: current.attempts + 1 };
        }
        if (sql.includes("INSERT INTO recovery_codes")) {
          db.recovery = { code_hash: this.params[1], code_salt: this.params[2], expires_at: this.params[3], consumed_at: null };
        }
        return { meta: { changes: 1 } };
      }
    };
  }

  async batch(statements) {
    if (statements.length === 2 && statements[0].sql.includes("INSERT OR IGNORE INTO friendships")) {
      this.friendshipInserts = statements.map(statement => statement.params);
      return [{ meta: { changes: 1 } }, { meta: { changes: 1 } }];
    }
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



test("ephemeral send stores only in its isolated table and requires a friend", async () => {
  const db = new FakeDB();
  db.friendshipAllowed = true;
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/ephemeral-messages",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ receiverId: "friend-1", body: "one-time text" })
    }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 201);
  const payload = await response.json();
  assert.match(payload.id, /^[0-9a-f-]{36}$/i);
  assert.equal(db.ephemeralRows.length, 1);
  assert.deepEqual(
    [db.ephemeralRows[0].sender_id, db.ephemeralRows[0].receiver_id, db.ephemeralRows[0].body],
    [user.id, "friend-1", "one-time text"]
  );
  assert.equal(db.messageRows, undefined);
  assert.equal(db.deviceTokens, undefined);
});

test("ephemeral send rejects non-friends, self messages and oversized text", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const post = body => worker.default.fetch(new Request(
    "https://api.example.test/api/ephemeral-messages",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    }
  ), { DB: db, JWT_SECRET: secret });

  db.friendshipAllowed = false;
  assert.equal((await post({ receiverId: "stranger", body: "hello" })).status, 403);
  db.friendshipAllowed = true;
  assert.equal((await post({ receiverId: user.id, body: "hello" })).status, 400);
  assert.equal((await post({ receiverId: "friend-1", body: "x".repeat(5001) })).status, 400);
  assert.equal(db.ephemeralRows?.length || 0, 0);
});

test("ephemeral history requires an existing friend relationship", async () => {
  const db = new FakeDB();
  db.friendshipAllowed = false;
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/ephemeral-messages?with=stranger",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 403);
  assert.equal(db.ephemeralRows, undefined);
});

test("ephemeral messages start the ten-second TTL on recipient read and schedule physical deletion", async () => {
  const db = new FakeDB();
  db.ephemeralRows = [{
    id: "ephemeral-1",
    sender_id: "friend-1",
    receiver_id: user.id,
    body: "one-time text",
    created_at: Math.floor(Date.now() / 1000),
    read_at: null,
    delete_at: null
  }];
  const token = await worker.signToken(user, secret, 0);
  const originalSetTimeout = globalThis.setTimeout;
  const delays = [];
  const pending = [];
  globalThis.setTimeout = (callback, delay, ...args) => {
    delays.push(delay);
    queueMicrotask(() => callback(...args));
    return 0;
  };
  try {
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/ephemeral-messages?with=friend-1",
      { headers: { Authorization: "Bearer " + token } }
    ), { DB: db, JWT_SECRET: secret }, {
      waitUntil(promise) { pending.push(promise); }
    });
    assert.equal(response.status, 200);
    const payload = await response.json();
    assert.equal(payload.messages.length, 1);
    assert.ok(payload.messages[0].read_at);
    assert.ok(payload.messages[0].delete_at >= payload.messages[0].read_at + 10);
    assert.equal(delays.length, 1);
    assert.ok(delays[0] >= 0 && delays[0] <= 10000);
    await Promise.all(pending);
    assert.deepEqual(db.ephemeralRows, []);
  } finally {
    globalThis.setTimeout = originalSetTimeout;
  }
});


test("opening an ephemeral conversation as sender does not start or extend the recipient TTL", async () => {
  const db = new FakeDB();
  db.friendshipAllowed = true;
  db.ephemeralRows = [{
    id: "ephemeral-sender-read",
    sender_id: user.id,
    receiver_id: "friend-1",
    body: "one-time text",
    created_at: Math.floor(Date.now() / 1000),
    read_at: null,
    delete_at: null
  }];
  const senderToken = await worker.signToken(user, secret, 0);
  const senderResponse = await worker.default.fetch(new Request(
    "https://api.example.test/api/ephemeral-messages?with=friend-1",
    { headers: { Authorization: "Bearer " + senderToken } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(senderResponse.status, 200);
  assert.equal(db.ephemeralRows[0].read_at, null);
  assert.equal(db.ephemeralRows[0].delete_at, null);

  const recipient = { ...user, id: "friend-1" };
  const recipientToken = await worker.signToken(recipient, secret, 0);
  const recipientRequest = () => worker.default.fetch(new Request(
    "https://api.example.test/api/ephemeral-messages?with=" + user.id,
    { headers: { Authorization: "Bearer " + recipientToken } }
  ), { DB: db, JWT_SECRET: secret });

  assert.equal((await recipientRequest()).status, 200);
  const firstReadAt = db.ephemeralRows[0].read_at;
  const firstDeleteAt = db.ephemeralRows[0].delete_at;
  assert.ok(firstReadAt);
  assert.equal(firstDeleteAt, firstReadAt + 10);

  assert.equal((await recipientRequest()).status, 200);
  assert.equal(db.ephemeralRows[0].read_at, firstReadAt);
  assert.equal(db.ephemeralRows[0].delete_at, firstDeleteAt);
});

test("profile photo upload rejects mismatched image bytes before contacting storage", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  let storageCalled = false;
  globalThis.__fakeTigrisHandler = async () => {
    storageCalled = true;
    return new Response(null, { status: 200 });
  };
  try {
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/profile/photo/me",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer " + token,
          "Content-Type": "image/png"
        },
        body: Uint8Array.from([0x3c, 0x73, 0x76, 0x67])
      }
    ), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 415);
    assert.equal(storageCalled, false);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});


test("profile photo upload enforces the 4 MiB limit before storage", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  let storageCalled = false;
  globalThis.__fakeTigrisHandler = async () => {
    storageCalled = true;
    return new Response(null, { status: 200 });
  };
  try {
    const bytes = new Uint8Array(4 * 1024 * 1024 + 1);
    bytes.set([0xff, 0xd8, 0xff]);
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/profile/photo/me",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer " + token,
          "Content-Type": "image/jpeg"
        },
        body: bytes
      }
    ), {
      DB: db, JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 413);
    assert.equal(storageCalled, false);
    assert.match((await response.json()).error, /4 MiB/);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

class ProfileOwnershipTestDB extends FakeDB {
  constructor() {
    super();
    this.profileUpdateParams = null;
    this.profileUpdateSql = null;
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => {
      if (sql.includes("SELECT u.id, u.username, u.display_name, u.phone")) {
        return { id: user.id, username: user.username, display_name: "Updated Name", phone: "+967700000002" };
      }
      return first();
    };
    statement.run = async () => {
      if (sql.includes("UPDATE users SET display_name = ? WHERE id = ?")) {
        this.profileUpdateParams = statement.params;
        this.profileUpdateSql = sql;
        assert.match(sql, /WHERE id = \?/);
        return { meta: { changes: 1 } };
      }
      return run();
    };
    return statement;
  }
}

test("profile updates are always scoped to the authenticated account despite a spoofed target userId", async () => {
  const db = new ProfileOwnershipTestDB();
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/profile", {
    method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: JSON.stringify({
      userId: "victim-account",
      displayName: "Updated Name",
      phone: "+967700000002"
    })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.deepEqual(db.profileUpdateParams, ["Updated Name", user.id]);
  assert.equal(db.profileUpdateParams[1], user.id);
  assert.notEqual(db.profileUpdateParams[1], "victim-account");
  assert.doesNotMatch(db.profileUpdateSql, /SET[^]*\bphone\s*=/i);
});

test("profile photo reads deny non-friends when the target profile is private", async () => {
  const db = new FakeDB();
  db.friendshipAllowed = false;
  db.targetPrivacy = { searchable: 0 };
  let storageCalled = false;
  globalThis.__fakeTigrisHandler = async () => {
    storageCalled = true;
    return new Response(Uint8Array.from([0xff, 0xd8, 0xff]));
  };
  try {
    const token = await worker.signToken(user, secret, 0);
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/profile/photo/friend-2",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db, JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 403);
    assert.equal(storageCalled, false);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("discoverable public profiles can show photos without a friendship", async () => {
  const db = new FakeDB();
  db.friendshipAllowed = false;
  db.targetPrivacy = { searchable: 1 };
  db.profilePhoto = {
    object_key: "profiles/public-user/photo-object",
    content_type: "image/jpeg",
    updated_at: "2026-11-20 12:00:00"
  };
  const image = Uint8Array.from([0xff, 0xd8, 0xff, 0x01]);
  globalThis.__fakeTigrisHandler = async () => new Response(image, { status: 200 });
  try {
    const token = await worker.signToken(user, secret, 0);
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/profile/photo/public-user",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db, JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 200);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), image);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("shared group members can view each other's private profile photos", async () => {
  const db = new FakeDB();
  db.friendshipAllowed = false;
  db.sharedGroupAllowed = true;
  db.profilePhoto = {
    object_key: "profiles/group-member/photo-object",
    content_type: "image/webp",
    updated_at: "2026-11-20 12:00:00"
  };
  const image = Uint8Array.from([0x52, 0x49, 0x46, 0x46, 0x00, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50]);
  globalThis.__fakeTigrisHandler = async () => new Response(image, { status: 200 });
  try {
    const token = await worker.signToken(user, secret, 0);
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/profile/photo/group-member",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db, JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "image/webp");
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), image);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("authorized friends receive private profile photo bytes with safe cache headers", async () => {
  const db = new FakeDB();
  db.profilePhoto = {
    object_key: "profiles/friend-2/photo-object",
    content_type: "image/jpeg",
    updated_at: "2026-11-20 12:00:00"
  };
  const image = Uint8Array.from([0xff, 0xd8, 0xff, 0x01]);
  let requestedUrl = "";
  globalThis.__fakeTigrisHandler = async (url, options) => {
    requestedUrl = url;
    assert.equal(options.method, "GET");
    return new Response(image, { status: 200 });
  };
  try {
    const token = await worker.signToken(user, secret, 0);
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/profile/photo/friend-2",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db, JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "image/jpeg");
    assert.equal(response.headers.get("cache-control"), "private, max-age=300");
    assert.equal(response.headers.get("vary"), "Authorization");
    assert.equal(response.headers.get("x-content-type-options"), "nosniff");
    assert.equal(response.headers.get("x-frame-options"), "DENY");
    assert.equal(response.headers.get("content-security-policy"), "default-src 'none'; base-uri 'none'; frame-ancestors 'none'");
    assert.equal(response.headers.get("referrer-policy"), "no-referrer");
    assert.equal(response.headers.get("strict-transport-security"), "max-age=31536000");
    assert.equal(response.headers.get("x-permitted-cross-domain-policies"), "none");
    assert.ok(requestedUrl.includes("profiles/friend-2/photo-object"));
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), image);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("recipient read schedules physical ephemeral deletion after the ten-second TTL", async () => {
  const db = new FakeDB();
  db.ephemeralRows = [{
    id: "ephemeral-1",
    sender_id: "friend-1",
    receiver_id: user.id,
    body: "temporary",
    created_at: Math.floor(Date.now() / 1000),
    read_at: null,
    delete_at: null
  }];
  const token = await worker.signToken(user, secret, 0);
  const pending = [];
  const originalSetTimeout = globalThis.setTimeout;
  const originalNow = Date.now;
  let clockAdvance = 0;
  Date.now = () => originalNow() + clockAdvance;
  globalThis.setTimeout = callback => {
    clockAdvance = 11_000;
    callback();
    return 0;
  };
  try {
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/ephemeral-messages?with=friend-1",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db,
      JWT_SECRET: secret
    }, {
      waitUntil(promise) { pending.push(promise); }
    });
    assert.equal(response.status, 200);
    const data = await response.json();
    assert.equal(data.messages.length, 1);
    assert.ok(data.messages[0].read_at);
    assert.equal(data.messages[0].delete_at, data.messages[0].read_at + 10);
    assert.equal(pending.length, 1);
    await Promise.all(pending);
    assert.equal(db.ephemeralRows.length, 0);
  } finally {
    globalThis.setTimeout = originalSetTimeout;
    Date.now = originalNow;
  }
});

test("sender viewing an ephemeral conversation does not mark outgoing messages as read", async () => {
  const db = new FakeDB();
  db.ephemeralRows = [{
    id: "ephemeral-outgoing",
    sender_id: user.id,
    receiver_id: "friend-1",
    body: "sent but not yet read",
    created_at: Math.floor(Date.now() / 1000),
    read_at: null,
    delete_at: null
  }];
  const token = await worker.signToken(user, secret, 0);
  const pending = [];
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/ephemeral-messages?with=friend-1",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret }, {
    waitUntil(promise) { pending.push(promise); }
  });
  assert.equal(response.status, 200);
  const payload = await response.json();
  assert.equal(payload.messages.length, 1);
  assert.equal(payload.messages[0].read_at, null);
  assert.equal(payload.messages[0].delete_at, null);
  assert.equal(db.ephemeralRows[0].read_at, null);
  assert.equal(pending.length, 0);
});

test("scheduled ephemeral cleanup removes rows at or before the expiry cutoff", async () => {
  const db = new FakeDB();
  db.expiredEphemeralCount = 3;
  const now = Date.UTC(2026, 10, 20, 12, 0, 20);
  const result = await worker.cleanupExpiredEphemeralMessages({ DB: db }, now);
  assert.deepEqual(result, {
    deleted: 3,
    cutoff: Math.floor(now / 1000)
  });
  assert.equal(db.ephemeralCleanupCutoff, Math.floor(now / 1000));
});

test("private conversation pagination uses a stable cursor and marks only returned incoming messages read", async () => {
  const db = new FakeDB();
  db.messageRows = [
    { id: "older-extra", sender_id: "friend-1", receiver_id: user.id, created_at: "2026-11-18 10:00:00", read_at: null },
    { id: "page-item", sender_id: "friend-1", receiver_id: user.id, created_at: "2026-11-18 11:00:00", read_at: null }
  ];
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/messages?with=friend-1&limit=1&before=2026-11-18%2012%3A00%3A00&beforeId=latest",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.deepEqual(data.messages.map(item => item.id), ["page-item"]);
  assert.equal(data.hasMore, true);
  assert.deepEqual(data.nextCursor, { before: "2026-11-18 11:00:00", beforeId: "page-item" });
  assert.match(db.lastMessageQuery, /created_at < \? OR \(created_at = \? AND id < \?\)/);
  assert.deepEqual(db.lastMessageParams.slice(-4), [
    "2026-11-18 12:00:00", "2026-11-18 12:00:00", "latest", 2
  ]);
  assert.deepEqual(db.readReceiptUpdate.params, ["friend-1", user.id, "page-item"]);
});

test("private conversation rejects incomplete pagination cursors", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/messages?with=friend-1&before=2026-11-18",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 400);
  assert.equal(db.lastMessageQuery, undefined);
});

test("group conversation pagination uses the same stable cursor contract", async () => {
  const db = new FakeDB();
  db.groupMessageRows = [
    { id: "older-extra", group_id: "group-1", sender_id: "friend-1", created_at: "2026-11-18 10:00:00" },
    { id: "page-item", group_id: "group-1", sender_id: "friend-1", created_at: "2026-11-18 11:00:00" }
  ];
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/groups/group-1/messages?limit=1&before=2026-11-18%2012%3A00%3A00&beforeId=latest",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.deepEqual(data.messages.map(item => item.id), ["page-item"]);
  assert.equal(data.hasMore, true);
  assert.deepEqual(data.nextCursor, { before: "2026-11-18 11:00:00", beforeId: "page-item" });
  assert.match(db.lastGroupMessageQuery, /gm.created_at < \? OR \(gm.created_at = \? AND gm.id < \?\)/);
  assert.deepEqual(db.lastGroupMessageParams, [
    "group-1", user.id, "2026-11-18 12:00:00", "2026-11-18 12:00:00", "latest", 2
  ]);
});

test("status publishing is rate limited per authenticated account", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const env = { DB: db, JWT_SECRET: secret };
  let response;
  for (let i = 0; i < 11; i++) {
    response = await worker.default.fetch(new Request("https://api.example.test/api/statuses", {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ content: "Status " + i })
    }), env);
  }
  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "900");
});

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
    body: JSON.stringify({ displayName: "New User", phone: "+967700000009", password: "new-secure-password" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 201);
  const data = await response.json();
  assert.match(data.recoveryCode, /^[A-F0-9]{40}$/);
  assert.ok(db.recovery.code_hash);
  assert.notEqual(db.recovery.code_hash, data.recoveryCode);
  assert.equal(db.recovery.expires_at > Math.floor(Date.now() / 1000), true);
});

test("registration accepts international numbers and generates a private handle when username is omitted", async () => {
  const db = new FakeDB();
  const response = await worker.default.fetch(new Request("https://api.example.test/api/register", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      displayName: "International User",
      phone: "+447911123456",
      password: "secure-password-123"
    })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 201);
  const data = await response.json();
  assert.equal(data.user.phone, "+447911123456");
  assert.match(data.user.username, /^barq[a-f0-9]{12}$/);
});

test("concurrent registrations cannot claim equivalent Yemen local and international phone formats", async () => {
  const db = new FakeDB();
  db.users = [];
  const register = (username, phone) => worker.default.fetch(new Request("https://api.example.test/api/register", {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ displayName: username, username, password: "new-secure-password", phone })
  }), { DB: db, JWT_SECRET: secret });
  const responses = await Promise.all([
    register("local_user", "+967770000002"),
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


test("failed storage rollback revokes access but retains expiration record for retry", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  const cleanupStatements = [];
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => sql.includes("SELECT 1 FROM friendships")
      ? { 1: 1 } : first();
    statement.run = async () => {
      if (sql.includes("INSERT INTO messages")) throw new Error("simulated message database failure");
      if (sql.includes("DELETE FROM media_access") || sql.includes("DELETE FROM media_expirations")) {
        cleanupStatements.push(sql);
      }
      return run();
    };
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  const calls = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    calls.push(options.method);
    if (options.method === "DELETE") throw new Error("simulated Tigris deletion outage");
    return new Response(null, { status: 200 });
  };
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "image/jpeg",
        "X-Recipient-Id": "friend-1",
        "X-File-Name": "rollback.jpg"
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
    assert.ok(cleanupStatements.some(sql => sql.includes("DELETE FROM media_access")));
    assert.ok(!cleanupStatements.some(sql => sql.includes("DELETE FROM media_expirations")));
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

test("user directory search is rate limited per authenticated account", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const request = () => worker.default.fetch(new Request(
    "https://api.example.test/api/users/search?q=ab",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  for (let i = 0; i < 120; i++) {
    assert.equal((await request()).status, 200);
  }
  const blocked = await request();
  assert.equal(blocked.status, 429);
  assert.equal(blocked.headers.get("Retry-After"), "900");
});

test("bulk contact matching is rate limited per authenticated account", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const request = () => worker.default.fetch(new Request(
    "https://api.example.test/api/contacts/match",
    {
      method: "POST",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ phones: ["0771234567"] })
    }
  ), { DB: db, JWT_SECRET: secret });
  for (let i = 0; i < 30; i++) {
    assert.equal((await request()).status, 200);
  }
  const blocked = await request();
  assert.equal(blocked.status, 429);
  assert.equal(blocked.headers.get("Retry-After"), "900");
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
  assert.match(db.lastContactLookupSql, /COALESCE\(\(SELECT searchable FROM user_privacy WHERE user_id = users\.id\), 1\) = 1/);
  assert.match(db.lastContactLookupSql, /WHERE id != \?/);
  assert.equal(db.lastContactLookupParams[0], user.id);
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
      if (sql.includes("JOIN chat_groups g") && sql.includes("m.joined_at")) {
        this.groupMemberListQuery = sql;
        return { results: this.groupMemberRows || [] };
      }
      if (sql.includes("FROM (") && sql.includes("group_messages")) {
        this.groupHistoryQuery = sql;
        this.groupHistoryParams = statement.params;
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

test("group members can view the roster and owner role but outsiders cannot", async () => {
  const db = new FakeGroupDB(true);
  db.groupMemberRows = [
    { id: user.id, username: user.username, display_name: user.display_name, photo_updated_at: "2026-11-20 12:00:00", is_owner: 1 },
    { id: "member-2", username: "member_two", display_name: "Member Two", photo_updated_at: "2026-11-20 12:01:00", is_owner: 0 }
  ];
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/groups/group-1/members",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  const data = await response.json();
  assert.deepEqual(data.members.map(item => item.id), [user.id, "member-2"]);
  assert.equal(data.members[0].is_owner, 1);
  assert.equal(data.members[1].photo_updated_at, "2026-11-20 12:01:00");
  assert.match(db.groupMemberListQuery, /LEFT JOIN profile_photos p ON p\.user_id = u\.id/);
  assert.match(db.groupMemberListQuery, /p\.updated_at AS photo_updated_at/);
  assert.match(db.groupMemberListQuery, /JOIN chat_groups g/);

  const outsider = new FakeGroupDB(false);
  const denied = await worker.default.fetch(new Request(
    "https://api.example.test/api/groups/group-1/members",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: outsider, JWT_SECRET: secret });
  assert.equal(denied.status, 404);
});

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
        this.privateHistoryParams = statement.params;
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

class IdempotentPrivateMessageDB extends FakeDB {
  constructor() {
    super();
    this.messagesById = new Map();
    this.messageInsertAttempts = 0;
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => {
      if (sql.includes("SELECT sender_id, receiver_id, body, reply_to_id FROM messages WHERE id = ?")) {
        return this.messagesById.get(statement.params[0]) || null;
      }
      if (sql.includes("SELECT 1 FROM friendships")) return { 1: 1 };
      if (sql.includes("SELECT display_name FROM users")) throw new Error("sender lookup unavailable");
      return first();
    };
    statement.run = async () => {
      if (sql.includes("INSERT INTO messages")) {
        this.messageInsertAttempts++;
        const [id, senderId, receiverId, body, replyToId] = statement.params;
        if (this.messagesById.has(id)) return { meta: { changes: 0 } };
        this.messagesById.set(id, {
          sender_id: senderId,
          receiver_id: receiverId,
          body,
          reply_to_id: replyToId || null,
        });
        return { meta: { changes: 1 } };
      }
      return run();
    };
    return statement;
  }
}

test("offline outbox retries are idempotent and reject client ID conflicts", async () => {
  const db = new IdempotentPrivateMessageDB();
  const token = await worker.signToken(user, secret, 0);
  const clientMessageId = "a1b2c3d4e5f60708a1b2c3d4e5f60708";
  const send = body => worker.default.fetch(new Request("https://api.example.test/api/messages", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ receiverId: "friend-1", body, clientMessageId })
  }), { DB: db, JWT_SECRET: secret });

  const first = await send("Persist once");
  assert.equal(first.status, 201);
  assert.equal((await first.json()).id, clientMessageId);

  const retry = await send("Persist once");
  assert.equal(retry.status, 200);
  assert.deepEqual(await retry.json(), {
    message: "Message already accepted",
    id: clientMessageId,
    duplicate: true
  });
  assert.equal(db.messagesById.size, 1);

  const conflict = await send("Different content with the same ID");
  assert.equal(conflict.status, 409);
  assert.equal(db.messagesById.size, 1);
  assert.equal(db.messageInsertAttempts, 3);
});

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
      ? { results: [{
          id: "incoming-1", sender_id: "friend-1", receiver_id: user.id,
          created_at: "2026-11-18 10:00:00", read_at: null
        }] } : all();
    return statement;
  }
}

test("profile updates ignore legacy phone changes after registration", async () => {
  const db = new ProfileOwnershipTestDB();
  db.phoneCandidates = [{ id: "other-user", phone: "+967700000002" }];
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/profile", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ displayName: "Tester", phone: "+967700000002" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.equal(db.phoneLookupQueries || 0, 0, "profile edits must not run phone replacement lookups");
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
      phone: "+967700000002"
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
  assert.match(db.privateHistoryQuery, /ORDER BY created_at DESC, id DESC\s+LIMIT \?/i);
  assert.match(db.privateHistoryQuery, /ORDER BY created_at ASC, id ASC/i);
  assert.equal(db.privateHistoryParams.at(-1), 101);
});

test("group history fetches the newest 100 messages in chronological order", async () => {
  const db = new FakeGroupDB(true);
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/groups/group-1/messages", {
    headers: { Authorization: "Bearer " + token }
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.match(db.groupHistoryQuery, /LEFT JOIN profile_photos p ON p\.user_id = u\.id/);
  assert.match(db.groupHistoryQuery, /p\.updated_at AS photo_updated_at/);
  assert.match(db.groupHistoryQuery, /ORDER BY gm\.created_at DESC, gm\.id DESC\s+LIMIT \?/i);
  assert.match(db.groupHistoryQuery, /ORDER BY created_at ASC, id ASC/i);
  assert.equal(db.groupHistoryParams.at(-1), 101);
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

test("status remains published when friend notification lookup fails", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const all = statement.all.bind(statement);
    statement.all = async () => {
      if (sql.includes("SELECT friend_id FROM friendships")) {
        throw new Error("simulated notification lookup failure");
      }
      return all();
    };
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/statuses", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ content: "Status stays published" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 201);
  assert.equal(db.statusPosts.length, 1);
  assert.equal(db.statusPosts[0][2], "Status stays published");
});

test("status pushes honor the statuses preference and use the status notification channel", async () => {
  const db = new FakeDB();
  db.notificationSettings = { messages: 0, groups: 0, statuses: 1 };
  db.deviceTokenRows = [{ fcm_token: "device-token" }];
  const pair = await crypto.subtle.generateKey({
    name: "RSASSA-PKCS1-v1_5", modulusLength: 2048,
    publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256"
  }, true, ["sign", "verify"]);
  const privateKey = Buffer.from(await crypto.subtle.exportKey("pkcs8", pair.privateKey)).toString("base64");
  const account = {
    client_email: "barq-test@example.test",
    project_id: "barq-test",
    token_uri: "https://oauth2.example.test/token",
    private_key: "-----BEGIN PRIVATE KEY-----\\n" + privateKey + "\\n-----END PRIVATE KEY-----"
  };
  const originalFetch = globalThis.fetch;
  let sentMessage = null;
  globalThis.fetch = async (url, options = {}) => {
    if (String(url).includes("oauth2.example.test")) {
      return new Response(JSON.stringify({ access_token: "test-access-token" }), { status: 200 });
    }
    sentMessage = JSON.parse(options.body);
    return new Response(JSON.stringify({ name: "projects/barq-test/messages/1" }), { status: 200 });
  };
  try {
    await worker.sendSirajPush({
      DB: db,
      FCM_SERVICE_ACCOUNT_JSON: JSON.stringify(account)
    }, "recipient-1", user.id, "Tester", "unused preview", { category: "statuses" });
    assert.equal(sentMessage.message.data.type, "status_update");
    assert.equal(sentMessage.message.notification.title, "SPARK جديد من Tester");
    assert.equal(sentMessage.message.android.notification.channel_id, "barq_statuses");
    assert.equal(sentMessage.message.notification.body, "شارك لحظة جديدة في SPARK");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("device tokens can be registered and revoked for the authenticated account", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const headers = {
    Authorization: "Bearer " + token,
    "Content-Type": "application/json"
  };
  const register = await worker.default.fetch(new Request("https://api.example.test/api/devices/token", {
    method: "POST", headers, body: JSON.stringify({ fcmToken: "fcm-device-token-123" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(register.status, 200);
  assert.equal(db.deviceTokens.get("fcm-device-token-123"), user.id);

  const revoke = await worker.default.fetch(new Request("https://api.example.test/api/devices/token", {
    method: "DELETE", headers, body: JSON.stringify({ fcmToken: "fcm-device-token-123" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(revoke.status, 200);
  assert.equal((await revoke.json()).removed, 1);
  assert.equal(db.deviceTokens.has("fcm-device-token-123"), false);
  assert.match(revoke.headers.get("access-control-allow-methods"), /DELETE/);
});

test("contacts can be added directly and appear in the contact list without friend requests", async () => {
  const db = new FakeDB();
  db.targetUser = { id: "friend-1", searchable: true };
  const token = await worker.signToken(user, secret, 0);
  const headers = {
    Authorization: "Bearer " + token,
    "Content-Type": "application/json"
  };
  const added = await worker.default.fetch(new Request("https://api.example.test/api/contacts", {
    method: "POST", headers, body: JSON.stringify({ userId: "friend-1" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(added.status, 201);
  assert.deepEqual(db.friendshipInserts, [[user.id, "friend-1"], ["friend-1", user.id]]);

  db.friendList = [{
    id: "friend-1", username: "friend", display_name: "Friend", phone: "+967771234567"
  }];
  const listed = await worker.default.fetch(new Request("https://api.example.test/api/friends", {
    headers: { Authorization: "Bearer " + token }
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(listed.status, 200);
  assert.deepEqual((await listed.json()).friends, [{
    id: "friend-1", username: "friend", displayName: "Friend", phone: "+967771234567"
  }]);
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
  assert.ok(config.includes('migrations_dir = "migrations/production"'));
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



test("declared oversized JSON bodies are rejected before authentication work", async () => {
  const db = new FakeDB();
  let bodyCancelled = false;
  const request = new Request("https://api.example.test/api/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Content-Length": String(256 * 1024 + 1)
    },
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new TextEncoder().encode(JSON.stringify({
          username: "tester",
          password: "not-used"
        })));
      },
      cancel() { bodyCancelled = true; }
    }),
    duplex: "half"
  });
  const response = await worker.default.fetch(request, {
    DB: db,
    JWT_SECRET: secret
  });
  assert.equal(response.status, 413);
  assert.deepEqual(await response.json(), {
    error: "JSON request body is too large"
  });
  assert.equal(db.lastLoginQuery, undefined);
  assert.equal(bodyCancelled, true, "declared oversized bodies cancel the unread stream");
});

test("chunked oversized JSON requests are rejected before route processing", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  let cancelled = false;
  const request = new Request("https://api.example.test/api/contacts/match", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new Uint8Array(256 * 1024));
        controller.enqueue(new Uint8Array(1));
      },
      cancel() { cancelled = true; }
    }),
    duplex: "half"
  });
  assert.equal(request.headers.has("Content-Length"), false);
  const response = await worker.default.fetch(request, { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 413);
  assert.deepEqual(await response.json(), { error: "JSON request body is too large" });
  assert.equal(cancelled, true);
});



test("chat attachments are retained without automatic 72-hour expiry", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  let savedExpiry = null;
  let savedAccess = null;
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => sql.includes("SELECT 1 FROM friendships")
      ? { 1: 1 } : first();
    statement.run = async () => {
      if (sql.includes("INSERT INTO media_expirations")) savedExpiry = statement.params[1];
      if (sql.includes("INSERT INTO media_access")) {
        savedAccess = {
          sql,
          params: [...statement.params]
        };
      }
      return run();
    };
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  let storageExpiry = null;
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    if (options.method === "PUT") storageExpiry = options.headers["x-amz-meta-expiresat"];
    return new Response(null, { status: 200 });
  };
  try {
    const before = Date.now();
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "image/jpeg",
        "X-Recipient-Id": "friend-1"
      },
      body: new Uint8Array([1, 2, 3])
    }), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 201);
    const permanentExpiry = "9999-12-31T23:59:59.999Z";
    assert.equal(savedExpiry, null, "successful chat attachments must not enter scheduled expiry cleanup");
    assert.equal(storageExpiry, permanentExpiry);
    assert.ok(savedAccess, "upload must persist a D1 authorization row");
    assert.match(savedAccess.sql, /INSERT INTO media_access/);
    assert.deepEqual(savedAccess.params.slice(0, 6), [
      (await response.json()).attachment.id,
      user.id,
      "friend-1",
      null,
      "attachment",
      "image/jpeg"
    ]);
    assert.equal(savedAccess.params[6], permanentExpiry);
    assert.equal(Date.parse(savedAccess.params[6]), Date.parse(permanentExpiry));
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});



test("group attachment upload persists permanent group-scoped access without a private recipient", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  let savedAccess = null;
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const run = statement.run.bind(statement);
    statement.run = async () => {
      if (sql.includes("INSERT INTO media_access")) {
        savedAccess = [...statement.params];
      }
      return run();
    };
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  const storageCalls = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    storageCalls.push({ method: options.method, headers: options.headers });
    return new Response(null, { status: 200 });
  };
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/pdf",
        "X-Group-Id": "group-42",
        "X-File-Name": "report.pdf"
      },
      body: new Uint8Array([1, 2, 3])
    }), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 201);
    const result = await response.json();
    assert.ok(savedAccess, "group upload must persist a D1 authorization row");
    assert.deepEqual(savedAccess.slice(0, 6), [
      result.attachment.id,
      user.id,
      null,
      "group-42",
      "report.pdf",
      "application/pdf"
    ]);
    assert.equal(savedAccess.length, 7);
    assert.equal(savedAccess[6], "9999-12-31T23:59:59.999Z");
    assert.equal(storageCalls.length, 1);
    assert.equal(storageCalls[0].method, "PUT");
    assert.equal(storageCalls[0].headers["x-amz-meta-groupid"], "group-42");
    assert.equal(storageCalls[0].headers["x-amz-meta-expiresat"], savedAccess[6]);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});






test("attachment upload rolls back the stored object and D1 access rows when message persistence fails", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  const cleanupStatements = [];
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const first = statement.first.bind(statement);
    const run = statement.run.bind(statement);
    statement.first = async () => sql.includes("SELECT 1 FROM friendships") ? { 1: 1 } : first();
    statement.run = async () => {
      if (sql.includes("INSERT INTO messages")) throw new Error("simulated message persistence failure");
      if (sql.includes("DELETE FROM media_access") || sql.includes("DELETE FROM media_expirations")) {
        cleanupStatements.push(sql);
      }
      return run();
    };
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  const storageMethods = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    storageMethods.push(options.method);
    return new Response(null, { status: options.method === "DELETE" ? 204 : 200 });
  };
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "image/jpeg",
        "X-Recipient-Id": "friend-1"
      },
      body: new Uint8Array([0xff, 0xd8, 0xff])
    }), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 500);
    assert.deepEqual(storageMethods, ["PUT", "DELETE"]);
    assert.ok(cleanupStatements.some(sql => sql.includes("DELETE FROM media_access")));
    assert.ok(cleanupStatements.some(sql => sql.includes("DELETE FROM media_expirations")));
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("attachment upload stops before storage when the destination friendship is missing", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const first = statement.first.bind(statement);
    statement.first = async () => sql.includes("SELECT 1 FROM friendships") ? null : first();
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  const storageMethods = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    storageMethods.push(options.method);
    return new Response(null, { status: 200 });
  };
  try {
    const response = await worker.default.fetch(new Request("https://api.example.test/api/media", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "image/jpeg",
        "X-Recipient-Id": "not-a-contact"
      },
      body: new Uint8Array([0xff, 0xd8, 0xff])
    }), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 403);
    assert.deepEqual(storageMethods, []);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("expired attachment is denied and deleted before any media bytes are downloaded", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const methods = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    methods.push(options.method);
    if (options.method === "HEAD") {
      return new Response(null, {
        status: 200,
        headers: {
          "x-amz-meta-ownerid": user.id,
          "x-amz-meta-expiresat": "2020-01-01T00:00:00.000Z"
        }
      });
    }
    return new Response(null, { status: 204 });
  };
  try {
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/media/user-1/old-video",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 410);
    assert.deepEqual(await response.json(), { error: "Attachment has expired" });
    assert.deepEqual(methods, ["HEAD", "DELETE"]);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("expired attachment cleanup record is retained when Tigris deletion fails", async () => {
  const db = new FakeDB();
  const originalPrepare = db.prepare.bind(db);
  db.expirationRowDeletes = 0;
  db.prepare = sql => {
    const statement = originalPrepare(sql);
    const run = statement.run.bind(statement);
    statement.run = async () => {
      if (sql.includes("DELETE FROM media_expirations")) db.expirationRowDeletes++;
      return run();
    };
    return statement;
  };
  const token = await worker.signToken(user, secret, 0);
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    if (options.method === "HEAD") {
      return new Response(null, {
        status: 200,
        headers: {
          "x-amz-meta-ownerid": user.id,
          "x-amz-meta-expiresat": "2020-01-01T00:00:00.000Z"
        }
      });
    }
    return new Response("temporary storage failure", { status: 503 });
  };
  try {
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/media/user-1/expired-object",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 410);
    assert.equal(db.expirationRowDeletes, 0);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("media expiration cleanup deletes only objects whose individual 72-hour deadline passed", async () => {
  const cutoff = Date.parse("2026-11-22T12:00:00.000Z");
  const rows = [
    { object_key: "user-1/expired-video", expires_at: "2026-11-22T11:59:59.000Z" },
    { object_key: "user-1/newer-photo", expires_at: "2026-11-22T22:00:00.000Z" }
  ];
  const removedRows = [];
  const removedAccessRows = [];
  const db = {
    prepare(sql) {
      const statement = {
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          if (sql.startsWith("DELETE FROM media_expirations")) removedRows.push(this.params[0]);
          if (sql.startsWith("DELETE FROM media_access")) removedAccessRows.push(this.params[0]);
          return { meta: { changes: 1 } };
        },
        async all() {
          return { results: rows.filter(row => row.expires_at <= this.params[0]) };
        }
      };
      return statement;
    }
  };
  const deletedObjects = [];
  globalThis.__fakeTigrisHandler = async (url, options) => {
    deletedObjects.push({ url: String(url), method: options.method });
    return new Response(null, { status: 204 });
  };
  try {
    const result = await worker.cleanupExpiredMedia({
      DB: db,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    }, cutoff);
    assert.deepEqual(result, { checked: 1, deleted: 1 });
    assert.equal(deletedObjects.length, 1);
    assert.match(deletedObjects[0].url, /expired-video$/);
    assert.deepEqual(removedRows, ["user-1/expired-video"]);
    assert.deepEqual(removedAccessRows, ["user-1/expired-video"]);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("rate limit cleanup removes only buckets older than 24 hours", async () => {
  const statements = [];
  const db = {
    prepare(sql) {
      return {
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          statements.push({ sql, params: this.params });
          return { meta: { changes: 3 } };
        }
      };
    }
  };
  const now = Date.parse("2026-11-19T12:00:00.000Z");
  const result = await worker.cleanupExpiredRateLimits({ DB: db }, now);
  const cutoff = Math.floor(now / 1000) - 24 * 60 * 60;
  assert.deepEqual(result, {
    login_rate_limits: 3,
    recovery_rate_limits: 3,
    transcription_rate_limits: 3
  });
  assert.equal(statements.length, 3);
  assert.ok(statements.every(item => item.sql.includes("window_started < ?")));
  assert.ok(statements.every(item => item.params[0] === cutoff));
});

test("revoked session cleanup removes only expired token hashes", async () => {
  const statements = [];
  const db = {
    prepare(sql) {
      return {
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          statements.push({ sql, params: this.params });
          return { meta: { changes: 4 } };
        }
      };
    }
  };
  const now = Date.parse("2026-11-20T12:00:00.000Z");
  const result = await worker.cleanupExpiredRevokedSessions({ DB: db }, now);
  const cutoff = Math.floor(now / 1000);
  assert.deepEqual(result, { deleted: 4, cutoff });
  assert.equal(statements.length, 1);
  assert.equal(statements[0].sql, "DELETE FROM revoked_sessions WHERE expires_at <= ?");
  assert.deepEqual(statements[0].params, [cutoff]);
});

test("media expiration cleanup continues after one storage deletion fails", async () => {
  const cutoff = Date.parse("2026-11-22T12:00:00.000Z");
  const rows = [
    { object_key: "user-1/failing-video", expires_at: "2026-11-22T11:00:00.000Z" },
    { object_key: "user-1/expired-photo", expires_at: "2026-11-22T11:30:00.000Z" }
  ];
  const removedRows = [];
  const removedAccessRows = [];
  const db = {
    prepare(sql) {
      const statement = {
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          if (sql.startsWith("DELETE FROM media_expirations")) removedRows.push(this.params[0]);
          if (sql.startsWith("DELETE FROM media_access")) removedAccessRows.push(this.params[0]);
          return { meta: { changes: 1 } };
        },
        async all() { return { results: rows.filter(row => row.expires_at <= this.params[0]) }; }
      };
      return statement;
    }
  };
  const attempted = [];
  globalThis.__fakeTigrisHandler = async (url, options) => {
    const key = String(url).split("/").pop();
    attempted.push(key);
    if (key === "failing-video") throw new Error("temporary storage failure");
    return new Response(null, { status: 204 });
  };
  try {
    const result = await worker.cleanupExpiredMedia({
      DB: db, TIGRIS_ACCESS_KEY_ID: "test-access", TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    }, cutoff);
    assert.deepEqual(result, { checked: 2, deleted: 1 });
    assert.deepEqual(attempted, ["failing-video", "expired-photo"]);
    assert.deepEqual(removedRows, ["user-1/expired-photo"]);
    assert.deepEqual(removedAccessRows, ["user-1/expired-photo"]);
    assert.ok(!removedAccessRows.includes("user-1/failing-video"));
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("unauthorized users cannot trigger deletion of an expired attachment", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  const methods = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    methods.push(options.method);
    if (options.method === "HEAD") {
      return new Response(null, { status: 200, headers: {
        "x-amz-meta-ownerid": "someone-else",
        "x-amz-meta-recipientid": "another-user",
        "x-amz-meta-expiresat": "2020-01-01T00:00:00.000Z"
      }});
    }
    return new Response(null, { status: 204 });
  };
  try {
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/media/someone-else/old-file",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db, JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access", TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 403);
    assert.deepEqual(methods, ["HEAD"]);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});

test("media expiration cleanup schedule runs every 15 minutes", async () => {
  const config = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");
  assert.match(config, /crons\s*=\s*\["\*\/15 \* \* \* \*"\]/);
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
        "Content-Length": String(60 * 1024 * 1024 + 1),
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
    assert.deepEqual(await response.json(), { error: "File must be between 1 byte and 60 MB" });
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

test("JWT verification rejects malformed identity and expiry claim types", async () => {
  const valid = await worker.signToken(user, secret, 0);
  const [header] = valid.split(".");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signPayload = async payload => {
    const unsigned = header + "." + Buffer.from(JSON.stringify(payload)).toString("base64url");
    const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(unsigned));
    return unsigned + "." + Buffer.from(signature).toString("base64url");
  };
  const payload = JSON.parse(Buffer.from(valid.split(".")[1], "base64url").toString("utf8"));
  for (const invalid of [
    { ...payload, sub: 42 },
    { ...payload, sub: "   " },
    { ...payload, exp: String(payload.exp) },
    { ...payload, exp: payload.exp + 0.5 },
    { ...payload, exp: Math.floor(Date.now() / 1000) }
  ]) {
    assert.equal(await worker.verifyToken(await signPayload(invalid), secret), null);
  }
  assert.ok(await worker.verifyToken(valid, secret));
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
  let registrationIndex = 0;
  const register = username => worker.default.fetch(new Request("https://api.example.test/api/register", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": "203.0.113.40" },
    body: JSON.stringify({ displayName: "New User", username, phone: "+1202555" + String(registrationIndex++).padStart(4, "0"), password: "secure-password-123" })
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


test("login identifier rate limit normalizes local and international phone formats", async () => {
  const db = new FakeDB();
  const attempt = (username, ip) => worker.default.fetch(new Request("https://api.example.test/api/login", {
    method: "POST",
    headers: { "Content-Type": "application/json", "CF-Connecting-IP": ip },
    body: JSON.stringify({ username, password: "incorrect-password" })
  }), { DB: db, JWT_SECRET: secret });
  for (let i = 0; i < 10; i++) {
    assert.equal((await attempt("0771234567", "203.0.113.50")).status, 401);
  }
  // A different IP and +967 formatting must not bypass the same account bucket.
  assert.equal((await attempt("+967 771 234 567", "203.0.113.51")).status, 429);
});
test("liveness probe stays available without database or secrets", async () => {
  const response = await worker.default.fetch(new Request("https://api.example.test/health/live"), {});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "alive", service: "barq-api" });
});

test("readiness probe fails closed when configuration or D1 is unavailable", async () => {
  const missingConfig = await worker.default.fetch(new Request("https://api.example.test/health/ready"), {});
  assert.equal(missingConfig.status, 503);
  const unavailableDb = new FakeDB();
  unavailableDb.readinessProbeThrows = true;
  const dbFailure = await worker.default.fetch(new Request("https://api.example.test/health/ready"), { DB: unavailableDb, JWT_SECRET: secret });
  assert.equal(dbFailure.status, 503);
  const badProbe = new FakeDB();
  badProbe.readinessProbeResult = { ok: 0 };
  const invalidResult = await worker.default.fetch(new Request("https://api.example.test/health/ready"), { DB: badProbe, JWT_SECRET: secret });
  assert.equal(invalidResult.status, 503);
  const readyDb = new FakeDB();
  const ready = await worker.default.fetch(new Request("https://api.example.test/health/ready"), { DB: readyDb, JWT_SECRET: secret });
  assert.equal(ready.status, 200);
  assert.deepEqual(await ready.json(), { status: "ready", service: "barq-api" });
});


test("logout revokes only the current bearer token and leaves another device session valid", async () => {
  const db = new FakeDB();
  const firstToken = await worker.signToken(user, secret, 0);
  const secondToken = await worker.signToken({ ...user, username: "tester-device-2" }, secret, 0);
  const env = { DB: db, JWT_SECRET: secret };
  const logout = await worker.default.fetch(new Request("https://api.example.test/api/logout", {
    method: "POST",
    headers: { Authorization: "Bearer " + firstToken }
  }), env);
  assert.equal(logout.status, 200);
  const firstSession = await worker.authenticate(new Request("https://api.example.test/api/me", {
    headers: { Authorization: "Bearer " + firstToken }
  }), env);
  const secondSession = await worker.authenticate(new Request("https://api.example.test/api/me", {
    headers: { Authorization: "Bearer " + secondToken }
  }), env);
  assert.equal(firstSession, null);
  assert.equal(secondSession.sub, user.id);
  assert.match(db.lastRevocationQuery, /expires_at > unixepoch\(\)/);
  assert.equal(db.lastRevocationParams[1], user.id);
  assert.equal(db.revokedSessions.has(firstToken), false, "raw bearer token must never be stored");
  assert.equal(db.revokedSessions.size, 1);
});


test("bounded request reader rejects oversized streaming bodies without Content-Length", async () => {
  const maxBytes = 2 * 1024 * 1024;
  let cancelled = false;
  const body = new ReadableStream({
    start(controller) {
      controller.enqueue(new Uint8Array(maxBytes));
      controller.enqueue(new Uint8Array(1));
    },
    cancel() { cancelled = true; }
  });
  const request = new Request("https://api.example.test/api/transcribe", {
    method: "POST",
    headers: { "Content-Type": "audio/webm" },
    body,
    duplex: "half"
  });
  assert.equal(request.headers.has("Content-Length"), false);
  assert.equal(await worker.readRequestBodyLimited(request, maxBytes), null);
  assert.equal(cancelled, true);
});

test("bounded request reader accepts a body exactly at the configured limit", async () => {
  const request = new Request("https://api.example.test/api/transcribe", {
    method: "POST",
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(Uint8Array.from([1, 2]));
        controller.enqueue(Uint8Array.from([3, 4]));
        controller.close();
      }
    }),
    duplex: "half"
  });
  assert.deepEqual(
    Array.from(await worker.readRequestBodyLimited(request, 4)),
    [1, 2, 3, 4]
  );
});

test("transcription route accepts supported audio and returns only the transcript", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  let inferenceInput;
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/transcribe",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "audio/webm"
      },
      body: Uint8Array.from([1, 2, 3, 4])
    }
  ), {
    DB: db,
    JWT_SECRET: secret,
    AI: { async run(model, input) { inferenceInput = { model, input }; return { text: "  مرحبًا بك  " }; } }
  });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { text: "مرحبًا بك" });
  assert.equal(inferenceInput.model, "@cf/openai/whisper");
  assert.deepEqual(inferenceInput.input.audio, [1, 2, 3, 4]);
  assert.equal(db.transcriptionRateLimit.attempts, 1);
});

test("transcription route enforces the per-account hourly inference limit", async () => {
  const db = new FakeDB();
  const now = Math.floor(Date.now() / 1000);
  db.transcriptionRateLimit = { userId: user.id, windowStarted: now, attempts: 10 };
  const token = await worker.signToken(user, secret, 0);
  let inferenceCalls = 0;
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/transcribe",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "audio/webm"
      },
      body: Uint8Array.from([1, 2, 3])
    }
  ), {
    DB: db,
    JWT_SECRET: secret,
    AI: { async run() { inferenceCalls++; return { text: "not allowed" }; } }
  });
  assert.equal(response.status, 429);
  assert.equal(db.transcriptionRateLimit.attempts, 11);
  assert.equal(inferenceCalls, 0);
});

test("transcription route requires authentication before reading audio or invoking AI", async () => {
  const db = new FakeDB();
  let inferenceCalls = 0;
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/transcribe",
    {
      method: "POST",
      headers: { "Content-Type": "audio/webm" },
      body: Uint8Array.from([1, 2, 3])
    }
  ), {
    DB: db,
    JWT_SECRET: secret,
    AI: { async run() { inferenceCalls++; return { text: "must not run" }; } }
  });
  assert.equal(response.status, 401);
  assert.equal(db.transcriptionRateLimit, null);
  assert.equal(inferenceCalls, 0);
});

test("transcription route rejects unsupported content types before counting or inference", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  let inferenceCalls = 0;
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/transcribe",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/octet-stream"
      },
      body: Uint8Array.from([1, 2, 3])
    }
  ), {
    DB: db,
    JWT_SECRET: secret,
    AI: { async run() { inferenceCalls++; return { text: "not allowed" }; } }
  });
  assert.equal(response.status, 415);
  assert.equal(db.transcriptionRateLimit, null);
  assert.equal(inferenceCalls, 0);
});

test("transcription route rejects oversized chunked audio before inference", async () => {
  const db = new FakeDB();
  const token = await worker.signToken(user, secret, 0);
  let inferenceCalls = 0;
  const request = new Request("https://api.example.test/api/transcribe", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "audio/webm"
    },
    body: new ReadableStream({
      start(controller) {
        controller.enqueue(new Uint8Array(2 * 1024 * 1024));
        controller.enqueue(new Uint8Array(1));
      }
    }),
    duplex: "half"
  });
  const response = await worker.default.fetch(request, {
    DB: db,
    JWT_SECRET: secret,
    AI: { async run() { inferenceCalls++; return { text: "unexpected" }; } }
  });
  assert.equal(response.status, 413);
  assert.equal(inferenceCalls, 0);
});


class MediaAccessTestDB extends FakeDB {
  constructor(accessRow, options = {}) {
    super();
    this.mediaAccessRow = accessRow;
    this.friendshipAllowed = options.friendshipAllowed !== false;
    this.groupMemberAllowed = options.groupMemberAllowed !== false;
  }
  prepare(sql) {
    const statement = super.prepare(sql);
    const first = statement.first.bind(statement);
    statement.first = async () => {
      if (sql.includes("FROM media_access WHERE object_key = ?")) {
        return this.mediaAccessRow ? { ...this.mediaAccessRow } : null;
      }
      if (sql.includes("SELECT 1 FROM friendships")) {
        return this.friendshipAllowed ? { 1: 1 } : null;
      }
      if (sql.includes("SELECT 1 FROM group_members")) {
        return this.groupMemberAllowed ? { 1: 1 } : null;
      }
      return first();
    };
    return statement;
  }
}

test("new media downloads authorize owner, private recipient, and group member before storage lookup", async () => {
  const token = await worker.signToken(user, secret, 0);
  const cases = [
    {
      name: "owner",
      row: { owner_id: user.id, recipient_id: "friend-1", group_id: null, file_name: "photo.jpg", content_type: "image/jpeg", expires_at: "2099-01-01T00:00:00.000Z" },
      options: {},
      expected: 200
    },
    {
      name: "private recipient",
      row: { owner_id: "sender-1", recipient_id: user.id, group_id: null, file_name: "photo.jpg", content_type: "image/jpeg", expires_at: "2099-01-01T00:00:00.000Z" },
      options: { friendshipAllowed: true },
      expected: 200
    },
    {
      name: "group member",
      row: { owner_id: "sender-1", recipient_id: null, group_id: "group-1", file_name: "photo.jpg", content_type: "image/jpeg", expires_at: "2099-01-01T00:00:00.000Z" },
      options: { groupMemberAllowed: true },
      expected: 200
    }
  ];

  for (const item of cases) {
    const db = new MediaAccessTestDB(item.row, item.options);
    const methods = [];
    globalThis.__fakeTigrisHandler = async (_url, options) => {
      methods.push(options.method);
      if (options.method === "HEAD") {
        return new Response(null, { status: 200, headers: {
          "content-type": "image/jpeg",
          "x-amz-meta-filename": "photo.jpg"
        }});
      }
      return new Response("image-bytes", { status: 200 });
    };
    try {
      const response = await worker.default.fetch(new Request(
        "https://api.example.test/api/media/sender-1/object-1",
        { headers: { Authorization: "Bearer " + token } }
      ), {
        DB: db, JWT_SECRET: secret,
        TIGRIS_ACCESS_KEY_ID: "test-access",
        TIGRIS_SECRET_ACCESS_KEY: "test-secret"
      });
      assert.equal(response.status, item.expected, item.name);
      assert.deepEqual(methods, ["HEAD", "GET"], item.name);
    } finally {
      delete globalThis.__fakeTigrisHandler;
    }
  }
});

test("new media download denies outsiders before making any storage request", async () => {
  const db = new MediaAccessTestDB({
    owner_id: "owner-2",
    recipient_id: "recipient-2",
    group_id: "group-2",
    file_name: "private.pdf",
    content_type: "application/pdf",
    expires_at: "2099-01-01T00:00:00.000Z"
  }, { friendshipAllowed: false, groupMemberAllowed: false });
  const token = await worker.signToken(user, secret, 0);
  const methods = [];
  globalThis.__fakeTigrisHandler = async (_url, options) => {
    methods.push(options.method);
    return new Response(null, { status: 200 });
  };
  try {
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/media/owner-2/private-object",
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db, JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 403);
    assert.deepEqual(methods, []);
  } finally {
    delete globalThis.__fakeTigrisHandler;
  }
});


test("failed SPARK media rollback schedules immediate cleanup retry", async () => {
  const statements = [];
  const db = {
    prepare(sql) {
      return {
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          statements.push({ sql, params: this.params });
          return { meta: { changes: 1 } };
        }
      };
    }
  };
  const storage = {
    async fetch(_url, options) {
      assert.equal(options.method, "DELETE");
      return new Response("temporary storage outage", { status: 503 });
    }
  };
  const before = Date.now();
  const deleted = await worker.rollbackSparkMediaUpload(
    { DB: db }, storage, "https://storage.example.test/spark-object", "user-1/spark-object"
  );
  assert.equal(deleted, false);
  assert.equal(statements.length, 1);
  assert.match(statements[0].sql, /INSERT INTO media_expirations/);
  assert.match(statements[0].sql, /ON CONFLICT\(object_key\) DO UPDATE/);
  assert.equal(statements[0].params[0], "user-1/spark-object");
  const retryAt = Date.parse(statements[0].params[1]);
  assert.ok(Number.isFinite(retryAt));
  assert.ok(retryAt >= before && retryAt <= Date.now() + 1000);
});

test("successful SPARK media rollback clears its cleanup record", async () => {
  const statements = [];
  const db = {
    prepare(sql) {
      return {
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() { statements.push({ sql, params: this.params }); return { meta: { changes: 1 } }; }
      };
    }
  };
  const storage = { async fetch(_url, options) {
    assert.equal(options.method, "DELETE");
    return new Response(null, { status: 204 });
  }};
  const deleted = await worker.rollbackSparkMediaUpload(
    { DB: db }, storage, "https://storage.example.test/spark-object", "user-1/spark-object"
  );
  assert.equal(deleted, true);
  assert.equal(statements.length, 1);
  assert.match(statements[0].sql, /^DELETE FROM media_expirations/);
  assert.deepEqual(statements[0].params, ["user-1/spark-object"]);
});


test("private memory photo upload verifies memory ownership before touching storage", async () => {
  const secret = "private-memory-test-secret";
  const token = await worker.signToken({ id: "owner-1", username: "owner-1" }, secret);
  const statements = [];
  const db = {
    prepare(sql) {
      const statement = {
        sql,
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          statements.push({ sql: this.sql, params: this.params });
          return { meta: { changes: 1 } };
        },
        async first() {
          if (this.sql.includes("SELECT session_version FROM account_security")) {
            return { session_version: 0 };
          }
          if (this.sql.includes("SELECT id FROM private_memories WHERE id = ? AND owner_id = ?")) {
            assert.deepEqual(this.params, ["memory-owned-by-someone-else", "owner-1"]);
            return null;
          }
          return null;
        },
        async all() { return { results: [] }; }
      };
      return statement;
    }
  };
  let storageCalls = 0;
  const previousHandler = globalThis.__fakeTigrisHandler;
  globalThis.__fakeTigrisHandler = async () => {
    storageCalls++;
    return new Response(null, { status: 204 });
  };
  try {
    const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/private-memories/memory-owned-by-someone-else/media",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer " + token,
          "Content-Type": "image/png",
          "X-File-Name": "private.png"
        },
        body: png
      }
    ), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 404);
    assert.equal(storageCalls, 0);
    assert.ok(statements.some(item => item.sql.includes("CREATE TABLE IF NOT EXISTS private_memory_media")));
  } finally {
    if (previousHandler === undefined) delete globalThis.__fakeTigrisHandler;
    else globalThis.__fakeTigrisHandler = previousHandler;
  }
});


test("deleted private memory photos cannot be read while storage cleanup is pending", async () => {
  const secret = "private-memory-read-test-secret";
  const token = await worker.signToken({ id: "owner-1", username: "owner-1" }, secret);
  const db = {
    prepare(sql) {
      const statement = {
        sql,
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() { return { meta: { changes: 1 } }; },
        async first() {
          if (this.sql.includes("SELECT session_version FROM account_security")) {
            return { session_version: 0 };
          }
          if (this.sql.includes("SELECT owner_id, recipient_id, group_id, file_name, content_type, expires_at FROM media_access")) {
            return null;
          }
          if (this.sql.includes("SELECT sm.status_id AS statusId")) return null;
          if (this.sql.includes("SELECT id FROM private_memory_media WHERE object_key = ? AND owner_id = ?")) {
            assert.deepEqual(this.params, ["owner-1/private-memories/deleted-photo", "owner-1"]);
            return null;
          }
          return null;
        },
        async all() { return { results: [] }; }
      };
      return statement;
    }
  };
  let storageCalls = 0;
  const previousHandler = globalThis.__fakeTigrisHandler;
  globalThis.__fakeTigrisHandler = async () => {
    storageCalls++;
    return new Response(null, { status: 200 });
  };
  try {
    const key = encodeURIComponent("owner-1/private-memories/deleted-photo");
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/media/" + key,
      { headers: { Authorization: "Bearer " + token } }
    ), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 404);
    assert.equal(storageCalls, 0);
  } finally {
    if (previousHandler === undefined) delete globalThis.__fakeTigrisHandler;
    else globalThis.__fakeTigrisHandler = previousHandler;
  }
});


test("deleting a private memory atomically revokes photo access and queues storage cleanup", async () => {
  const secret = "private-memory-delete-test-secret";
  const token = await worker.signToken({ id: "owner-1", username: "owner-1" }, secret);
  const batches = [];
  const db = {
    prepare(sql) {
      const statement = {
        sql,
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() { return { meta: { changes: 1 } }; },
        async first() {
          if (this.sql.includes("SELECT session_version FROM account_security")) {
            return { session_version: 0 };
          }
          if (this.sql.includes("SELECT id FROM private_memories WHERE id = ? AND owner_id = ?")) {
            assert.deepEqual(this.params, ["memory-1", "owner-1"]);
            return { id: "memory-1" };
          }
          if (this.sql.includes("SELECT 1 FROM revoked_sessions")) return null;
          return null;
        },
        async all() {
          if (this.sql.includes("SELECT object_key FROM private_memory_media")) {
            assert.deepEqual(this.params, ["memory-1", "owner-1"]);
            return { results: [{ object_key: "owner-1/private-memories/photo-1" }] };
          }
          return { results: [] };
        }
      };
      return statement;
    },
    async batch(statements) {
      batches.push(statements.map(statement => ({ sql: statement.sql, params: statement.params })));
      return statements.map(() => ({ meta: { changes: 1 } }));
    }
  };
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/private-memories/memory-1",
    { method: "DELETE", headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { message: "Memory deleted" });
  assert.equal(batches.length, 1);
  const sql = batches[0].map(statement => statement.sql);
  assert.ok(sql.some(value => value.includes("INSERT INTO media_expirations")));
  assert.ok(sql.some(value => value.includes("DELETE FROM media_access")));
  assert.ok(sql.some(value => value.includes("DELETE FROM private_memory_media")));
  assert.ok(sql.some(value => value.includes("DELETE FROM private_memories")));
  assert.ok(
    sql.findIndex(value => value.includes("INSERT INTO media_expirations")) <
    sql.findIndex(value => value.includes("DELETE FROM media_access"))
  );
});


test("private memories list is owner-scoped and updates cannot cross owners", async () => {
  const secret = "private-memory-scope-test-secret";
  const token = await worker.signToken({ id: "owner-1", username: "owner-1" }, secret);
  const queries = [];
  const db = {
    prepare(sql) {
      const statement = {
        sql,
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          queries.push({ sql: this.sql, params: this.params });
          return { meta: { changes: this.sql.startsWith("UPDATE private_memories") ? 0 : 1 } };
        },
        async first() {
          if (this.sql.includes("SELECT session_version FROM account_security")) return { session_version: 0 };
          return null;
        },
        async all() {
          queries.push({ sql: this.sql, params: this.params });
          if (this.sql.includes("FROM private_memories WHERE owner_id = ?")) {
            assert.deepEqual(this.params, ["owner-1"]);
            return { results: [{
              id: "memory-1",
              title: "My private note",
              content: "Only the owner should see this",
              sourceType: "text"
            }] };
          }
          if (this.sql.includes("FROM private_memory_media WHERE owner_id = ?")) {
            assert.deepEqual(this.params, ["owner-1"]);
            return { results: [{
              id: "photo-1",
              memoryId: "memory-1",
              attachmentId: "owner-1/private-memories/photo-1",
              fileName: "note.png",
              contentType: "image/png",
              size: 128
            }] };
          }
          return { results: [] };
        }
      };
      return statement;
    }
  };
  const listResponse = await worker.default.fetch(new Request(
    "https://api.example.test/api/private-memories",
    { headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(listResponse.status, 200);
  const listBody = await listResponse.json();
  assert.equal(listBody.memories.length, 1);
  assert.equal(listBody.memories[0].id, "memory-1");
  assert.equal(listBody.memories[0].media[0].attachmentId, "owner-1/private-memories/photo-1");

  const updateResponse = await worker.default.fetch(new Request(
    "https://api.example.test/api/private-memories/not-owned",
    {
      method: "PATCH",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ title: "Attempted edit", content: "Should not update" })
    }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(updateResponse.status, 404);
  assert.ok(queries.some(item => item.sql.includes("UPDATE private_memories") &&
    item.params[2] === "not-owned" && item.params[3] === "owner-1"));
});


test("private memory photo upload stores the owner-scoped record and access metadata", async () => {
  const secret = "private-memory-photo-upload-test-secret";
  const token = await worker.signToken({ id: "owner-1", username: "owner-1" }, secret);
  const batches = [];
  const db = {
    prepare(sql) {
      const statement = {
        sql,
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() { return { meta: { changes: 1 } }; },
        async first() {
          if (this.sql.includes("SELECT session_version FROM account_security")) return { session_version: 0 };
          if (this.sql.includes("SELECT id FROM private_memories WHERE id = ? AND owner_id = ?")) {
            assert.deepEqual(this.params, ["memory-1", "owner-1"]);
            return { id: "memory-1" };
          }
          return null;
        },
        async all() { return { results: [] }; }
      };
      return statement;
    },
    async batch(statements) {
      batches.push(statements.map(statement => ({ sql: statement.sql, params: statement.params })));
      return statements.map(() => ({ meta: { changes: 1 } }));
    }
  };
  const storageCalls = [];
  const previousHandler = globalThis.__fakeTigrisHandler;
  globalThis.__fakeTigrisHandler = async (url, options) => {
    storageCalls.push({ url: String(url), method: options.method, headers: options.headers });
    return new Response(null, { status: 200 });
  };
  try {
    const png = Uint8Array.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const response = await worker.default.fetch(new Request(
      "https://api.example.test/api/private-memories/memory-1/media",
      {
        method: "POST",
        headers: {
          Authorization: "Bearer " + token,
          "Content-Type": "image/png",
          "X-File-Name": "memory.png"
        },
        body: png
      }
    ), {
      DB: db,
      JWT_SECRET: secret,
      TIGRIS_ACCESS_KEY_ID: "test-access",
      TIGRIS_SECRET_ACCESS_KEY: "test-secret"
    });
    assert.equal(response.status, 201);
    const body = await response.json();
    assert.equal(body.media.memoryId, "memory-1");
    assert.match(body.media.attachmentId, /^owner-1\/private-memories\//);
    assert.equal(body.media.contentType, "image/png");
    assert.equal(storageCalls.length, 1);
    assert.equal(storageCalls[0].method, "PUT");
    assert.equal(batches.length, 1);
    assert.ok(batches[0].some(item => item.sql.includes("INSERT INTO private_memory_media")));
    assert.ok(batches[0].some(item => item.sql.includes("INSERT INTO media_access")));
    assert.ok(batches[0].every(item => item.params.includes("owner-1")));
  } finally {
    if (previousHandler === undefined) delete globalThis.__fakeTigrisHandler;
    else globalThis.__fakeTigrisHandler = previousHandler;
  }
});


test("private memories list only the owner’s records and PATCH rejects another owner’s memory", async () => {
  const secret = "private-memory-read-edit-test-secret";
  const token = await worker.signToken({ id: "owner-1", username: "owner-1" }, secret);
  const reads = [];
  const db = {
    prepare(sql) {
      const statement = {
        sql,
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          if (this.sql.includes("UPDATE private_memories")) {
            return { meta: { changes: this.params[2] === "memory-1" && this.params[3] === "owner-1" ? 1 : 0 } };
          }
          return { meta: { changes: 1 } };
        },
        async first() {
          if (this.sql.includes("SELECT session_version FROM account_security")) return { session_version: 0 };
          if (this.sql.includes("SELECT id, title, content, source_type AS sourceType")) {
            return {
              id: this.params[0],
              title: "Updated memory",
              content: "Updated private note",
              sourceType: "text",
              createdAt: "2026-11-21 10:00:00",
              updatedAt: "2026-11-21 10:01:00"
            };
          }
          return null;
        },
        async all() {
          reads.push({ sql: this.sql, params: this.params });
          if (this.sql.includes("FROM private_memories WHERE owner_id = ?")) {
            return { results: [{
              id: "memory-1",
              title: "My memory",
              content: "Only visible to owner",
              sourceType: "text",
              media: undefined
            }] };
          }
          if (this.sql.includes("FROM private_memory_media WHERE owner_id = ?")) {
            return { results: [
              { id: "photo-1", memoryId: "memory-1", attachmentId: "owner-1/private-memories/photo-1" },
              { id: "photo-2", memoryId: "memory-1", attachmentId: "owner-1/private-memories/photo-2" }
            ] };
          }
          return { results: [] };
        }
      };
      return statement;
    }
  };
  const env = { DB: db, JWT_SECRET: secret };
  const listResponse = await worker.default.fetch(new Request(
    "https://api.example.test/api/private-memories",
    { headers: { Authorization: "Bearer " + token } }
  ), env);
  assert.equal(listResponse.status, 200);
  const listed = await listResponse.json();
  assert.equal(listed.memories.length, 1);
  assert.equal(listed.memories[0].id, "memory-1");
  assert.deepEqual(listed.memories[0].media.map(item => item.id), ["photo-1", "photo-2"]);
  assert.equal(reads.length, 2);
  assert.ok(reads.every(item => item.params[0] === "owner-1"));

  const updateOwned = await worker.default.fetch(new Request(
    "https://api.example.test/api/private-memories/memory-1",
    {
      method: "PATCH",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ title: "Updated memory", content: "Updated private note" })
    }
  ), env);
  assert.equal(updateOwned.status, 200);
  const updated = await updateOwned.json();
  assert.equal(updated.memory.content, "Updated private note");

  const updateForeign = await worker.default.fetch(new Request(
    "https://api.example.test/api/private-memories/other-owner-memory",
    {
      method: "PATCH",
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({ title: "Intrusion", content: "Must not change" })
    }
  ), env);
  assert.equal(updateForeign.status, 404);
});

test("private memory DELETE is owner-scoped and revokes photo access before cleanup", async () => {
  const secret = "private-memory-delete-owner-test-secret";
  const token = await worker.signToken({ id: "owner-1", username: "owner-1" }, secret);
  const batches = [];
  const db = {
    prepare(sql) {
      const statement = {
        sql, params: [],
        bind(...params) { this.params = params; return this; },
        async run() { return { meta: { changes: 1 } }; },
        async first() {
          if (this.sql.includes("SELECT session_version FROM account_security")) return { session_version: 0 };
          if (this.sql.includes("SELECT id FROM private_memories WHERE id = ? AND owner_id = ?")) {
            assert.deepEqual(this.params, ["memory-1", "owner-1"]);
            return { id: "memory-1" };
          }
          return null;
        },
        async all() {
          if (this.sql.includes("SELECT object_key FROM private_memory_media WHERE memory_id = ? AND owner_id = ?")) {
            assert.deepEqual(this.params, ["memory-1", "owner-1"]);
            return { results: [{ object_key: "owner-1/private-memories/photo-1" }] };
          }
          return { results: [] };
        }
      };
      return statement;
    },
    async batch(statements) {
      batches.push(statements.map(item => ({ sql: item.sql, params: item.params })));
      return statements.map(() => ({ meta: { changes: 1 } }));
    }
  };
  const response = await worker.default.fetch(new Request(
    "https://api.example.test/api/private-memories/memory-1",
    { method: "DELETE", headers: { Authorization: "Bearer " + token } }
  ), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).message, "Memory deleted");
  assert.equal(batches.length, 1);
  const statements = batches[0];
  assert.ok(statements.some(item => item.sql.includes("DELETE FROM media_access") &&
    item.params[0] === "owner-1/private-memories/photo-1"));
  assert.ok(statements.some(item => item.sql.includes("DELETE FROM private_memory_media") &&
    item.params[1] === "owner-1"));
  assert.ok(statements.some(item => item.sql.includes("DELETE FROM private_memories") &&
    item.params[1] === "owner-1"));
});

test("private memory creation accepts a title-only photo note and rejects unsupported source types", async () => {
  const secret = "private-memory-create-test-secret";
  const token = await worker.signToken({ id: "owner-1", username: "owner-1" }, secret);
  const inserts = [];
  const db = {
    prepare(sql) {
      const statement = {
        sql,
        params: [],
        bind(...params) { this.params = params; return this; },
        async run() {
          if (this.sql.includes("INSERT INTO private_memories")) inserts.push(this.params);
          return { meta: { changes: 1 } };
        },
        async first() {
          if (this.sql.includes("SELECT session_version FROM account_security")) return { session_version: 0 };
          if (this.sql.includes("SELECT id, title, content, source_type AS sourceType")) {
            return {
              id: this.params[0],
              title: "Photo memory",
              content: "",
              sourceType: "text"
            };
          }
          return null;
        },
        async all() { return { results: [] }; }
      };
      return statement;
    }
  };
  const create = body => worker.default.fetch(new Request(
    "https://api.example.test/api/private-memories",
    {
      method: "POST",
      headers: {
        Authorization: "Bearer " + token,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(body)
    }
  ), { DB: db, JWT_SECRET: secret });
  const valid = await create({ title: "Photo memory", content: "", sourceType: "text" });
  assert.equal(valid.status, 201);
  const saved = await valid.json();
  assert.equal(saved.memory.title, "Photo memory");
  assert.equal(saved.memory.content, "");
  assert.equal(inserts.length, 1);
  assert.equal(inserts[0][1], "owner-1");
  const invalidType = await create({ title: "Invalid", content: "text", sourceType: "admin" });
  assert.equal(invalidType.status, 400);
  const empty = await create({ title: "  ", content: "  " });
  assert.equal(empty.status, 400);
  const longTitle = await create({ title: "t".repeat(121), content: "" });
  assert.equal(longTitle.status, 400);
  const longContent = await create({ title: "", content: "c".repeat(10001) });
  assert.equal(longContent.status, 400);
  assert.equal(inserts.length, 1);

  const savedMessage = await create({ title: "Saved chat", content: "Copied message", sourceType: "message" });
  assert.equal(savedMessage.status, 201);
  assert.equal(inserts.length, 2);
  assert.equal(inserts[1][1], "owner-1");
  assert.equal(inserts[1][4], "message");
});
