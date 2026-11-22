import test from "node:test";
import assert from "node:assert/strict";
import { sendBarqPushNotification } from "./notification_service.js";

function makeHarness({ preference = null, devices = [{ fcm_token: "device-token-1" }], fcmResponses = [] } = {}) {
  const calls = [];
  const deleted = [];
  const errors = [];
  let fcmIndex = 0;
  const db = {
    prepare(sql) {
      let values = [];
      return {
        bind(...args) { values = args; return this; },
        async first() {
          calls.push({ kind: "first", sql, values });
          if (sql.includes("notification_preferences")) return preference;
          return null;
        },
        async all() {
          calls.push({ kind: "all", sql, values });
          if (sql.includes("device_tokens")) return { results: devices };
          return { results: [] };
        },
        async run() {
          calls.push({ kind: "run", sql, values });
          if (sql.includes("DELETE FROM device_tokens")) deleted.push(values[0]);
          return { success: true, meta: { changes: 1 } };
        }
      };
    }
  };
  const fetchImpl = async (url, init = {}) => {
    calls.push({ kind: "fetch", url, init });
    if (String(url).includes("oauth2.googleapis.com")) {
      return new Response(JSON.stringify({ access_token: "test-access-token" }), {
        status: 200, headers: { "Content-Type": "application/json" }
      });
    }
    const next = fcmResponses[fcmIndex++] || { status: 200, body: "{}" };
    return new Response(next.body || "{}", { status: next.status || 200 });
  };
  const dependencies = {
    fetchImpl,
    cryptoImpl: {
      subtle: {
        async importKey() { return { testKey: true }; },
        async sign() { return new Uint8Array([1, 2, 3]); }
      }
    },
    now: () => 1_800_000_000_000,
    logger: { error: (...args) => errors.push(args) }
  };
  const env = {
    DB: db,
    FCM_PROJECT_ID: "barq-test-project",
    FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({
      client_email: "barq-test@example.iam.gserviceaccount.com",
      private_key: "-----BEGIN PRIVATE KEY-----\\nAQ==\\n-----END PRIVATE KEY-----",
      token_uri: "https://oauth2.googleapis.com/token",
      project_id: "barq-test-project"
    })
  };
  return { env, dependencies, calls, deleted, errors };
}

test("disabled notification preference prevents all device deliveries", async () => {
  const h = makeHarness({ preference: { enabled: 0 } });
  await sendBarqPushNotification(h.env, "recipient-1", "sender-1", "Sender", "hello", {}, h.dependencies);
  assert.equal(h.calls.filter(call => call.kind === "fetch" && String(call.url).includes("messages:send")).length, 0);
  assert.equal(h.calls.some(call => call.kind === "all" && call.sql.includes("device_tokens")), false);
  assert.deepEqual(h.errors, []);
});

test("enabled/default preference sends exactly once to each registered device", async () => {
  const h = makeHarness({
    preference: null,
    devices: [{ fcm_token: "device-a" }, { fcm_token: "device-b" }]
  });
  await sendBarqPushNotification(h.env, "recipient-1", "sender-1", "Ali", "hello BARQ", {}, h.dependencies);
  const sends = h.calls.filter(call => call.kind === "fetch" && String(call.url).includes("messages:send"));
  assert.equal(sends.length, 2);
  const payload = JSON.parse(sends[0].init.body).message;
  assert.equal(payload.token, "device-a");
  assert.equal(payload.notification.title, "رسالة من Ali");
  assert.equal(payload.notification.body, "hello BARQ");
  assert.equal(payload.data.type, "direct_message");
  assert.equal(payload.data.senderId, "sender-1");
  assert.deepEqual(h.errors, []);
});

test("group and SPARK categories use their own titles, data types and channels", async () => {
  const group = makeHarness();
  await sendBarqPushNotification(group.env, "r", "s", "Sender", "group text", {
    category: "groups", groupId: "group-7", groupName: "Team"
  }, group.dependencies);
  const groupPayload = JSON.parse(group.calls.find(call => call.kind === "fetch" && String(call.url).includes("messages:send")).init.body).message;
  assert.equal(groupPayload.notification.title, "رسالة في Team");
  assert.equal(groupPayload.android.notification.channel_id, "barq_groups");
  assert.equal(groupPayload.data.type, "group_message");
  assert.equal(groupPayload.data.groupId, "group-7");

  const spark = makeHarness();
  await sendBarqPushNotification(spark.env, "r", "s", "Sender", "ignored body", {
    category: "statuses",
    statusId: "spark-status-9"
  }, spark.dependencies);
  const sparkPayload = JSON.parse(spark.calls.find(call => call.kind === "fetch" && String(call.url).includes("messages:send")).init.body).message;
  assert.equal(sparkPayload.notification.title, "SPARK جديد من Sender");
  assert.equal(sparkPayload.notification.body, "شارك لحظة جديدة في SPARK");
  assert.equal(sparkPayload.android.notification.channel_id, "barq_statuses");
  assert.equal(sparkPayload.data.type, "status_update");
  assert.equal(sparkPayload.data.statusId, "spark-status-9");
});

test("invalid FCM registration is deleted without logging it as a normal send failure", async () => {
  const h = makeHarness({
    fcmResponses: [{ status: 404, body: JSON.stringify({ error: { status: "NOT_FOUND", message: "UNREGISTERED" } }) }]
  });
  await sendBarqPushNotification(h.env, "recipient-1", "sender-1", "Sender", "hello", {}, h.dependencies);
  assert.deepEqual(h.deleted, ["device-token-1"]);
  assert.deepEqual(h.errors, []);
});

test("FCM transport errors are contained and logged instead of escaping the request", async () => {
  const h = makeHarness();
  h.dependencies.fetchImpl = async (url, init = {}) => {
    if (String(url).includes("oauth2.googleapis.com")) {
      return new Response(JSON.stringify({ access_token: "test-access-token" }), { status: 200 });
    }
    throw new Error("simulated network outage");
  };
  await assert.doesNotReject(() =>
    sendBarqPushNotification(h.env, "recipient-1", "sender-1", "Sender", "hello", {}, h.dependencies)
  );
  assert.equal(h.errors.length, 1);
  assert.match(String(h.errors[0][1]), /simulated network outage/);
});

test("ambiguous INVALID_ARGUMENT payload errors do not revoke a device token", async () => {
  const h = makeHarness({
    fcmResponses: [{ status: 400, body: JSON.stringify({ error: { status: "INVALID_ARGUMENT", message: "Invalid message payload" } }) }]
  });
  await sendBarqPushNotification(h.env, "recipient-1", "sender-1", "Sender", "hello", {}, h.dependencies);
  assert.deepEqual(h.deleted, []);
  assert.equal(h.errors.length, 1);
  assert.match(String(h.errors[0][2]), /INVALID_ARGUMENT|Invalid message payload/);
});

test("missing service credentials safely skip delivery", async () => {
  const h = makeHarness();
  delete h.env.FCM_SERVICE_ACCOUNT_JSON;
  await sendBarqPushNotification(h.env, "recipient-1", "sender-1", "Sender", "hello", {}, h.dependencies);
  assert.equal(h.calls.length, 0);
});
