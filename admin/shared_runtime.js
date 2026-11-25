import adminWorker from "./worker.js";

const ADMIN_PREFIX = "/admin";

export function createSharedAdminEnvironment(env) {
  return {
    ...env,
    // BARQ Admin intentionally shares the existing BARQ D1 and AI bindings.
    // Never fall back to a second Admin database in this integration path.
    ADMIN_DB: env?.DB ?? null,
    ADMIN_AI: env?.AI ?? null,
    ADMIN_TASK_QUEUE: env?.ADMIN_TASK_QUEUE ?? null
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
