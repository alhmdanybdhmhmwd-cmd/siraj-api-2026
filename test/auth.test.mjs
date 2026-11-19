import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const workerPath = new URL("../src/src/index.js", import.meta.url);
let workerSource = await readFile(workerPath, "utf8");
workerSource = workerSource.replace('import { AwsClient } from "aws4fetch";', "");
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
    this.recovery = null;
    this.sessionVersion = 0;
    this.contactCandidates = [];
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
        if (sql.includes("COALESCE((SELECT searchable FROM user_privacy")) {
          return db.targetUser ? { id: db.targetUser.id, searchable: db.targetUser.searchable ? 1 : 0 } : null;
        }
        if (sql.includes("SELECT id FROM users WHERE phone = ? AND id != ?")) {
          return db.existingPhone && db.existingPhone.phone === this.params[0] &&
            db.existingPhone.id !== this.params[1] ? { id: db.existingPhone.id } : null;
        }
        if (sql.includes("SELECT * FROM users WHERE username = ? OR phone = ?")) {
          const id = String(this.params[0]).toLowerCase();
          const phone = String(this.params[1]);
          return (id === db.user.username || phone === db.user.phone) ? { ...db.user } : null;
        }
        if (sql.includes("SELECT recovery_hash, recovery_salt FROM account_recovery")) {
          return db.recovery ? { ...db.recovery } : null;
        }
        return null;
      },
      async all() {
        if (sql.includes("substr(") && sql.includes("user_privacy")) {
          db.contactLookupQueries = (db.contactLookupQueries || 0) + 1;
          return { results: db.contactCandidates };
        }
        return { results: [] };
      },
      async run() {
        if (sql.includes("INSERT OR IGNORE INTO account_security")) db.sessionVersion ??= 0;
        return { meta: { changes: 1 } };
      }
    };
  }

  async batch(statements) {
    const [updatePassword, incrementVersion, consumeCode] = statements;
    const [newHash, newSalt, userId, recoveryUserId, expectedHash] = updatePassword.params;
    if (!this.recovery || this.recovery.recovery_hash !== expectedHash ||
        this.user.id !== userId || recoveryUserId !== userId) {
      return [{ meta: { changes: 0 } }, { meta: { changes: 0 } }, { meta: { changes: 0 } }];
    }
    this.user.password_hash = newHash;
    this.user.password_salt = newSalt;
    this.sessionVersion += 1;
    this.recovery = null;
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

test("password recovery consumes the code and invalidates the old session", async () => {
  const db = new FakeDB();
  const code = "A1B2C3D4E5F6";
  const recoverySalt = "AAECAwQFBgcICQoLDA0ODw";
  db.recovery = {
    recovery_hash: await worker.hashPassword(code, recoverySalt),
    recovery_salt: recoverySalt
  };
  const token = await worker.signToken(user, secret, 0);
  const request = () => new Request("https://api.example.test/api/password/recover", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      identifier: user.username,
      recoveryCode: "A1B2-C3D4 E5F6",
      newPassword: "new-secure-password"
    })
  });
  const env = { DB: db, JWT_SECRET: secret };
  const response = await worker.default.fetch(request(), env);
  assert.equal(response.status, 200);
  assert.equal(db.recovery, null);
  assert.equal(db.sessionVersion, 1);
  assert.notEqual(db.user.password_hash, user.password_hash);
  assert.equal(await worker.authenticate(new Request("https://api.example.test/private", {
    headers: { Authorization: "Bearer " + token }
  }), env), null);
  const newToken = await worker.signToken(user, secret, 1);
  const reusedRequest = new Request("https://api.example.test/api/password/recover", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + newToken,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      identifier: user.username,
      recoveryCode: code,
      newPassword: "another-secure-password"
    })
  });
  const reused = await worker.default.fetch(reusedRequest, env);
  assert.equal(reused.status, 400);
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

test("profile updates cannot claim another account's phone number", async () => {
  const db = new FakeDB();
  db.existingPhone = { id: "other-user", phone: "+967700000002" };
  const token = await worker.signToken(user, secret, 0);
  const response = await worker.default.fetch(new Request("https://api.example.test/api/profile", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({ displayName: "Tester", phone: "+967700000002" })
  }), { DB: db, JWT_SECRET: secret });
  assert.equal(response.status, 409);
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
