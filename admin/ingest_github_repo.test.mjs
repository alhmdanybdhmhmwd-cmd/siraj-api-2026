import test from "node:test";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";
import { shouldIndexPath, splitKnowledgeContent, inferSourceType, normalizeAdminApiUrl, summarizeIndexCoverage, selectIndexBatch, normalizeAllowedRepositories, selectIndexBatchWithSkips, ingestRepository, containsLikelySecret, classifyIndexPath, fetchWithRetry } from "./ingest_github_repo.mjs";

test("repository ingestion allowlists project files and excludes secrets/build output", () => {
  assert.equal(shouldIndexPath("docs/BARQ_PRODUCT.md"), true);
  assert.equal(shouldIndexPath("src/src/index.js"), true);
  assert.equal(shouldIndexPath("android/app/src/main/AndroidManifest.xml"), true);
  assert.equal(shouldIndexPath("android/app/build.gradle.kts"), true);
  assert.equal(shouldIndexPath("scripts/check_schema.py"), true);
  assert.equal(shouldIndexPath("secrets/private_notes.md"), false);
  assert.equal(shouldIndexPath("admin/pubspec.lock"), false);
  assert.equal(shouldIndexPath("android/app/google-services.json"), false);
  assert.equal(shouldIndexPath(".env.production"), false);
  assert.equal(shouldIndexPath("android/build/app.apk"), false);
  assert.equal(shouldIndexPath("../../secret.txt"), false);
  assert.equal(classifyIndexPath("secrets/private_notes.md"), "sensitive_path");
  assert.equal(classifyIndexPath("README.rst"), "unsupported_extension");
  assert.equal(classifyIndexPath(".env.local"), "sensitive_path");
  assert.equal(classifyIndexPath("docs/guide.md"), null);
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

test("repository indexing uses one consistent lexical order across mixed-case resume cursors", () => {
  const entries = ["docs/z.md", "Docs/A.md", "admin/z.md", "Admin/A.md", "docs/A.md"]
    .map(path => ({ path }));
  const seen = [];
  let cursor = "";
  while (true) {
    const batch = selectIndexBatch(entries, cursor, 2);
    seen.push(...batch.selected.map(item => item.path));
    if (!batch.nextStartAfter) break;
    cursor = batch.nextStartAfter;
  }
  assert.deepEqual(seen, [
    "Admin/A.md", "Docs/A.md", "admin/z.md", "docs/A.md", "docs/z.md"
  ]);
  assert.equal(new Set(seen).size, entries.length);
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
  assert.equal(second.skippedByReason.oversized_file, 2);
  assert.equal(second.skippedByReason.sensitive_path, 1);
});


test("owner knowledge seed preserves product boundaries and flags time-sensitive decisions", () => {
  const seed = readFileSync(new URL("./knowledge/BARQ_OWNER_CONTEXT.md", import.meta.url), "utf8");
  assert.match(seed, /\*\*برق — BARQ\*\* is the main global messaging application/);
  assert.match(seed, /\*\*SPARK — سبارك\*\* is only the stories\/status feature/);
  assert.match(seed, /\*\*BARQ Admin\*\* is a separate management application/);
  assert.match(seed, /\*\*BARQ Brain\*\* is the AI assistant inside BARQ Admin/);
  assert.match(seed, /needs_owner_confirmation/);
  assert.match(seed, /No direct contradiction was found among the stable product-identity decisions/);
  assert.match(seed, /Feature requirements .* are not proof that the corresponding code is complete/);
  assert.match(seed, /The 12-stage BARQ roadmap supersedes the older 8-stage plan/);
});


test("repository ingestion rejects branch-based resume to prevent mixed-revision batches", async () => {
  await assert.rejects(ingestRepository({
    repository: "alhmdanybdhmhmwd-cmd/siraj-api-2026",
    ref: "main",
    startAfter: "admin/worker.js",
    githubToken: "read-only-test-token",
    adminApiUrl: "https://admin-preview.example.workers.dev",
    ownerToken: "short-lived-test-token",
    allowedRepositories: ["alhmdanybdhmhmwd-cmd/siraj-api-2026"]
  }), /resume_requires_immutable_commit_sha/);
});

test("secret-content screening catches common provider tokens and private-key formats", () => {
  const samples = [
    ["github_pat_", "abcdefghijklmnopqrstuvwxyz1234567890"].join(""),
    ["AKIA", "1234567890ABCDEF"].join(""),
    ["xox", "b-", "123456789012-", "abcdefghijklmnop"].join(""),
    ["sk_live_", "1234567890abcdefghijkl"].join(""),
    ["-----BEGIN DSA PRIVATE KEY-----"],
    ["client_secret: ", "abcdefghijklmnopqrstuvwxyz123456"].join("")
  ];
  for (const sample of samples) assert.equal(containsLikelySecret(sample), true, sample);
  assert.equal(containsLikelySecret("BARQ product requirements and architecture overview"), false);
});


test("index coverage reports why repository files were excluded", () => {
  const report = selectIndexBatchWithSkips([
    { type: "blob", path: "docs/guide.md", size: 100 },
    { type: "blob", path: "secrets/private.md", size: 80 },
    { type: "blob", path: "README.rst", size: 60 },
    { type: "blob", path: "android/app/large.md", size: 140000 },
    { type: "blob", path: "docs/no-size.md" },
    { type: "tree", path: "docs", size: 0 }
  ], "", 10, 120000);
  assert.deepEqual(report.skippedByReason, {
    sensitive_path: 1,
    unsupported_extension: 1,
    invalid_size: 1,
    oversized_file: 1
  });
  assert.equal(report.eligibleFiles, 2);
  assert.equal(report.selected.length, 1);
});


test("repository and knowledge API fetches retry transient failures but not permanent client errors", async () => {
  const originalFetch = globalThis.fetch;
  try {
    let calls = 0;
    globalThis.fetch = async () => {
      calls++;
      return calls === 1
        ? new Response("temporary", { status: 503 })
        : new Response("ok", { status: 200 });
    };
    const recovered = await fetchWithRetry("https://example.test", {}, {
      attempts: 3,
      retryDelayMs: 0
    });
    assert.equal(recovered.status, 200);
    assert.equal(calls, 2);

    calls = 0;
    globalThis.fetch = async () => {
      calls++;
      throw new Error("temporary_network_failure");
    };
    await assert.rejects(fetchWithRetry("https://example.test", {}, {
      attempts: 2,
      retryDelayMs: 0
    }), /temporary_network_failure/);
    assert.equal(calls, 2);

    calls = 0;
    globalThis.fetch = async () => {
      calls++;
      return new Response("invalid", { status: 400 });
    };
    const rejected = await fetchWithRetry("https://example.test", {}, {
      attempts: 3,
      retryDelayMs: 0
    });
    assert.equal(rejected.status, 400);
    assert.equal(calls, 1);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
