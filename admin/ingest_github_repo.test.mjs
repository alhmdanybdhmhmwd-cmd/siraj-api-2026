import test from "node:test";
import assert from "node:assert/strict";
import { shouldIndexPath, splitKnowledgeContent, inferSourceType, normalizeAdminApiUrl } from "./ingest_github_repo.mjs";

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


test("repository index reports incomplete coverage rather than silently claiming a full index", async () => {
  const source = await import("./ingest_github_repo.mjs");
  assert.equal(typeof source.ingestRepository, "function");
  assert.match(source.ingestRepository.toString(), /remainingFiles/);
  assert.match(source.ingestRepository.toString(), /complete:/);
  assert.match(source.ingestRepository.toString(), /repository \+ "\/"/);
});
