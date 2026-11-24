import test from "node:test";
import assert from "node:assert/strict";
import { shouldIndexPath, classifyIndexPath, buildRepositoryCoverageReport, splitKnowledgeContent, inferSourceType, normalizeAdminApiUrl, summarizeIndexCoverage, selectIndexBatch, normalizeAllowedRepositories, selectIndexBatchWithSkips, containsLikelySecret, ingestRepository, fetchWithRetry, githubJson } from "./ingest_github_repo.mjs";


test("repository coverage reports eligible domains, file types, and explicit exclusion reasons", () => {
  const report = buildRepositoryCoverageReport([
    { type: "blob", path: "android/lib/main.dart", size: 1000 },
    { type: "blob", path: "src/worker.js", size: 2000 },
    { type: "blob", path: "admin/mobile/lib/main.dart", size: 3000 },
    { type: "blob", path: ".github/workflows/check.yml", size: 400 },
    { type: "blob", path: "docs/guide.md", size: 500 },
    { type: "blob", path: "android/app/google-services.json", size: 800 },
    { type: "blob", path: "android/build/output.apk", size: 200000 },
    { type: "blob", path: "assets/logo.svg", size: 100 }
  ]);
  assert.equal(report.treeBlobs, 8);
  assert.equal(report.eligibleFiles, 5);
  assert.equal(report.oversizedFiles, 1);
  assert.equal(report.excludedByReason.credential_filename, 1);
  assert.equal(report.excludedByReason.unsupported_file_type, 1);
  assert.equal(report.eligibleByDomain["barq-consumer-android"], 1);
  assert.equal(report.eligibleByDomain["barq-consumer-backend"], 1);
  assert.equal(report.eligibleByDomain["barq-admin"], 1);
  assert.equal(report.eligibleByDomain["ci-and-config"], 1);
  assert.equal(report.eligibleByDomain["product-docs"], 1);
  assert.equal(report.eligibleByExtension[".dart"], 2);
  assert.equal(classifyIndexPath("../secret.md"), "unsafe_path");
  assert.throws(() => buildRepositoryCoverageReport([], 0), /invalid_max_file_size/);
});

test("GitHub API ingestion reads retry transient responses before parsing JSON", async () => {
  const statuses = [503, 200];
  const delays = [];
  let calls = 0;
  const result = await githubJson("https://api.github.com/repos/owner/repo", "read-only-token", {
    fetchImpl: async (_url, options) => {
      calls++;
      assert.equal(options.headers.Authorization, "Bearer read-only-token");
      return new Response(JSON.stringify({ ok: true }), {
        status: statuses[calls - 1],
        headers: { "content-type": "application/json" }
      });
    },
    sleep: async milliseconds => { delays.push(milliseconds); },
    maxAttempts: 3
  });
  assert.deepEqual(result, { ok: true });
  assert.equal(calls, 2);
  assert.deepEqual(delays, [250]);
});

test("repository ingestion allowlists project files and excludes secrets/build output", () => {
  assert.equal(shouldIndexPath("docs/BARQ_PRODUCT.md"), true);
  assert.equal(shouldIndexPath("src/src/index.js"), true);
  assert.equal(shouldIndexPath("android/app/src/main/AndroidManifest.xml"), true);
  assert.equal(shouldIndexPath("android/app/build.gradle.kts"), true);
  assert.equal(shouldIndexPath("scripts/check_schema.py"), true);
  assert.equal(shouldIndexPath("admin/mobile/web/index.html"), true);
  assert.equal(shouldIndexPath("admin/mobile/web/styles.css"), true);
  assert.equal(shouldIndexPath("admin/mobile/package.json"), true);
  assert.equal(shouldIndexPath("admin/mobile/tsconfig.json"), true);
  assert.equal(shouldIndexPath("admin/mobile/android/app/src/main/kotlin/MainActivity.kt"), true);
  assert.equal(shouldIndexPath("admin/mobile/android/app/src/main/java/Bridge.java"), true);
  assert.equal(shouldIndexPath("admin/mobile/android/local.properties"), false);
  assert.equal(shouldIndexPath("admin/mobile/android/key.properties"), false);
  assert.equal(shouldIndexPath("infra/production.tfvars"), false);
  assert.equal(shouldIndexPath("admin/.firebase/project.json"), false);
  assert.equal(shouldIndexPath("secrets/private_notes.md"), false);
  assert.equal(shouldIndexPath("admin/pubspec.lock"), false);
  assert.equal(shouldIndexPath("android/app/google-services.json"), false);
  assert.equal(shouldIndexPath(".env.production"), false);
  assert.equal(shouldIndexPath("android/build/app.apk"), false);
  assert.equal(shouldIndexPath("../../secret.txt"), false);
});

test("knowledge chunking preserves content and stays within configured bounds", () => {
  const source = ("BARQ project knowledge line\n").repeat(900);
  const chunks = splitKnowledgeContent(source, 1000);
  assert.ok(chunks.length > 1);
  assert.ok(chunks.every(chunk => chunk.length <= 1000));
  assert.equal(chunks.join("\n").replace(/\n+/g, "\n").length > 0, true);
});

test("repository source type follows the project documentation category", () => {
  assert.equal(inferSourceType("docs/BARQ_ARCHITECTURE_BLUEPRINT.md"), "architecture_decision");
  assert.equal(inferSourceType("docs/BARQ_PRODUCT_REQUIREMENTS.md"), "product_requirement");
  assert.equal(inferSourceType("migrations/0001_core.sql"), "api_contract");
  assert.equal(inferSourceType("src/src/index.js"), "repository_file");
});

test("knowledge ingestion only accepts HTTPS Admin API endpoints", () => {
  assert.equal(normalizeAdminApiUrl("https://admin.example.com/").toString(), "https://admin.example.com");
  assert.throws(() => normalizeAdminApiUrl("http://admin.example.com"), /must_be_https/);
  assert.throws(() => normalizeAdminApiUrl("https://user:pass@admin.example.com"), /must_be_https/);
  assert.throws(() => normalizeAdminApiUrl("not-a-url"), /invalid_admin_api_url/);
});



test("index coverage reports remaining files and rejects impossible counts", () => {
  assert.deepEqual(summarizeIndexCoverage(420, 300), {
    eligibleFiles: 420,
    processedFiles: 300,
    remainingFiles: 120,
    complete: false
  });
  assert.deepEqual(summarizeIndexCoverage(12, 12), {
    eligibleFiles: 12,
    processedFiles: 12,
    remainingFiles: 0,
    complete: true
  });
  assert.throws(() => summarizeIndexCoverage(10, 11), /invalid_index_coverage/);
});


test("repository indexing can continue in ordered batches without skipping files", () => {
  const entries = ["z.md", "a.md", "d.md", "b.md", "c.md"].map(path => ({ path }));
  const first = selectIndexBatch(entries, "", 2);
  assert.deepEqual(first.selected.map(item => item.path), ["a.md", "b.md"]);
  assert.equal(first.remaining, 3);
  assert.equal(first.nextStartAfter, "b.md");
  const second = selectIndexBatch(entries, first.nextStartAfter, 2);
  assert.deepEqual(second.selected.map(item => item.path), ["c.md", "d.md"]);
  assert.equal(second.remaining, 1);
  const last = selectIndexBatch(entries, second.nextStartAfter, 2);
  assert.deepEqual(last.selected.map(item => item.path), ["z.md"]);
  assert.equal(last.remaining, 0);
  assert.equal(last.nextStartAfter, null);
  assert.throws(() => selectIndexBatch(entries, "../unsafe", 2), /invalid_index_batch/);
});

test("repository indexing requires an explicit exact allowlist", () => {
  assert.deepEqual(normalizeAllowedRepositories("owner/barq; owner/admin;owner/barq"), [
    "owner/barq", "owner/admin"
  ]);
  assert.throws(() => normalizeAllowedRepositories(""), /allowlist_required/);
  assert.throws(() => normalizeAllowedRepositories("owner/barq;../private"), /invalid_repository_allowlist/);
});

test("repository ingestion rejects repositories outside the approved scope", async () => {
  await assert.rejects(ingestRepository({
    repository: "other/private-project",
    githubToken: "read-only-test-token",
    adminApiUrl: "https://admin-preview.example.workers.dev",
    ownerToken: "short-lived-test-token",
    allowedRepositories: ["alhmdanybdhmhmwd-cmd/siraj-api-2026"]
  }), /repository_not_owner_approved/);
});

test("knowledge indexing counts oversized files as skipped and resumes without losing coverage", () => {
  const entries = [
    { type: "blob", path: "a.md", size: 100 },
    { type: "blob", path: "b.md", size: 130000 },
    { type: "blob", path: "c.md", size: 100 },
    { type: "blob", path: "d.md", size: 150000 },
    { type: "blob", path: "node_modules/pkg/index.js", size: 20 }
  ];
  const first = selectIndexBatchWithSkips(entries, "", 1, 120000);
  assert.deepEqual(first.selected.map(item => item.path), ["a.md"]);
  assert.equal(first.eligibleFiles, 4);
  assert.equal(first.eligibleFilesAfterCursor, 4);
  assert.equal(first.processedFiles, 1);
  assert.equal(first.skippedOversizeFiles, 0);
  assert.equal(first.remaining, 1);

  const second = selectIndexBatchWithSkips(entries, first.nextStartAfter, 1, 120000);
  assert.deepEqual(second.selected.map(item => item.path), ["c.md"]);
  assert.equal(second.processedFiles, 3);
  assert.equal(second.skippedOversizeFiles, 2);
  assert.equal(second.remaining, 0);
  assert.equal(second.eligibleFilesAfterCursor, 3);
});


test("knowledge ingestion rejects common provider credential formats and keeps ordinary documentation", () => {
  const repeated = "abcdefghijklmnopqrstuvwxyz1234567890";
  const secretSamples = [
    ["ghp", "_", repeated].join(""),
    ["github_pat", "_", repeated].join(""),
    ["AKIA", "1234567890ABCDEF"].join(""),
    ["xoxb", "-", "123456789012", "-", "123456789012", "-", "abcdefghijklmnopqrst"].join(""),
    ["sk", "_live_", "1234567890abcdefghijklmnop"].join(""),
    ["GOCSPX-", "abcdefghijklmnopqrstuvwx"].join(""),
    ["npm_", "abcdefghijklmnopqrstuvwxyz12345678901234567890"].join(""),
    ["pypi-", "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"].join("")
  ];
  for (const sample of secretSamples) assert.equal(containsLikelySecret(sample), true);
  assert.equal(containsLikelySecret("BARQ uses Firebase Cloud Messaging for push notifications."), false);
  assert.equal(containsLikelySecret("Example: set the API key in your local secret manager."), false);
  assert.equal(containsLikelySecret('{"private_key":"synthetic-private-value-long-enough"}'), true);
  assert.equal(containsLikelySecret('{"refresh_token":"synthetic-refresh-token-value"}'), true);
});

test("knowledge ingestion retries transient rate limits and server errors", async () => {
  const statuses = [503, 429, 201];
  const delays = [];
  let calls = 0;
  const response = await fetchWithRetry("https://admin-preview.example.workers.dev/v1/knowledge", {
    method: "POST"
  }, {
    fetchImpl: async () => new Response("", { status: statuses[calls++] }),
    sleep: async milliseconds => { delays.push(milliseconds); },
    maxAttempts: 3
  });
  assert.equal(response.status, 201);
  assert.equal(calls, 3);
  assert.deepEqual(delays, [250, 500]);
});

test("knowledge ingestion bounds retries and surfaces persistent failures", async () => {
  let calls = 0;
  const delays = [];
  const response = await fetchWithRetry("https://admin-preview.example.workers.dev/v1/knowledge", {}, {
    fetchImpl: async () => { calls++; return new Response("", { status: 503 }); },
    sleep: async milliseconds => { delays.push(milliseconds); },
    maxAttempts: 3
  });
  assert.equal(response.status, 503);
  assert.equal(calls, 3);
  assert.deepEqual(delays, [250, 500]);
});

test("knowledge ingestion retries transient network errors without an unbounded loop", async () => {
  let calls = 0;
  const response = await fetchWithRetry("https://admin-preview.example.workers.dev/v1/knowledge", {}, {
    fetchImpl: async () => {
      calls++;
      if (calls < 3) throw new Error("temporary network failure");
      return new Response("", { status: 201 });
    },
    sleep: async () => {},
    maxAttempts: 3
  });
  assert.equal(response.status, 201);
  assert.equal(calls, 3);
});
