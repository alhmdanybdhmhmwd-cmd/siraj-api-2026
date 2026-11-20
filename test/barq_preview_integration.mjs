import assert from "node:assert/strict";
import { randomInt, randomUUID } from "node:crypto";

const base = process.env.BARQ_PREVIEW_URL;
if (!base || !/^https:\/\/[a-z0-9.-]+\.workers\.dev$/i.test(base)) {
  throw new Error("BARQ_PREVIEW_URL must point to the isolated workers.dev Preview host");
}

async function call(path, { method = "GET", token, body, expected = 200 } = {}) {
  const response = await fetch(new URL(path, base), {
    method,
    headers: {
      ...(body === undefined ? {} : { "Content-Type": "application/json" }),
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    ...(body === undefined ? {} : { body: JSON.stringify(body) })
  });
  const raw = await response.text();
  let data;
  try { data = raw ? JSON.parse(raw) : {}; } catch { throw new Error(`${method} ${path}: non-JSON response (${response.status})`); }
  assert.equal(response.status, expected, `${method} ${path}: ${JSON.stringify(data)}`);
  return data;
}

const digits = () => String(randomInt(1000000, 9999999));
const password = "Preview-Test-" + randomUUID().slice(0, 8);
const suffix = randomUUID().replaceAll("-", "").slice(0, 8);
const accountA = { displayName: "Preview Alpha " + suffix, username: "pa" + suffix, phone: "+1202" + digits(), password };
const accountB = { displayName: "Preview Beta " + suffix, username: "pb" + suffix, phone: "+1202" + digits(), password };

const a = await call("/api/register", { method: "POST", body: accountA, expected: 201 });
assert.ok(a.user?.id && a.token && /^[A-F0-9]{40}$/.test(a.recoveryCode || ""), "registration must return user, session and recovery code");
const b = await call("/api/register", { method: "POST", body: accountB, expected: 201 });
assert.ok(b.user?.id && b.token, "second account registration must return a session");

const login = await call("/api/login", { method: "POST", body: { username: accountA.phone, password } });
assert.ok(login.token && login.user.id === a.user.id, "phone login must return the created account");

const me = await call("/api/me", { token: a.token });
assert.equal(me.user.id, a.user.id);
const updatedName = "Preview Updated " + suffix;
const profile = await call("/api/profile", {
  method: "POST", token: a.token,
  body: { displayName: updatedName, phone: accountA.phone }
});
assert.equal(profile.user.displayName, updatedName);

const privacyOff = await call("/api/privacy", {
  method: "POST", token: b.token, body: { searchable: false, readReceipts: false }
});
assert.equal(privacyOff.privacy.searchable, false);
const hiddenMatch = await call("/api/contacts/match", {
  method: "POST", token: a.token, body: { phones: [accountB.phone] }
});
assert.equal(hiddenMatch.users.length, 0, "non-searchable accounts must not appear in contact matching");

await call("/api/privacy", {
  method: "POST", token: b.token, body: { searchable: true }
});
const arabicDigits = accountB.phone.replace(/[0-9]/g, d => String.fromCharCode(0x0660 + Number(d)));
const matches = await call("/api/contacts/match", {
  method: "POST", token: a.token, body: { phones: [arabicDigits] }
});
assert.ok(matches.users.some(user => user.id === b.user.id), "contact matching must normalize Arabic-Indic digits");

await call("/api/contacts", { method: "POST", token: a.token, body: { userId: b.user.id }, expected: 201 });
const friendsA = await call("/api/friends", { token: a.token });
const friendsB = await call("/api/friends", { token: b.token });
assert.ok(friendsA.friends.some(user => user.id === b.user.id), "contact addition must create the sender's contact link");
assert.ok(friendsB.friends.some(user => user.id === a.user.id), "contact addition must be reciprocal");

// A lost response followed by an offline-outbox retry must persist and notify
// only one message. Reusing an ID for a different sender/recipient is rejected.
const clientMessageId = "abcdef0123456789abcdef0123456789";
const firstMessage = await call("/api/messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "idempotency integration check", clientMessageId },
  expected: 201
});
assert.equal(firstMessage.id, clientMessageId);
const retriedMessage = await call("/api/messages", {
  method: "POST", token: a.token,
  body: { receiverId: b.user.id, body: "idempotency integration check", clientMessageId }
});
assert.equal(retriedMessage.id, clientMessageId);
assert.equal(retriedMessage.duplicate, true, "same client ID must be acknowledged as a duplicate");
await call("/api/messages", {
  method: "POST", token: b.token,
  body: { receiverId: a.user.id, body: "different owner", clientMessageId },
  expected: 409
});
const conversation = await call("/api/messages?with=" + encodeURIComponent(b.user.id), { token: a.token });
assert.equal(conversation.messages.filter(message => message.id === clientMessageId).length, 1,
  "retries must leave exactly one persisted message");

await call("/api/contacts/match", { method: "POST", token: a.token, body: { phones: [] } }).then(result => {
  assert.deepEqual(result.users, []);
});
await call("/api/me", { expected: 401 });
await call("/api/contacts", { method: "POST", token: a.token, body: { userId: a.user.id }, expected: 400 });

console.log("Preview integration passed: two registrations, phone login, authenticated profile read/update, privacy enforcement, Arabic-digit contact matching, direct reciprocal contact addition, and authorization/validation guards.");
