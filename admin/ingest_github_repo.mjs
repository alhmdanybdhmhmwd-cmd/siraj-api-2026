import { pathToFileURL } from "node:url";

const MAX_CHUNK_CHARS = 18000;
const MAX_FILES_PER_RUN = 300;
const ALLOWED_EXTENSIONS = new Set([
  ".md", ".mdx", ".txt", ".dart", ".js", ".mjs", ".ts", ".tsx",
  ".jsx", ".sql", ".yaml", ".yml", ".toml", ".xml", ".gradle", ".kts", ".properties", ".py", ".sh"
]);
const SENSITIVE_PATH = /(^|\/)(\.git|\.next|\.dart_tool|build|dist|node_modules|vendor|coverage|secrets?|credentials?)(\/|$)|(^|\/)(\.env[^/]*|.*\.(pem|key|p12|pfx|keystore|jks|apk|aab|ipa|sqlite|db|lock))$/i;
const SECRET_CONTENT = [
  /-----BEGIN (?:(?:RSA|EC|OPENSSH|DSA) )?PRIVATE KEY-----/,
  /AIza[0-9A-Za-z_-]{30,}/,
  /gh[pousr]_[A-Za-z0-9_]{30,}/,
  /github_pat_[A-Za-z0-9_]{30,}/,
  /AKIA[0-9A-Z]{16}/,
  /xox[baprs]-[A-Za-z0-9-]{20,}/,
  /\bsk_live_[A-Za-z0-9]{16,}\b/,
  /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/,
  /(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*["'][^"']{12,}["']/i,
  /(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)\s*[:=]\s*[^\s"'#]{16,}/i
];

export function normalizeAllowedRepositories(value) {
  if (typeof value !== "string" || !value.trim()) {
    throw new TypeError("explicit_repository_allowlist_required");
  }
  const repositories = [...new Set(value.split(";").map(item => item.trim()).filter(Boolean))];
  if (!repositories.length || repositories.some(item =>
    !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(item) ||
    item.split("/").some(part => part === "." || part === "..")
  )) {
    throw new TypeError("invalid_repository_allowlist");
  }
  return repositories;
}

export function selectIndexBatch(entries, startAfter = "", limit = MAX_FILES_PER_RUN) {
  if (typeof startAfter !== "string" || startAfter.length > 160 ||
      startAfter.startsWith("/") || startAfter.split("/").some(part => part === "..") ||
      !Number.isSafeInteger(limit) || limit < 1 || limit > 1000) {
    throw new TypeError("invalid_index_batch");
  }
  const ordered = (entries || [])
    .filter(entry => entry && typeof entry.path === "string" && entry.path > startAfter)
    .sort((a, b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  const selected = ordered.slice(0, limit);
  const remaining = ordered.length - selected.length;
  return {
    selected,
    eligibleAfterCursor: ordered.length,
    remaining,
    nextStartAfter: remaining > 0 && selected.length
      ? selected[selected.length - 1].path
      : null
  };
}

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

export function selectIndexBatchWithSkips(entries, startAfter = "", limit = MAX_FILES_PER_RUN, maxFileBytes = 120000) {
  if (!Number.isSafeInteger(maxFileBytes) || maxFileBytes < 1) {
    throw new TypeError("invalid_max_file_size");
  }
  const candidates = (entries || []).filter(entry =>
    entry && entry.type === "blob" && shouldIndexPath(entry.path)
  );
  const eligible = candidates.filter(entry => entry.size <= maxFileBytes);
  const batch = selectIndexBatch(eligible, startAfter, limit);
  const lastSelectedPath = batch.selected.length
    ? batch.selected[batch.selected.length - 1].path
    : null;
  const skippedOversizeFiles = candidates.filter(entry =>
    entry.size > maxFileBytes && entry.path > startAfter &&
    (!lastSelectedPath || entry.path <= lastSelectedPath || batch.remaining === 0)
  ).length;
  return {
    ...batch,
    eligibleFiles: candidates.length,
    eligibleFilesAfterCursor: candidates.filter(entry => entry.path > startAfter).length,
    processedFiles: batch.selected.length + skippedOversizeFiles,
    skippedOversizeFiles
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

export function containsLikelySecret(content) {
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

export async function ingestRepository({ repository, ref = "HEAD", startAfter = "", githubToken, adminApiUrl, ownerToken, allowedRepositories }) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository || "") ||
      !githubToken || !adminApiUrl || !ownerToken) {
    throw new Error("missing_ingestion_configuration");
  }
  const allowed = normalizeAllowedRepositories(Array.isArray(allowedRepositories)
    ? allowedRepositories.join(";")
    : process.env.BARQ_ADMIN_GITHUB_ALLOWED_REPOSITORIES);
  if (!allowed.includes(repository)) throw new Error("repository_not_owner_approved");
  if (startAfter && !/^[a-f0-9]{40}$/i.test(ref)) {
    throw new Error("resume_requires_immutable_commit_sha");
  }
  const apiBase = normalizeAdminApiUrl(adminApiUrl);
  const commit = await githubJson(
    "https://api.github.com/repos/" + repository + "/commits/" + encodeURIComponent(ref),
    githubToken
  );
  const revision = commit.sha;
  if (startAfter && revision.toLowerCase() !== ref.toLowerCase()) {
    throw new Error("resume_commit_sha_mismatch");
  }
  const tree = await githubJson(
    "https://api.github.com/repos/" + repository + "/git/trees/" + revision + "?recursive=1",
    githubToken
  );
  if (tree.truncated) throw new Error("repository_tree_truncated_refusing_partial_index");
  let indexed = 0;
  let skipped = 0;
  const batch = selectIndexBatchWithSkips(tree.tree || [], startAfter, MAX_FILES_PER_RUN);
  const selectedEntries = batch.selected;
  skipped = batch.skippedOversizeFiles;
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
    repository,
    revision,
    resumeRef: revision,
    indexed,
    skipped,
    eligibleFiles: batch.eligibleFiles,
    eligibleFilesAfterCursor: batch.eligibleFilesAfterCursor,
    processedFiles: batch.processedFiles,
    remainingFiles: batch.remaining,
    complete: batch.remaining === 0,
    nextStartAfter: batch.nextStartAfter
  };
}

async function main() {
  const result = await ingestRepository({
    repository: process.env.BARQ_ADMIN_GITHUB_REPOSITORY,
    ref: process.env.BARQ_ADMIN_GITHUB_REF || "HEAD",
    startAfter: process.env.BARQ_ADMIN_GITHUB_START_AFTER || "",
    githubToken: process.env.BARQ_ADMIN_GITHUB_TOKEN,
    adminApiUrl: process.env.BARQ_ADMIN_API_URL,
    ownerToken: process.env.BARQ_ADMIN_OWNER_TOKEN,
    allowedRepositories: normalizeAllowedRepositories(process.env.BARQ_ADMIN_GITHUB_ALLOWED_REPOSITORIES)
  });
  process.stdout.write(JSON.stringify(result) + "\n");
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => {
    process.stderr.write(String(error.message || error) + "\n");
    process.exitCode = 1;
  });
}
