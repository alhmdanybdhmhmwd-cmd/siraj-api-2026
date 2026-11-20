import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const testConfig = await readFile(new URL("../wrangler.test.toml", import.meta.url), "utf8");
const productionConfig = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");

function hasRoute(method, path) {
  const escaped = path.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`method === ["']${method}["'] && path === ["']${escaped}["']`).test(worker);
}

test("liveness probe is independent from database readiness", () => {
  assert.match(worker, /path === ["']\/health\/live["']/);
  assert.match(worker, /path === ["']\/health\/ready["']/);
  assert.match(worker, /SELECT 1 AS ok/);
});

test("phase 2 core account and messaging routes remain present", () => {
  for (const [method, path] of [
    ["POST", "/api/register"],
    ["POST", "/api/login"],
    ["POST", "/api/password/recover"],
    ["POST", "/api/profile"],
    ["GET", "/api/me"],
    ["GET", "/api/privacy"],
    ["POST", "/api/privacy"],
    ["GET", "/api/notification-settings"],
    ["POST", "/api/notification-settings"],
    ["GET", "/api/friends"],
    ["POST", "/api/contacts"],
    ["POST", "/api/contacts/match"],
    ["POST", "/api/messages"],
    ["GET", "/api/messages"],
    ["POST", "/api/statuses"],
    ["GET", "/api/statuses"],
    ["POST", "/api/groups"],
    ["GET", "/api/groups"],
  ]) {
    assert.ok(hasRoute(method, path), `Missing ${method} ${path}`);
  }
});

test("isolated test D1 is not the production database", () => {
  const testId = testConfig.match(/database_id\s*=\s*"([^"]+)"/)?.[1];
  const productionId = productionConfig.match(/database_id\s*=\s*"([^"]+)"/)?.[1];
  assert.ok(testId, "test D1 database_id must be configured");
  assert.ok(productionId, "production D1 database_id must be configured");
  assert.notEqual(testId, productionId);
  assert.match(testConfig, /database_name\s*=\s*"barq-phase2-test-/);
  assert.doesNotMatch(testConfig, /\[vars\]|\[\[routes\]\]/);
});
