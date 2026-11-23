const encoder = new TextEncoder();
const TASK_STATUSES = new Set(["queued", "running", "paused", "needs_approval", "failed", "completed", "cancelled"]);
const TRANSITIONS = {
  queued: new Set(["running", "paused", "cancelled", "needs_approval"]),
  running: new Set(["paused", "needs_approval", "failed", "completed", "cancelled"]),
  paused: new Set(["queued", "running", "cancelled"]),
  needs_approval: new Set(["queued", "paused", "cancelled"]),
  failed: new Set(["queued", "cancelled"]),
  completed: new Set(),
  cancelled: new Set()
};
const MAX_JSON_BYTES = 32 * 1024;

function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function decodeBase64url(value) {
  const normalized = value.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(normalized + "=".repeat((4 - normalized.length % 4) % 4));
  return Uint8Array.from(binary, char => char.charCodeAt(0));
}

export function validateTaskInput(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, error: "invalid_body" };
  }
  const title = typeof value.title === "string" ? value.title.trim() : "";
  const description = typeof value.description === "string" ? value.description.trim() : "";
  const priority = value.priority ?? "normal";
  if (!title || title.length > 180 || description.length > 8000) {
    return { ok: false, error: "invalid_task_text" };
  }
  if (!["low", "normal", "high", "urgent"].includes(priority)) {
    return { ok: false, error: "invalid_priority" };
  }
  return { ok: true, value: { title, description, priority } };
}

export function canTransitionTask(from, to) {
  return TASK_STATUSES.has(from) && TASK_STATUSES.has(to) && Boolean(TRANSITIONS[from]?.has(to));
}

export function validateCheckpointInput(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, error: "invalid_body" };
  }
  if (!Number.isSafeInteger(value.expectedVersion) || value.expectedVersion < 0) {
    return { ok: false, error: "invalid_expected_version" };
  }
  const completedStep = typeof value.completedStep === "string" ? value.completedStep.trim() : "";
  const nextAction = typeof value.nextAction === "string" ? value.nextAction.trim() : "";
  const input = value.input ?? {};
  const output = value.output ?? {};
  try {
    const inputJson = JSON.stringify(input);
    const outputJson = JSON.stringify(output);
    if (inputJson === undefined || outputJson === undefined ||
        encoder.encode(inputJson).length + encoder.encode(outputJson).length > MAX_JSON_BYTES) {
      return { ok: false, error: "checkpoint_payload_too_large" };
    }
    return { ok: true, value: { completedStep, nextAction, inputJson, outputJson } };
  } catch {
    return { ok: false, error: "invalid_checkpoint_payload" };
  }
}

async function verifyOwnerToken(request, env) {
  const authorization = request.headers.get("Authorization") || "";
  if (!authorization.startsWith("Bearer ")) return null;
  const token = authorization.slice(7);
  if (token.length > 8192 || !env.BARQ_ADMIN_JWT_SECRET ||
      env.BARQ_ADMIN_JWT_SECRET.length < 32 || !env.BARQ_ADMIN_OWNER_SUBJECT) return null;
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const header = JSON.parse(new TextDecoder().decode(decodeBase64url(parts[0])));
    if (header.alg !== "HS256" || header.typ !== "JWT") return null;
    const key = await crypto.subtle.importKey(
      "raw", encoder.encode(env.BARQ_ADMIN_JWT_SECRET),
      { name: "HMAC", hash: "SHA-256" }, false, ["verify"]
    );
    const valid = await crypto.subtle.verify(
      "HMAC", key, decodeBase64url(parts[2]), encoder.encode(parts[0] + "." + parts[1])
    );
    if (!valid) return null;
    const claims = JSON.parse(new TextDecoder().decode(decodeBase64url(parts[1])));
    const now = Math.floor(Date.now() / 1000);
    if (claims.iss !== "barq-admin-auth" || claims.aud !== "barq-admin" ||
        typeof claims.sub !== "string" || claims.sub !== env.BARQ_ADMIN_OWNER_SUBJECT ||
        !Number.isSafeInteger(claims.exp) || claims.exp <= now ||
        (claims.nbf !== undefined && (!Number.isSafeInteger(claims.nbf) || claims.nbf > now))) {
      return null;
    }
    return { subject: claims.sub, deviceId: typeof claims.did === "string" ? claims.did.slice(0, 100) : "" };
  } catch {
    return null;
  }
}

function response(data, status = 200, origin = "") {
  const headers = {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "DENY",
    "Referrer-Policy": "no-referrer",
    "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'",
    "Vary": "Origin"
  };
  if (origin) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type, X-Idempotency-Key";
    headers["Access-Control-Allow-Methods"] = "GET, POST, PATCH, OPTIONS";
  }
  return new Response(JSON.stringify(data), { status, headers });
}

async function readJson(request) {
  const length = Number(request.headers.get("Content-Length") || 0);
  if (length > MAX_JSON_BYTES) return null;
  try {
    const text = await request.text();
    if (encoder.encode(text).length > MAX_JSON_BYTES) return null;
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function workspaceId(subject) {
  return "owner:" + subject;
}

async function ensureWorkspace(env, actor) {
  const id = workspaceId(actor.subject);
  await env.ADMIN_DB.prepare(
    "INSERT OR IGNORE INTO admin_workspaces (id, owner_subject) VALUES (?, ?)"
  ).bind(id, actor.subject).run();
  return id;
}

async function audit(env, workspace, actor, eventType, targetType, targetId, details = {}) {
  await env.ADMIN_DB.prepare(`
    INSERT INTO admin_audit_events
      (id, workspace_id, actor_subject, actor_device_id, event_type, target_type, target_id, details_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
  `).bind(crypto.randomUUID(), workspace, actor.subject, actor.deviceId,
    eventType, targetType, targetId, JSON.stringify(details)).run();
}

async function listTasks(env, workspace) {
  const result = await env.ADMIN_DB.prepare(`
    SELECT id, title, description, status, priority, checkpoint_version,
      last_checkpoint_id, next_action, attempt_count, created_at, updated_at
    FROM admin_tasks WHERE workspace_id = ?
    ORDER BY updated_at DESC LIMIT 100
  `).bind(workspace).all();
  return result.results || [];
}

async function handle(request, env) {
  const url = new URL(request.url);
  const configuredOrigin = env.BARQ_ADMIN_ALLOWED_ORIGIN || "";
  const requestOrigin = request.headers.get("Origin") || "";
  const allowedOrigin = configuredOrigin && requestOrigin === configuredOrigin ? requestOrigin : "";
  if (request.method === "OPTIONS") {
    if (!allowedOrigin) return response({ error: "origin_not_allowed" }, 403);
    return new Response(null, { status: 204, headers: {
      "Access-Control-Allow-Origin": allowedOrigin,
      "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Idempotency-Key",
      "Access-Control-Allow-Methods": "GET, POST, PATCH, OPTIONS",
      "Vary": "Origin"
    }});
  }
  if (url.pathname === "/health") return response({ ok: true, service: "barq-admin-preview" });
  if (!env.ADMIN_DB) return response({ error: "admin_database_unavailable" }, 503, allowedOrigin);
  const actor = await verifyOwnerToken(request, env);
  if (!actor) return response({ error: "unauthorized" }, 401, allowedOrigin);
  const workspace = await ensureWorkspace(env, actor);

  if (request.method === "GET" && url.pathname === "/v1/workspace") {
    const row = await env.ADMIN_DB.prepare(
      "SELECT id, display_name, current_project, current_phase, version, updated_at FROM admin_workspaces WHERE id = ?"
    ).bind(workspace).first();
    return response({ workspace: row, tasks: await listTasks(env, workspace) }, 200, allowedOrigin);
  }

  if (request.method === "GET" && url.pathname === "/v1/tasks") {
    return response({ tasks: await listTasks(env, workspace) }, 200, allowedOrigin);
  }

  if (request.method === "POST" && url.pathname === "/v1/tasks") {
    const body = await readJson(request);
    const parsed = validateTaskInput(body);
    if (!parsed.ok) return response({ error: parsed.error }, 400, allowedOrigin);
    const id = crypto.randomUUID();
    const idempotencyKey = (request.headers.get("X-Idempotency-Key") || "").slice(0, 128) || null;
    try {
      await env.ADMIN_DB.prepare(`
        INSERT INTO admin_tasks (id, workspace_id, created_by, title, description, priority, idempotency_key)
        VALUES (?, ?, ?, ?, ?, ?, ?)
      `).bind(id, workspace, actor.subject, parsed.value.title, parsed.value.description,
        parsed.value.priority, idempotencyKey).run();
    } catch (error) {
      if (idempotencyKey) {
        const existing = await env.ADMIN_DB.prepare(
          "SELECT id, title, status, checkpoint_version FROM admin_tasks WHERE workspace_id = ? AND idempotency_key = ?"
        ).bind(workspace, idempotencyKey).first();
        if (existing) return response({ task: existing, duplicate: true }, 200, allowedOrigin);
      }
      throw error;
    }
    await audit(env, workspace, actor, "task.created", "task", id,
      { priority: parsed.value.priority });
    const task = await env.ADMIN_DB.prepare(
      "SELECT id, title, description, status, priority, checkpoint_version, next_action, created_at FROM admin_tasks WHERE id = ?"
    ).bind(id).first();
    return response({ task }, 201, allowedOrigin);
  }

  const checkpointMatch = url.pathname.match(/^\/v1\/tasks\/([0-9a-f-]{36})\/checkpoints$/i);
  if (request.method === "POST" && checkpointMatch) {
    const taskId = checkpointMatch[1];
    const body = await readJson(request);
    const parsed = validateCheckpointInput(body);
    if (!parsed.ok) return response({ error: parsed.error }, 400, allowedOrigin);
    const task = await env.ADMIN_DB.prepare(
      "SELECT id, status, checkpoint_version FROM admin_tasks WHERE id = ? AND workspace_id = ?"
    ).bind(taskId, workspace).first();
    if (!task) return response({ error: "task_not_found" }, 404, allowedOrigin);
    if (!["queued", "running", "paused", "failed"].includes(task.status)) {
      return response({ error: "task_not_checkpointable" }, 409, allowedOrigin);
    }
    if (task.checkpoint_version !== parsed.value.expectedVersion) {
      return response({ error: "checkpoint_version_conflict", currentVersion: task.checkpoint_version }, 409, allowedOrigin);
    }
    const nextVersion = task.checkpoint_version + 1;
    const checkpointId = crypto.randomUUID();
    const results = await env.ADMIN_DB.batch([
      env.ADMIN_DB.prepare(`
        UPDATE admin_tasks SET checkpoint_version = ?, last_checkpoint_id = ?,
          next_action = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND workspace_id = ? AND checkpoint_version = ?
      `).bind(nextVersion, checkpointId, parsed.value.nextAction, taskId, workspace, parsed.value.expectedVersion),
      env.ADMIN_DB.prepare(`
        INSERT INTO admin_task_checkpoints
          (id, task_id, sequence, input_json, output_json, completed_step, next_action, created_by)
        SELECT ?, ?, ?, ?, ?, ?, ?, ?
        WHERE EXISTS (
          SELECT 1 FROM admin_tasks WHERE id = ? AND last_checkpoint_id = ? AND checkpoint_version = ?
        )
      `).bind(checkpointId, taskId, nextVersion, parsed.value.inputJson, parsed.value.outputJson,
        parsed.value.completedStep, parsed.value.nextAction, actor.subject, taskId, checkpointId, nextVersion)
    ]);
    if (!results?.[0]?.meta?.changes || !results?.[1]?.meta?.changes) {
      return response({ error: "checkpoint_version_conflict" }, 409, allowedOrigin);
    }
    await audit(env, workspace, actor, "task.checkpoint.saved", "task", taskId,
      { version: nextVersion, completedStep: parsed.value.completedStep });
    return response({ checkpoint: { id: checkpointId, version: nextVersion,
      completedStep: parsed.value.completedStep, nextAction: parsed.value.nextAction } }, 201, allowedOrigin);
  }

  const statusMatch = url.pathname.match(/^\/v1\/tasks\/([0-9a-f-]{36})\/status$/i);
  if (request.method === "PATCH" && statusMatch) {
    const taskId = statusMatch[1];
    const body = await readJson(request);
    const nextStatus = body?.status;
    const task = await env.ADMIN_DB.prepare(
      "SELECT status FROM admin_tasks WHERE id = ? AND workspace_id = ?"
    ).bind(taskId, workspace).first();
    if (!task) return response({ error: "task_not_found" }, 404, allowedOrigin);
    if (!canTransitionTask(task.status, nextStatus)) {
      return response({ error: "invalid_status_transition", from: task.status, to: nextStatus }, 409, allowedOrigin);
    }
    await env.ADMIN_DB.prepare(
      "UPDATE admin_tasks SET status = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ? AND workspace_id = ? AND status = ?"
    ).bind(nextStatus, taskId, workspace, task.status).run();
    await audit(env, workspace, actor, "task.status.changed", "task", taskId,
      { from: task.status, to: nextStatus });
    return response({ task: { id: taskId, status: nextStatus } }, 200, allowedOrigin);
  }

  return response({ error: "not_found" }, 404, allowedOrigin);
}

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      // Keep secrets and raw SQL details out of client responses.
      console.error("BARQ Admin request failed:", error);
      return response({ error: "internal_error" }, 500);
    }
  }
};
