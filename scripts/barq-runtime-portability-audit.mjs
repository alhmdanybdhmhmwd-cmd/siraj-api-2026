import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";

const files = ["src/src/index.js", "src/src/media_multipart_routes.js", "src/src/runtime_adapters.js"];
const [source, adapterSource] = await Promise.all([
  Promise.all(files.map(path => readFile(new URL(`../${path}`, import.meta.url), "utf8"))).then(parts => parts.join("\n")),
  readFile(new URL("../src/src/runtime_adapters.js", import.meta.url), "utf8")
]);
const references = [...source.matchAll(/\benv(?:\?\.|\.)([A-Za-z_$][\w$]*)/g)].reduce((counts, match) => {
  counts[match[1]] = (counts[match[1]] || 0) + 1;
  return counts;
}, {});
const approvedBindings = [
  "AI",
  "DB",
  "FCM_PROJECT_ID",
  "FCM_SERVICE_ACCOUNT_JSON",
  "JWT_SECRET",
  "OBJECT_STORAGE_ACCESS_KEY_ID",
  "OBJECT_STORAGE_BUCKET",
  "OBJECT_STORAGE_ENDPOINT",
  "OBJECT_STORAGE_REGION",
  "OBJECT_STORAGE_SECRET_ACCESS_KEY",
  "TIGRIS_ACCESS_KEY_ID",
  "TIGRIS_BUCKET",
  "TIGRIS_SECRET_ACCESS_KEY"
].sort();
const actualBindings = Object.keys(references).sort();

assert.deepEqual(
  actualBindings,
  approvedBindings,
  "A new or removed Worker binding needs an explicit portability/security review."
);
assert.match(source, /env\.DB\.prepare\(/, "SQL access should remain visible to the portability audit.");
assert.equal((source.match(/createDatabaseProvider\(env\.DB\)/g) || []).length, 2, "HTTP and scheduled entrypoints must both receive the database adapter.");
assert.match(adapterSource, /export function createDatabaseProvider\(binding\)/, "The provider-neutral SQL adapter must remain available.");
assert.match(adapterSource, /prepare\(sql\)/, "The SQL adapter must expose prepared statements.");
assert.match(adapterSource, /async batch\(statements\)/, "The SQL adapter must expose batched statements.");
assert.match(source, /createAiProvider\(env\.AI\)/, "Workers AI should flow through the provider-neutral adapter.");
assert.match(source, /AwsClient/, "Tigris/S3-compatible storage adapter should remain visible to the portability audit.");

const report = {
  scope: files,
  runtime: "Cloudflare Workers",
  bindings: Object.fromEntries(actualBindings.map(name => [name, references[name]])),
  directD1References: references.DB,
  directWorkersAIReferences: references.AI,
  databaseAdapter: "SQL capability adapter is wired at HTTP and scheduled entrypoints; current implementation still wraps D1.",
  note: "Static dependency inventory across route modules and runtime adapters only; it does not prove a remote storage provider is configured or VPN reachability."
};
process.stdout.write(JSON.stringify(report, null, 2) + "\n");
