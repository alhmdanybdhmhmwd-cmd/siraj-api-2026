import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const workerPath = new URL("../src/src/index.js", import.meta.url);
let workerSource = await readFile(workerPath, "utf8");
const summarySource = await readFile(new URL("../src/src/conversation_summary.js", import.meta.url), "utf8");
const adapterSource = await readFile(new URL("../src/src/runtime_adapters.js", import.meta.url), "utf8");
workerSource = workerSource.replace('import { createAiProvider, createDatabaseProvider } from "./runtime_adapters.js";', adapterSource.replaceAll("export function ", "function "));
workerSource = workerSource.replace('import { AwsClient } from "aws4fetch";', "class AwsClient {}");
workerSource = workerSource.replace(
  'import { prepareConversationSummaryTranscript, buildConversationSummaryMessages, extractConversationSummaryText } from "./conversation_summary.js";',
  summarySource
);
workerSource = workerSource.replace(
  'import { handleResumableMediaUpload, cleanupExpiredUploadSessions } from "./media_multipart_routes.js";',
  'const handleResumableMediaUpload = async () => null; const cleanupExpiredUploadSessions = async () => ({ expired: 0 });'
);
const workerModulePath = `/tmp/barq-health-worker-${process.pid}.mjs`;
await writeFile(workerModulePath, workerSource, "utf8");
const workerModule = await import(pathToFileURL(workerModulePath).href);
const fetchWorker = workerModule.default.fetch;

function request(path) {
  return new Request("https://barq.test" + path, { method: "GET" });
}

test("GET /health/live succeeds without database or secrets", async () => {
  const response = await fetchWorker(request("/health/live"), {});
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "alive", service: "barq-api" });
});

test("GET /health/ready returns 503 when required configuration is missing", async () => {
  const noDatabase = await fetchWorker(request("/health/ready"), { JWT_SECRET: "test" });
  assert.equal(noDatabase.status, 503);
  assert.deepEqual(await noDatabase.json(), { status: "not_ready" });

  const noSecret = await fetchWorker(request("/health/ready"), {
    DB: { prepare() { throw new Error("DB must not be queried"); } }
  });
  assert.equal(noSecret.status, 503);
  assert.deepEqual(await noSecret.json(), { status: "not_ready" });
});

test("GET /health/ready performs only a read-only SELECT probe", async () => {
  const statements = [];
  const env = {
    JWT_SECRET: "unit-test-secret",
    DB: {
      prepare(sql) {
        statements.push(sql);
        return { async first() { return { ok: 1 }; } };
      }
    }
  };
  const response = await fetchWorker(request("/health/ready"), env);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ready", service: "barq-api" });
  assert.deepEqual(statements, ["SELECT 1 AS ok"]);
  assert.ok(statements.every(sql => /^\s*SELECT\b/i.test(sql)));
});

test("GET /health/ready returns 503 when the database probe fails", async () => {
  const env = {
    JWT_SECRET: "unit-test-secret",
    DB: { prepare() { throw new Error("simulated unavailable database"); } }
  };
  const response = await fetchWorker(request("/health/ready"), env);
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { status: "not_ready" });
});


test("scheduled rate-limit cleanup also removes expired transcription limiter rows", async () => {
  const statements = [];
  const env = {
    DB: {
      prepare(sql) {
        statements.push(sql);
        return {
          bind(cutoff) {
            assert.equal(cutoff, 1_700_000_000 - 86_400);
            return { async run() { return { meta: { changes: 2 } }; } };
          }
        };
      }
    }
  };
  const result = await workerModule.cleanupExpiredRateLimits(env, 1_700_000_000_000);
  assert.deepEqual(result, {
    login_rate_limits: 2,
    recovery_rate_limits: 2,
    transcription_rate_limits: 2
  });
  assert.equal(statements.length, 3);
  assert.ok(statements.some(sql => sql.includes("DELETE FROM transcription_rate_limits")));
});
