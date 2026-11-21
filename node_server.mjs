import http from "node:http";
import { Readable } from "node:stream";
import { pathToFileURL } from "node:url";
import { createClient } from "@libsql/client";
import worker from "./src/src/index.js";
import { createLibsqlDatabaseProvider } from "./src/src/runtime_adapters.js";

const REQUIRED_ENV = ["JWT_SECRET"];

export function createNodeEnvironment(source = process.env, overrides = {}) {
  const url = source.LIBSQL_URL || source.DATABASE_URL;
  if (!overrides.DB && !url) {
    throw new Error("LIBSQL_URL (or DATABASE_URL) is required for the standalone BARQ API");
  }
  for (const name of REQUIRED_ENV) {
    if (!overrides[name] && !source[name]) throw new Error(name + " is required for the standalone BARQ API");
  }

  const client = overrides.client || (overrides.DB ? null : createClient({
    url,
    authToken: source.LIBSQL_AUTH_TOKEN || source.DATABASE_AUTH_TOKEN || undefined
  }));
  const database = overrides.DB || createLibsqlDatabaseProvider(client);
  return {
    AI: overrides.AI || null,
    DB: database,
    JWT_SECRET: overrides.JWT_SECRET || source.JWT_SECRET,
    FCM_PROJECT_ID: source.FCM_PROJECT_ID,
    FCM_SERVICE_ACCOUNT_JSON: source.FCM_SERVICE_ACCOUNT_JSON,
    OBJECT_STORAGE_ENDPOINT: source.OBJECT_STORAGE_ENDPOINT,
    OBJECT_STORAGE_BUCKET: source.OBJECT_STORAGE_BUCKET,
    OBJECT_STORAGE_REGION: source.OBJECT_STORAGE_REGION,
    OBJECT_STORAGE_ACCESS_KEY_ID: source.OBJECT_STORAGE_ACCESS_KEY_ID,
    OBJECT_STORAGE_SECRET_ACCESS_KEY: source.OBJECT_STORAGE_SECRET_ACCESS_KEY,
    TIGRIS_BUCKET: source.TIGRIS_BUCKET,
    TIGRIS_ACCESS_KEY_ID: source.TIGRIS_ACCESS_KEY_ID,
    TIGRIS_SECRET_ACCESS_KEY: source.TIGRIS_SECRET_ACCESS_KEY,
    __databaseClient: client
  };
}

function toWebRequest(incoming) {
  const host = incoming.headers.host || "127.0.0.1";
  const protocol = incoming.headers["x-forwarded-proto"] === "https" ? "https" : "http";
  const url = new URL(incoming.url || "/", protocol + "://" + host);
  const headers = new Headers();
  for (const [name, value] of Object.entries(incoming.headers)) {
    if (["connection", "transfer-encoding", "host"].includes(name) || value == null) continue;
    headers.set(name, Array.isArray(value) ? value.join(", ") : String(value));
  }
  const method = (incoming.method || "GET").toUpperCase();
  const init = { method, headers, signal: AbortSignal.timeout(120_000) };
  if (method !== "GET" && method !== "HEAD") {
    init.body = Readable.toWeb(incoming);
    init.duplex = "half";
  }
  return new Request(url, init);
}

export function createNodeApiServer({ env, fetchHandler = worker.fetch, logger = console }) {
  if (!env?.DB || typeof fetchHandler !== "function") {
    throw new TypeError("A database environment and Worker-compatible fetch handler are required");
  }
  return http.createServer(async (incoming, outgoing) => {
    try {
      const request = toWebRequest(incoming);
      const response = await fetchHandler(request, env, {
        waitUntil(promise) {
          Promise.resolve(promise).catch(error => logger.error("BARQ background task failed:", error));
        }
      });
      outgoing.writeHead(response.status, Object.fromEntries(response.headers.entries()));
      if (!response.body || request.method === "HEAD") {
        outgoing.end();
        return;
      }
      Readable.fromWeb(response.body).on("error", error => {
        logger.error("BARQ response stream failed:", error);
        outgoing.destroy(error);
      }).pipe(outgoing);
    } catch (error) {
      logger.error("BARQ standalone request failed:", error);
      if (!outgoing.headersSent) {
        outgoing.writeHead(500, { "Content-Type": "application/json; charset=utf-8" });
        outgoing.end(JSON.stringify({ error: "Internal server error" }));
      } else {
        outgoing.destroy(error);
      }
    }
  });
}

export function startScheduledMaintenance(env, intervalMs = 15 * 60 * 1000, logger = console) {
  let running = false;
  const timer = setInterval(async () => {
    if (running) return;
    running = true;
    try {
      await worker.scheduled({ cron: "standalone-interval" }, env);
    } catch (error) {
      logger.error("BARQ scheduled maintenance failed:", error);
    } finally {
      running = false;
    }
  }, intervalMs);
  timer.unref?.();
  return () => clearInterval(timer);
}

export async function startNodeApiServer(options = {}) {
  const env = options.env || createNodeEnvironment();
  if (typeof env.DB.healthCheck === "function" && !(await env.DB.healthCheck())) {
    throw new Error("Standalone BARQ database readiness check failed");
  }
  const server = createNodeApiServer({ env, logger: options.logger || console });
  const port = Number(options.port ?? process.env.PORT ?? 8787);
  const host = options.host || process.env.HOST || "0.0.0.0";
  const stopMaintenance = options.disableScheduler ? () => {} : startScheduledMaintenance(env);
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, host, resolve);
  });
  server.requestTimeout = 120_000;
  server.headersTimeout = 30_000;
  server.keepAliveTimeout = 5_000;
  const address = server.address();
  (options.logger || console).log("BARQ standalone API listening on " + host + ":" + address.port);
  let closing;
  const close = () => {
    if (closing) return closing;
    closing = new Promise(resolve => {
      stopMaintenance();
      server.close(async () => {
        try { await env.__databaseClient?.close?.(); } catch (error) {
          (options.logger || console).error("BARQ database close failed:", error);
        }
        resolve();
      });
    });
    return closing;
  };
  return { server, env, port: address.port, close };
}

const isMain = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href;
if (isMain) {
  startNodeApiServer().then(({ close }) => {
    const shutdown = () => close().finally(() => process.exit(0));
    process.once("SIGINT", shutdown);
    process.once("SIGTERM", shutdown);
  }).catch(error => {
    console.error("BARQ standalone API startup failed:", error.message);
    process.exitCode = 1;
  });
}
