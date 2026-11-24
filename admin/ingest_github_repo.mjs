import { pathToFileURL } from "node:url";

const MAX_CHUNK_CHARS = 18000;
const MAX_FILES_PER_RUN = 300;
const ALLOWED_EXTENSIONS = new Set([
  ".md", ".mdx", ".txt", ".dart", ".js", ".mjs", ".ts", ".tsx",
  ".jsx", ".html", ".css", ".json", ".java", ".kt", ".h", ".c", ".cpp", ".swift", ".plist", ".xcconfig", ".sql", ".yaml", ".yml", ".toml", ".xml", ".gradle", ".kts", ".properties", ".py", ".sh"
]);
const SENSITIVE_PATH = /(^|\/)(\.git|\.next|\.dart_tool|\.firebase|\.gradle|build|dist|node_modules|vendor|coverage|secrets?|credentials?)(\/|$)|(^|\/)(\.env[^/]*|local\.properties|key\.properties|.*\.(pem|key|p12|pfx|keystore|jks|apk|aab|ipa|sqlite|db|lock|tfvars))$/i;
const SECRET_CONTENT = [
  /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/,
  /AIza[0-9A-Za-z_-]{30,}/,
  /gh[pousr]_[A-Za-z0-9_]{30,}/,
  /github_pat_[A-Za-z0-9_]{30,}/,
  /AKIA[0-9A-Z]{16}/,
  /xox[baprs]-[A-Za-z0-9-]{20,}/,
  /(?:sk|rk)_live_[A-Za-z0-9]{16,}/,
  /GOCSPX-[A-Za-z0-9_-]{20,}/,
  /npm_[A-Za-z0-9]{30,}/,
  /pypi-[A-Za-z0-9_-]{50,}/,
  /SG\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}/,
  /(?:api[_-]?key|private[_-]?key|signing[_-]?key|secret|access[_-]?token|refresh[_-]?token|client[_-]?secret|auth[_-]?token|password)["']?\s*[:=]\s*["'][^"']{12,}["']/i
];

export async function fetchWithRetry(url, options = {}, dependencies = {}) {
  const fetchImpl = dependencies.fetchImpl || fetch;
  const sleep = dependencies.sleep || (milliseconds =>
    new Promise(resolve => setTimeout(resolve, milliseconds)));
  const maxAttempts = Number.isSafeInteger(dependencies.maxAttempts)
    ? Math.max(1, Math.min(dependencies.maxAttempts, 5))
    : 3;
  let lastError;
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const response = await fetchImpl(url, {
        ...options,
        signal: options.signal || AbortSignal.timeout(30000)
      });
      const retryable = response.status === 408 || response.status === 425 ||
        response.status === 429 || response.status >= 500;
      if (!retryable || attempt === maxAttempts) return response;
      const retryAfterHeader = response.headers?.get?.("retry-after");
      const retryAfter = retryAfterHeader == null || retryAfterHeader.trim() === ""
        ? Number.NaN
        : Number(retryAfterHeader);
      const delay = Number.isFinite(retryAfter) && retryAfter >= 0
        ? Math.min(retryAfter * 1000, 5000)
        : Math.min(250 * (2 ** (attempt - 1)), 2000);
      await sleep(delay);
    } catch (error) {
      lastError = error;
      if (attempt === maxAttempts) throw error;
      await sleep(Math.min(250 * (2 ** (attempt - 1)), 2000));
    }
  }
  throw lastError || new Error("request_retry_exhausted");
}

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
    .sort((a, b) => a.path.localeCompare(b.path));
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

export function classifyIndexPath(input) {
  if (typeof input !== "string" || !input || input.length > 160) return "invalid_path";
  const path = input.replace(/\\/g, "/");
  if (path.startsWith("/") || path.split("/").some(part => part === ".." || part === ".")) return "unsafe_path";
  if (SENSITIVE_PATH.test(path)) return "sensitive_path";
  const name = path.split("/").pop() || "";
  if (!name || name.startsWith(".")) return "hidden_file";
  if (/google-services|firebase-admin|service-account|credentials|secrets?/i.test(name)) return "credential_filename";
  const dot = name.lastIndexOf(".");
  const extension = dot >= 0 ? name.slice(dot).toLowerCase() : "";
  if (!ALLOWED_EXTENSIONS.has(extension)) return "unsupported_file_type";
  return "eligible";
}

export function shouldIndexPath(input) {
  return classifyIndexPath(input) === "eligible";
}

export function buildRepositoryCoverageReport(entries, maxFileBytes = 120000) {
  if (!Number.isSafeInteger(maxFileBytes) || maxFileBytes < 1) {
    throw new TypeError("invalid_max_file_size");
  }
  const report = {
    treeBlobs: 0,
    eligibleFiles: 0,
    oversizedFiles: 0,
    excludedByReason: {},
    eligibleByExtension: {},
    eligibleByDomain: {}
  };
  for (const entry of entries || []) {
    if (!entry || entry.type !== "blob" || typeof entry.path !== "string") continue;
    report.treeBlobs++;
    const classification = classifyIndexPath(entry.path);
    if (classification !== "eligible") {
      report.excludedByReason[classification] = (report.excludedByReason[classification] || 0) + 1;
      continue;
    }
    if (!Number.isSafeInteger(entry.size) || entry.size < 0) {
      report.excludedByReason.invalid_file_size = (report.excludedByReason.invalid_file_size || 0) + 1;
      continue;
    }
    if (entry.size > maxFileBytes) {
      report.oversizedFiles++;
      continue;
    }
    report.eligibleFiles++;
    const name = entry.path.split("/").pop() || "";
    const dot = name.lastIndexOf(".");
    const extension = dot >= 0 ? name.slice(dot).toLowerCase() : "(no extension)";
    report.eligibleByExtension[extension] = (report.eligibleByExtension[extension] || 0) + 1;
    const first = entry.path.split("/")[0] || "root";
    const domain = first.startsWith(".") ? "ci-and-config" :
      first === "android" ? "barq-consumer-android" :
      first === "src" ? "barq-consumer-backend" :
      first === "admin" ? "barq-admin" :
      first === "docs" || first === "documentation" ? "product-docs" : "root-and-other";
    report.eligibleByDomain[domain] = (report.eligibleByDomain[domain] || 0) + 1;
  }
  return report;
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

export async function githubJson(url, token, dependencies = {}) {
  const response = await fetchWithRetry(url, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: "Bearer " + token,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "BARQ-Admin-Knowledge-Ingest"
    }
  }, dependencies);
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
  const coverage = buildRepositoryCoverageReport(tree.tree || []);
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
      const response = await fetchWithRetry(apiBase + "/v1/knowledge", {
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
  let reconciliation = null;
  const complete = batch.remaining === 0;
  if (complete) {
    const response = await fetchWithRetry(apiBase + "/v1/knowledge/reconcile", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + ownerToken,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({ repository, sourceRevision: revision, complete: true })
    });
    if (!response.ok) throw new Error("admin_knowledge_reconciliation_" + response.status);
    reconciliation = await response.json();
  }
  return {
    repository,
    revision,
    coverage,
    indexed,
    skipped,
    eligibleFiles: batch.eligibleFiles,
    eligibleFilesAfterCursor: batch.eligibleFilesAfterCursor,
    processedFiles: batch.processedFiles,
    remainingFiles: batch.remaining,
    complete,
    reconciliation,
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
