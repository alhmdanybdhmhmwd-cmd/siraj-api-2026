import test from "node:test";
import assert from "node:assert/strict";
import { createSharedAdminEnvironment, handleSharedAdminRequest } from "./shared_runtime.js";

test("shared Admin environment maps the existing BARQ DB and AI bindings", () => {
  const DB = { prepare() {} };
  const AI = { run() {} };
  const ADMIN_TASK_QUEUE = { send() {} };
  const env = createSharedAdminEnvironment({
    DB, AI, ADMIN_TASK_QUEUE,
    BARQ_ADMIN_ALLOWED_ORIGIN: "https://admin.example"
  });
  assert.equal(env.ADMIN_DB, DB);
  assert.equal(env.ADMIN_AI, AI);
  assert.equal(env.ADMIN_TASK_QUEUE, ADMIN_TASK_QUEUE);
  assert.equal(env.BARQ_ADMIN_ALLOWED_ORIGIN, "https://admin.example");
});

test("shared Admin environment never uses a separate ADMIN_DB fallback", () => {
  const separateDb = { prepare() {} };
  const env = createSharedAdminEnvironment({ ADMIN_DB: separateDb });
  assert.equal(env.ADMIN_DB, null);
});

test("non-Admin requests are not intercepted", async () => {
  const request = new Request("https://barq.example/api/messages");
  assert.equal(await handleSharedAdminRequest(request, {}), null);
});

test("the shared Worker exposes Admin health under /admin/health", async () => {
  const request = new Request("https://barq.example/admin/health");
  const response = await handleSharedAdminRequest(request, {});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { ok: true, service: "barq-admin-preview" });
});

test("Admin preflight is handled before the consumer API's generic CORS path", async () => {
  const origin = "https://admin.example";
  const request = new Request("https://barq.example/admin/v1/auth/exchange", {
    method: "OPTIONS",
    headers: { Origin: origin, "Access-Control-Request-Method": "POST" }
  });
  const response = await handleSharedAdminRequest(request, {
    BARQ_ADMIN_ALLOWED_ORIGIN: origin
  });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), origin);
  assert.match(response.headers.get("Access-Control-Allow-Methods") || "", /POST/);
});

test("Admin routes receive the shared DB binding and fail closed if it is absent", async () => {
  const request = new Request("https://barq.example/admin/v1/workspace");
  const response = await handleSharedAdminRequest(request, {});
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "admin_database_unavailable" });
});
