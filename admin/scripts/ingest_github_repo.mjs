import { Buffer } from "node:buffer";

const DEFAULT_REF = process.env.BARQ_GITHUB_REF || "barq/ux-media-chat-spark-2026-11-23";
const MAX_FILES = 250;
const MAX_FILE_BYTES = 120_000;
const CHUNK_CHARS = 5_000;

export function shouldIndexPath(path) {
  if (typeof path !== "string" || path.startsWith("/") || path.includes("..")) return false;
  if (/^android\/(\.gradle|build|\.dart_tool)\//.test(path)) return false;
  if (/(^|\/)(\.env[^/]*|.*\.jks|.*\.keystore|google-services\.json|GoogleService-Info\.plist|.*\.pem|.*\.p12)$/i.test(path)) return false;
  if (/\/(node_modules|\.dart_tool|build|\.git|\.gradle)\//.test(path)) return false;
  const allowedRoot = /^(README\.md|package\.json|wrangler\.(test|fallback\.test)\.toml|docs\/|src\/src\/|api\/|migrations\/|test\/|admin\/|\.github\/workflows\/)/;
  return allowedRoot.test(path) && /\.(md|mdx|js|mjs|ts|tsx|dart|sql|ya?ml|toml|json)$/i.test(path);
}

export function splitKnowledgeContent(content, maxChars = CHUNK_CHARS) {
  const text = String(content || "").replace(/\r\n/g, "\n");
  if (!text.trim()) return [];
  const chunks = [];
  let rest = text;
  while (rest.length > maxChars) {
    let cut = rest.lastIndexOf("\n", maxChars);
    if (cut < Math.floor(maxChars * 0.55)) cut = maxChars;
    chunks.push(rest.slice(0, cut).trim());
    rest = rest.slice(cut).trimStart();
  }
  if (rest.trim()) chunks.push(rest.trim());
  return chunks;
}

export function inferSourceType(path) {
  if (/^docs\/.*(decision|architecture|blueprint)/i.test(path)) return "architecture_decision";
  if (/^docs\/.*(requirement|product|roadmap)/i.test(path)) return "product_requirement";
  if (/^docs\/.*(runbook|operations|deploy)/i.test(path)) return "runbook";
  if (/^docs\/.*(launch|marketing|growth)/i.test(path)) return "launch_material";
  if (/^(api\/|migrations\/)/.test(path)) return "api_contract";
  return "repository_file";
}

async function requestJson(url, token) {
  const response = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(token ? { Authorization: "Bearer " + token } : {})
    },
    signal: AbortSignal.timeout(30000)
  });
  if (!response.ok) throw new Error("GitHub request failed: " + response.status + " " + url);
  return response.json();
}

async function main() {
  const owner = process.env.BARQ_GITHUB_OWNER || "alhmdanybdhmhmwd-cmd";
  const repository = process.env.BARQ_GITHUB_REPO || "siraj-api-2026";
  const apiBase = process.env.BARQ_ADMIN_API_URL;
  const ownerToken = process.env.BARQ_ADMIN_OWNER_TOKEN;
  const githubToken = process.env.GITHUB_TOKEN || "";
  if (!apiBase || !ownerToken) throw new Error("BARQ_ADMIN_API_URL and BARQ_ADMIN_OWNER_TOKEN are required");
  const apiUrl = new URL(apiBase);
  if (apiUrl.protocol !== "https:") throw new Error("Admin API must use HTTPS");

  const tree = await requestJson(
    "https://api.github.com/repos/" + owner + "/" + repository +
      "/git/trees/" + encodeURIComponent(DEFAULT_REF) + "?recursive=1",
    githubToken
  );
  const revision = tree.sha;
  const files = (tree.tree || []).filter(item => item.type === "blob" &&
    item.size <= MAX_FILE_BYTES && shouldIndexPath(item.path)).slice(0, MAX_FILES);
  let indexed = 0;
  let skipped = 0;

  for (const file of files) {
    try {
      const rawUrl = "https://raw.githubusercontent.com/" + owner + "/" + repository +
        "/" + revision + "/" + file.path.split("/").map(encodeURIComponent).join("/");
      const response = await fetch(rawUrl, { signal: AbortSignal.timeout(30000) });
      if (!response.ok) throw new Error("raw file fetch failed: " + response.status);
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.byteLength > MAX_FILE_BYTES) { skipped++; continue; }
      const text = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
      const chunks = splitKnowledgeContent(text);
      for (let i = 0; i < chunks.length; i++) {
        const sourcePath = chunks.length === 1 ? file.path : file.path + "#part-" + (i + 1);
        const result = await fetch(new URL("/v1/knowledge", apiUrl), {
          method: "POST",
          headers: {
            Authorization: "Bearer " + ownerToken,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            sourceType: inferSourceType(file.path),
            sourcePath,
            sourceRevision: revision,
            title: file.path + (chunks.length > 1 ? " — part " + (i + 1) : ""),
            content: chunks[i]
          }),
          signal: AbortSignal.timeout(30000)
        });
        if (!result.ok) throw new Error("Admin knowledge API failed: " + result.status);
        indexed++;
      }
    } catch (error) {
      skipped++;
      process.stderr.write("Skipped " + file.path + ": " + String(error.message || error) + "\n");
    }
  }
  process.stdout.write(JSON.stringify({ repository: owner + "/" + repository, revision, files: files.length, chunksIndexed: indexed, skipped }) + "\n");
}

if (import.meta.url === "file://" + process.argv[1]) {
  main().catch(error => {
    process.stderr.write(String(error.stack || error) + "\n");
    process.exitCode = 1;
  });
}
