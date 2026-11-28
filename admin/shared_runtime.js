import adminWorker from "./worker.js";

const ADMIN_PREFIX = "/admin";

export function createSharedAdminEnvironment(env) {
  return {
    ...env,
    // BARQ Admin intentionally shares the existing BARQ D1 and AI bindings.
    // Never fall back to a second Admin database in this integration path.
    ADMIN_DB: env?.DB ?? null,
    ADMIN_AI: env?.AI ?? null,
    ADMIN_TASK_QUEUE: env?.ADMIN_TASK_QUEUE ?? null,
    // Shared-runtime queue routing must be explicitly configured. In particular,
    // never inherit the standalone Preview queue names in BARQ's Worker.
    BARQ_ADMIN_TASK_QUEUE_NAME: env?.BARQ_ADMIN_TASK_QUEUE_NAME || null,
    BARQ_ADMIN_DEAD_LETTER_QUEUE_NAME: env?.BARQ_ADMIN_DEAD_LETTER_QUEUE_NAME || null,
    BARQ_ADMIN_RUNTIME_MODE: "shared"
  };
}

export async function handleSharedAdminRequest(request, env) {
  const url = new URL(request.url);
  if (url.pathname !== ADMIN_PREFIX && !url.pathname.startsWith(ADMIN_PREFIX + "/")) {
    return null;
  }

  // Keep the public Admin namespace distinct while reusing the Admin handler's
  // internal /v1 routes. Query strings, headers, method, and body are preserved.
  url.pathname = url.pathname.slice(ADMIN_PREFIX.length) || "/";
  const adminRequest = new Request(url, request);
  return adminWorker.fetch(adminRequest, createSharedAdminEnvironment(env));
}

export async function handleSharedAdminQueue(batch, env) {
  const queueName = typeof batch?.queue === "string" ? batch.queue : "";
  const sharedEnv = createSharedAdminEnvironment(env);
  const knownQueues = new Set([
    sharedEnv.BARQ_ADMIN_TASK_QUEUE_NAME,
    sharedEnv.BARQ_ADMIN_DEAD_LETTER_QUEUE_NAME
  ].filter(Boolean));
  if (!knownQueues.has(queueName)) return false;
  await adminWorker.queue(batch, sharedEnv);
  return true;
}
