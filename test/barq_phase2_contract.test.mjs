import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const worker = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const testConfig = await readFile(new URL("../wrangler.test.toml", import.meta.url), "utf8");
const productionConfig = await readFile(new URL("../wrangler.toml", import.meta.url), "utf8");

function hasPath(path) {
  return worker.includes('path === "' + path + '"') ||
    worker.includes("path === '" + path + "'");
}

test("health probes and read-only readiness query are present", () => {
  assert.ok(hasPath("/health/live"));
  assert.ok(hasPath("/health/ready"));
  assert.ok(worker.includes("SELECT 1 AS ok"));
});

test("phase 2 core API route paths remain present", () => {
  const paths = [
    "/api/register", "/api/login", "/api/password/recover",
    "/api/profile", "/api/me", "/api/privacy",
    "/api/notification-settings", "/api/friends", "/api/contacts",
    "/api/contacts/match", "/api/messages", "/api/statuses", "/api/groups"
  ];
  for (const path of paths) {
    assert.ok(hasPath(path), "Missing route path " + path);
  }
});

test("isolated test D1 is not the production database", () => {
  const testId = testConfig.match(/database_id\s*=\s*"([^"]+)"/)?.[1];
  const productionId = productionConfig.match(/database_id\s*=\s*"([^"]+)"/)?.[1];
  assert.ok(testId, "test D1 database_id must be configured");
  assert.ok(productionId, "production D1 database_id must be configured");
  assert.notEqual(testId, productionId);
  assert.ok(testConfig.includes('database_name = "barq-phase2-test-'));
  assert.ok(!testConfig.includes("[vars]"));
  assert.ok(!testConfig.includes("[[routes]]"));
});
