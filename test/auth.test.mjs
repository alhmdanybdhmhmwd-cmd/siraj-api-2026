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
      recoveryCode: code,
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
