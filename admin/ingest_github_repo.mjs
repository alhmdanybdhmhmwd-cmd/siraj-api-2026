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
  /\bbearer\s+[A-Za-z0-9._~-]{24,}\b/i,
  /(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret[_-]?key|aws[_-]?secret[_-]?access[_-]?key|password)\s*[:=]\s*["'][^"']{12,}["']/i,
  /(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret[_-]?key|aws[_-]?secret[_-]?access[_-]?key|password)\s*[:=]\s*[^\s"'#]{16,}/i
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

export function classifyIndexPath(input) {
  if (typeof input !== "string" || !input || input.length > 160) return "invalid_path";
  const path = input.replace(/\\/g, "/");
  if (path.startsWith("/") || path.split("/").some(part => part === ".." || part === ".")) {
    return "unsafe_path";
  }
  if (SENSITIVE_PATH.test(path)) return "sensitive_path";
  const name = path.split("/").pop() || "";
  if (!name || name.startsWith(".")) return "hidden_file";
  const dot = name.lastIndexOf(".");
  const extension = dot >= 0 ? name.slice(dot).toLowerCase() : "";
  if (!ALLOWED_EXTENSIONS.has(extension)) return "unsupported_extension";
  if (/google-services|firebase-admin|service-account|credentials|secrets?/i.test(name)) {
    return "sensitive_filename";
  }
  return null;
}

export function selectIndexBatchWithSkips(entries, startAfter = "", limit = MAX_FILES_PER_RUN, maxFileBytes = 120000) {
  if (!Number.isSafeInteger(maxFileBytes) || maxFileBytes < 1) {
    throw new TypeError("invalid_max_file_size");
  }
  const blobs = (entries || []).filter(entry =>
    entry && entry.type === "blob" && typeof entry.path === "string" && entry.path > startAfter
  );
  const eligible = [];
  for (const entry of blobs) {
    if (classifyIndexPath(entry.path) !== null) continue;
    if (!Number.isSafeInteger(entry.size) || entry.size < 0 || entry.size > maxFileBytes) continue;
    eligible.push(entry);
  }
  const batch = selectIndexBatch(eligible, startAfter, limit);
  const boundary = batch.remaining > 0 && batch.selected.length
    ? batch.selected[batch.selected.length - 1].path
    : null;
  const scanned = blobs.filter(entry => boundary === null || entry.path <= boundary);
  const skippedByReason = {};
  for (const entry of scanned) {
    const reason = classifyIndexPath(entry.path) ||
      (!Number.isSafeInteger(entry.size) || entry.size < 0
        ? "invalid_size"
        : entry.size > maxFileBytes ? "oversized_file" : null);
    if (reason) skippedByReason[reason] = (skippedByReason[reason] || 0) + 1;
  }
  const skipped = Object.values(skippedByReason).reduce((total, count) => total + count, 0);
  return {
    ...batch,
    eligibleFiles: eligible.length + blobs.filter(entry => {
      const reason = classifyIndexPath(entry.path);
      return reason === null && Number.isSafeInteger(entry.size) && entry.size >= 0 &&
        entry.size > maxFileBytes;
    }).length,
    eligibleFilesAfterCursor: eligible.length + blobs.filter(entry => {
      const reason = classifyIndexPath(entry.path);
      return reason === null && Number.isSafeInteger(entry.size) && entry.size >= 0 &&
        entry.size > maxFileBytes;
    }).length,
    processedFiles: batch.selected.length + (skippedByReason.oversized_file || 0),
    remaining: batch.remaining,
    skippedOversizeFiles: skippedByReason.oversized_file || 0,
    skippedByReason
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
  return classifyIndexPath(input) === null;
}

export function splitKnowledgeContent(source, maxChars = MAX_CHUNK_CHARS) {
  if (typeof source !== "string" || !Number.isSafeInteger(maxChars) || maxChars < 100) {
    throw new TypeError("invalid_chunk_input");
  }
  const normalized = source.replace(/\r\n?/g, "\n");
  if (!normalized) return [];
  const chunks = [];
  let current = "";
  const parts = normalized.match(/[^\n]*\n|[^\n]+$/g) || [];
  for (let part of parts) {
    while (part.length > maxChars) {
      if (current) {
        chunks.push(current);
        current = "";
      }
      chunks.push(part.slice(0, maxChars));
      part = part.slice(maxChars);
    }
    if (current.length + part.length > maxChars) {
      if (current) chunks.push(current);
      current = part;
    } else {
      current += part;
    }
  }
  if (current) chunks.push(current);
  return chunks;
}
export function createKnowledgeChunkRecords(repository, path, revision, source, maxChars = MAX_CHUNK_CHARS) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository || "") ||
      !shouldIndexPath(path) || !/^[a-f0-9]{40}$/i.test(revision || "") ||
      typeof source !== "string") {
    throw new TypeError("invalid_knowledge_chunk_identity");
  }
  const chunks = splitKnowledgeContent(source, maxChars);
  return chunks.map((content, index) => ({
    sourceType: inferSourceType(path),
    sourcePath: repository + "/" + (chunks.length === 1 ? path : path + "#chunk-" + (index + 1)),
    sourceRevision: revision,
    title: path + (chunks.length > 1 ? " [part " + (index + 1) + " of " + chunks.length + "]" : ""),
    content
  }));
}

export function planKnowledgeReconciliation(repository, currentRevision, currentPaths, indexedSources) {
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository || "") ||
      !/^[a-f0-9]{40}$/i.test(currentRevision || "") ||
      !Array.isArray(currentPaths) || !Array.isArray(indexedSources)) {
    throw new TypeError("invalid_knowledge_reconciliation_input");
  }
  const parseChunk = source => {
    const match = String(source.sourcePath || "").match(/#chunk-(\d+)$/);
    if (!match) return { index: 1, count: 1, known: true };
    const title = String(source.title || "");
    const countMatch = title.match(/\[part\s+(\d+)\s+of\s+(\d+)\]$/i);
    if (!countMatch || Number(countMatch[1]) !== Number(match[1])) {
      return { index: Number(match[1]), count: null, known: false };
    }
    return { index: Number(match[1]), count: Number(countMatch[2]), known: true };
  };
  const normalizeSourcePath = value => String(value || "").replace(/#chunk-\d+$/, "");
  const current = new Set(currentPaths.filter(path =>
    typeof path === "string" && shouldIndexPath(path)
  ));
  const scoped = indexedSources.filter(source =>
    source && typeof source.sourcePath === "string" &&
    source.sourcePath.startsWith(repository + "/")
  );
  const currentRevisionGroups = new Map();
  const staleRevisions = [];
  const missingFromRepository = [];
  for (const source of scoped) {
    const relativePath = normalizeSourcePath(source.sourcePath.slice(repository.length + 1));
    if (!current.has(relativePath)) {
      missingFromRepository.push({
        sourcePath: source.sourcePath,
        sourceRevision: source.sourceRevision || null,
        relativePath
      });
    } else if (source.sourceRevision === currentRevision) {
      const group = currentRevisionGroups.get(relativePath) || [];
      group.push({ source, chunk: parseChunk(source) });
      currentRevisionGroups.set(relativePath, group);
    } else {
      staleRevisions.push({
        sourcePath: source.sourcePath,
        sourceRevision: source.sourceRevision || null,
        currentRevision
      });
    }
  }
  const incompleteChunks = [];
  const unknownChunkMetadata = [];
  const currentRevisionPaths = new Set();
  for (const [relativePath, records] of currentRevisionGroups) {
    const counts = new Set(records.filter(item => item.chunk.known).map(item => item.chunk.count));
    const metadataKnown = records.every(item => item.chunk.known) && counts.size === 1;
    if (!metadataKnown) {
      unknownChunkMetadata.push(relativePath);
      incompleteChunks.push({ relativePath, reason: "chunk_metadata_missing_or_inconsistent" });
      continue;
    }
    const expectedCount = [...counts][0];
    const indexes = new Set(records.map(item => item.chunk.index));
    const complete = indexes.size === expectedCount &&
      Array.from({ length: expectedCount }, (_, index) => index + 1).every(index => indexes.has(index));
    if (complete) {
      currentRevisionPaths.add(relativePath);
    } else {
      incompleteChunks.push({
        relativePath,
        expectedChunks: expectedCount,
        indexedChunks: indexes.size,
        missingChunkIndexes: Array.from({ length: expectedCount }, (_, index) => index + 1)
          .filter(index => !indexes.has(index))
      });
    }
  }
  const notYetIndexed = [...current].filter(path => !currentRevisionPaths.has(path));
  return {
    repository,
    currentRevision,
    currentPathCount: current.size,
    staleRevisions,
    missingFromRepository,
    notYetIndexed,
    incompleteChunks,
    unknownChunkMetadata,
    coverageGranularity: unknownChunkMetadata.length ? "file_presence_with_legacy_unknown_chunks" : "chunk_verified",
    chunkCompletenessVerified: unknownChunkMetadata.length === 0 &&
      incompleteChunks.length === 0,
    destructiveChangesApplied: false
  };
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

const retryDelay = milliseconds =>
  new Promise(resolve => setTimeout(resolve, milliseconds));

export async function fetchWithRetry(input, init, { attempts = 3, retryDelayMs = 250 } = {}) {
  if (!Number.isSafeInteger(attempts) || attempts < 1 || attempts > 5 ||
      !Number.isSafeInteger(retryDelayMs) || retryDelayMs < 0 || retryDelayMs > 5000) {
    throw new TypeError("invalid_fetch_retry_policy");
  }
  let lastError;
  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const response = await fetch(input, init);
      if (response.ok || (response.status !== 429 && response.status < 500)) return response;
      lastError = new Error("retryable_http_" + response.status);
    } catch (error) {
      lastError = error;
    }
    if (attempt + 1 < attempts) {
      await retryDelay(retryDelayMs * (attempt + 1));
    }
  }
  throw lastError || new Error("fetch_retry_exhausted");
}

async function githubJson(url, token) {
  const response = await fetchWithRetry(url, {
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
  const skippedByReason = { ...batch.skippedByReason };
  skipped = Object.values(skippedByReason).reduce((total, count) => total + count, 0);
  const recordSkip = reason => {
    skipped++;
    skippedByReason[reason] = (skippedByReason[reason] || 0) + 1;
  };
  for (const entry of selectedEntries) {
    if (entry.type !== "blob" || !shouldIndexPath(entry.path) || entry.size > 120000) {
      recordSkip("invalid_selected_entry");
      continue;
    }
    const blob = await githubJson(
      "https://api.github.com/repos/" + repository + "/git/blobs/" + entry.sha,
      githubToken
    );
    if (blob.encoding !== "base64" || typeof blob.content !== "string") {
      recordSkip("unreadable_blob");
      continue;
    }
    const source = Buffer.from(blob.content.replace(/\n/g, ""), "base64").toString("utf8");
    if (!source.trim() || source.includes("\u0000")) {
      recordSkip("empty_or_binary_content");
      continue;
    }
    if (containsLikelySecret(source)) {
      recordSkip("secret_pattern_detected");
      continue;
    }
    const records = createKnowledgeChunkRecords(repository, entry.path, revision, source);
    for (const record of records) {
      const response = await fetchWithRetry(apiBase + "/v1/knowledge", {
        method: "POST",
        headers: {
          Authorization: "Bearer " + ownerToken,
          "Content-Type": "application/json"
        },
        body: JSON.stringify(record)
      });
      if (!response.ok) {
        throw new Error("admin_knowledge_api_" + response.status + "_at_" + entry.path +
          "_revision_" + revision + "_cursor_" + (startAfter || "START"));
      }
      indexed++;
    }
  }
  return {
    repository,
    revision,
    resumeRef: revision,
    indexed,
    skipped,
    skippedByReason,
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
