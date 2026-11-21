import { readFile } from "node:fs/promises";
import assert from "node:assert/strict";

const files = ["src/src/index.js", "src/src/media_multipart_routes.js"];
const source = (await Promise.all(files.map(path => readFile(new URL(`../${path}`, import.meta.url), "utf8")))).join("\n");
const references = [...source.matchAll(/\benv\.([A-Za-z_$][\w$]*)/g)].reduce((counts, match) => {
  counts[match[1]] = (counts[match[1]] || 0) + 1;
  return counts;
}, {});
const approvedBindings = [
  "AI",
  "DB",
  "FCM_PROJECT_ID",
  "FCM_SERVICE_ACCOUNT_JSON",
  "JWT_SECRET",
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
assert.match(source, /env\.DB\.prepare\(/, "D1 access should remain visible to the portability audit.");
assert.match(source, /env\.AI\./, "Workers AI access should remain visible to the portability audit.");
assert.match(source, /AwsClient/, "Tigris/S3-compatible storage adapter should remain visible to the portability audit.");

const report = {
  scope: files,
  runtime: "Cloudflare Workers",
  bindings: Object.fromEntries(actualBindings.map(name => [name, references[name]])),
  directD1References: references.DB,
  directWorkersAIReferences: references.AI,
  note: "Static dependency inventory only; it does not prove a Node/AWS runtime implementation or VPN reachability."
};
process.stdout.write(JSON.stringify(report, null, 2) + "\n");
