import { pathToFileURL } from "node:url";

const MAX_CHUNK_CHARS = 18000;
const MAX_FILES_PER_RUN = 300;
const ALLOWED_EXTENSIONS = new Set([
  ".md", ".mdx", ".txt", ".dart", ".js", ".mjs", ".ts", ".tsx",
  ".jsx", ".sql", ".yaml", ".yml", ".toml", ".xml", ".gradle", ".kts", ".properties", ".py", ".sh"
]);
const SENSITIVE_PATH = /(^|\/)(\.git|\.next|\.dart_tool|build|dist|node_modules|vendor|coverage|secrets?|credentials?)(\/|$)|(^|\/)(\.env[^/]*|.*\.(pem|key|p12|pfx|keystore|jks|apk|aab|ipa|sqlite|db|lock))$/i;
const SECRET_CONTENT = [
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /AIza[0-9A-Za-z_-]{30,}/,
  /gh[pousr]_[A-Za-z0-9_]{30,}/,
  /(?:api[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*["'][^"']{12,}["']/i
];

export function summarizeIndexCoverage(eligibleFiles, processedFiles) {
  if (!Number.isSafeInteger(eligibleFiles) || eligibleFiles < 0 ||
      !Number.isSafeInteger(processedFiles) || processedFiles < 0 ||
      processedFiles > eligibleFiles) {
    throw new TypeError("invalid_index_coverage");
  }
  return {
    eligibleFiles,
    processedFiles,
    remainingFiles: eligibleFiles - processedFiles,
    complete: processedFiles === eligibleFiles
  };
}

export function normalizeAdminApiUrl(input) {
  let parsed;
  try {
    parsed = new URL(input);
  } catch {
    throw new TypeError("invalid_admin_api_url");
  }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password ||
      parsed.search || parsed.hash) {
    throw new TypeError("admin_api_url_must_be_https_without_credentials_or_query");
  }
  return parsed.toString().replace(/\/+$/, "");
}

export function shouldIndexPath(input) {
  if (typeof input !== "string" || !input || input.length > 160) return false;
  const path = input.replace(/\\/g, "/");
  if (path.startsWith("/") || path.split("/").some(part => part === ".." || part === ".")) return false;
  if (SENSITIVE_PATH.test(path)) return false;
  const name = path.split("/").pop() || "";
  if (!name || name.startsWith(".")) return false;
  const dot = name.lastIndexOf(".");
  const extension = dot >= 0 ? name.slice(dot).toLowerCase() : "";
  if (!ALLOWED_EXTENSIONS.has(extension)) return false;
  if (/google-services|firebase-admin|service-account|credentials|secrets?/i.test(name)) return false;
  return true;
}

export function splitKnowledgeContent(source, maxChars = MAX_CHUNK_CHARS) {
  if (typeof source !== "string" || !Number.isSafeInteger(maxChars) || maxChars < 100) {
    throw new TypeError("invalid_chunk_input");
  }
  const normalized = source.replace(/\r\n?/g, "\n").trim();
  if (!normalized) return [];
  const chunks = [];
  let current = "";
  for (const line of normalized.split("\n")) {
    let remaining = line;
    while (remaining.length > maxChars) {
      if (current) {
        chunks.push(current);
        current = "";
      }
      chunks.push(remaining.slice(0, maxChars));
      remaining = remaining.slice(maxChars);
    }
    const candidate = current ? current + "\n" + remaining : remaining;
    if (candidate.length > maxChars) {
      if (current) chunks.push(current);
      current = remaining;
    } else {
      current = candidate;
    }
  }
  if (current) chunks.push(current);
  return chunks;
}

export function inferSourceType(path) {
  const value = String(path || "").toLowerCase();
  if (/product|requirement|specification|prd/.test(value)) return "product_requirement";
  if (/architecture|blueprint|decision|adr/.test(value)) return "architecture_decision";
  if (/(^|\/)migrations?\//.test(value) || /openapi|swagger|api[-_]contract/.test(value)) return "api_contract";
  if (/(^|\/)(test|tests|__tests__|\.github\/workflows)(\/|$)|\.(test|spec)\./.test(value)) return "test_report";
  if (/launch|marketing|growth|campaign/.test(value)) return "launch_material";
  if (/runbook|operations|incident/.test(value)) return "runbook";
  return "repository_file";
}

function containsLikelySecret(content) {
  return SECRET_CONTENT.some(pattern => pattern.test(content));
}

async function githubJson(url, token) {
  const response = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: "Bearer " + token,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "BARQ-Admin-Knowledge-Ingest"
    }
  });
  if (!response.ok) throw new Error("github_api_" + response.status);
  return response.json();
}

export async function ingestRepository({ repository, ref = "HEAD", githubToken, adminApiUrl, ownerToken }) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository || "") ||
      !githubToken || !adminApiUrl || !ownerToken) {
    throw new Error("missing_ingestion_configuration");
  }
  const apiBase = normalizeAdminApiUrl(adminApiUrl);
  const commit = await githubJson(
    "https://api.github.com/repos/" + repository + "/commits/" + encodeURIComponent(ref),
    githubToken
  );
  const revision = commit.sha;
  const tree = await githubJson(
    "https://api.github.com/repos/" + repository + "/git/trees/" + revision + "?recursive=1",
    githubToken
  );
  if (tree.truncated) throw new Error("repository_tree_truncated_refusing_partial_index");
  let indexed = 0;
  let skipped = 0;
  const eligibleEntries = (tree.tree || []).filter(item =>
    item.type === "blob" && shouldIndexPath(item.path) && item.size <= 120000
  );
  const selectedEntries = eligibleEntries.slice(0, MAX_FILES_PER_RUN);
  for (const entry of selectedEntries) {
    if (entry.type !== "blob" || !shouldIndexPath(entry.path) || entry.size > 120000) {
      skipped++;
      continue;
    }
    const blob = await githubJson(
      "https://api.github.com/repos/" + repository + "/git/blobs/" + entry.sha,
      githubToken
    );
    if (blob.encoding !== "base64" || typeof blob.content !== "string") {
      skipped++;
      continue;
    }
    const source = Buffer.from(blob.content.replace(/\n/g, ""), "base64").toString("utf8");
    if (!source.trim() || source.includes("\u0000") || containsLikelySecret(source)) {
      skipped++;
      continue;
    }
    const chunks = splitKnowledgeContent(source);
    for (let index = 0; index < chunks.length; index++) {
      const response = await fetch(apiBase + "/v1/knowledge", {
        method: "POST",
        headers: {
          Authorization: "Bearer " + ownerToken,
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          sourceType: inferSourceType(entry.path),
          sourcePath: repository + "/" + (chunks.length === 1 ? entry.path : entry.path + "#chunk-" + (index + 1)),
          sourceRevision: revision,
          title: entry.path + (chunks.length > 1 ? " (part " + (index + 1) + ")" : ""),
          content: chunks[index]
        })
      });
      if (!response.ok) throw new Error("admin_knowledge_api_" + response.status + "_at_" + entry.path);
      indexed++;
    }
  }
  return {
    repository, revision, indexed, skipped,
    ...summarizeIndexCoverage(eligibleEntries.length, selectedEntries.length)
  };
}

async function main() {
  const result = await ingestRepository({
    repository: process.env.BARQ_ADMIN_GITHUB_REPOSITORY,
    ref: process.env.BARQ_ADMIN_GITHUB_REF || "HEAD",
    githubToken: process.env.BARQ_ADMIN_GITHUB_TOKEN,
    adminApiUrl: process.env.BARQ_ADMIN_API_URL,
    ownerToken: process.env.BARQ_ADMIN_OWNER_TOKEN
  });
  process.stdout.write(JSON.stringify(result) + "\n");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => {
    process.stderr.write(String(error.message || error) + "\n");
    process.exitCode = 1;
  });
}
