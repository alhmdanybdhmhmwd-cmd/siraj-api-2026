/**
 * Provider-neutral AI capability contract.
 *
 * Worker bindings and independent runtime providers can implement the same
 * { run(model, input) } contract. Keep provider-specific SDKs outside domain
 * handlers so the API can be hosted beyond Cloudflare without changing routes.
 */
export function createAiProvider(binding) {
  const run = binding && typeof binding.run === "function"
    ? binding.run.bind(binding)
    : null;

  return Object.freeze({
    isAvailable() {
      return Boolean(run);
    },
    async run(model, input) {
      if (!run) throw new Error("AI provider is not configured");
      return run(model, input);
    }
  });
}

/**
 * SQL database capability contract. The adapter deliberately exposes only
 * the operations used by BARQ's repositories; alternate runtimes can provide
 * these operations without exposing a Cloudflare env binding to route code.
 */
export function createDatabaseProvider(binding) {
  if (!binding || typeof binding.prepare !== "function") return null;
  const provider = {
    prepare(sql) {
      if (typeof sql !== "string" || !sql.trim()) throw new TypeError("SQL statement is required");
      return binding.prepare(sql);
    },
    async batch(statements) {
      if (typeof binding.batch !== "function") throw new Error("Database batch is not supported");
      return binding.batch(statements);
    },
    async exec(sql) {
      if (typeof binding.exec !== "function") throw new Error("Database exec is not supported");
      return binding.exec(sql);
    },
    async healthCheck() {
      const statement = binding.prepare("SELECT 1 AS barq_ready");
      if (!statement || typeof statement.first !== "function") throw new Error("Database health probe is not supported");
      const row = await statement.first();
      return Number(row?.barq_ready) === 1;
    }
  };
  return Object.freeze(provider);
}

/**
 * libSQL adapter for independent Node runtimes.
 *
 * The application continues to consume the small D1-shaped SQL contract.
 * A Node host can create a client with @libsql/client and inject it here;
 * no Cloudflare binding or SDK import is required by Worker code.
 */
const LIBSQL_STATEMENT = Symbol("barq.libsql.statement");

function toD1CompatibleMeta(result) {
  return {
    ...result,
    changes: Number(result?.rowsAffected ?? result?.changes ?? 0),
    last_row_id: result?.lastInsertRowid ?? result?.last_row_id ?? null
  };
}

export function createLibsqlDatabaseProvider(client) {
  if (!client || typeof client.execute !== "function" || typeof client.batch !== "function") {
    throw new TypeError("A libSQL-compatible client with execute and batch is required");
  }

  const makeStatement = (sql, args = []) => {
    if (typeof sql !== "string" || !sql.trim()) throw new TypeError("SQL statement is required");
    const statement = {
      [LIBSQL_STATEMENT]: true,
      sql,
      args,
      bind(...nextArgs) {
        return makeStatement(sql, nextArgs);
      },
      async first() {
        const result = await client.execute({ sql, args });
        return result.rows?.[0] ?? null;
      },
      async all() {
        const result = await client.execute({ sql, args });
        return {
          results: result.rows ?? [],
          success: true,
          meta: toD1CompatibleMeta(result)
        };
      },
      async run() {
        const result = await client.execute({ sql, args });
        return { success: true, meta: toD1CompatibleMeta(result) };
      }
    };
    return Object.freeze(statement);
  };

  return Object.freeze({
    prepare(sql) {
      return makeStatement(sql);
    },
    async batch(statements) {
      if (!Array.isArray(statements) || statements.some(item => !item?.[LIBSQL_STATEMENT])) {
        throw new TypeError("libSQL batch accepts only statements prepared by this provider");
      }
      const results = await client.batch(
        statements.map(item => ({ sql: item.sql, args: item.args })),
        "write"
      );
      return results.map(result => ({ success: true, meta: toD1CompatibleMeta(result) }));
    },
    async exec(sql) {
      if (typeof sql !== "string" || !sql.trim()) throw new TypeError("SQL statement is required");
      if (typeof client.executeMultiple !== "function") {
        throw new Error("libSQL executeMultiple is required for multi-statement SQL scripts");
      }
      return client.executeMultiple(sql);
    },
    async healthCheck() {
      const result = await client.execute("SELECT 1 AS barq_ready");
      const row = result.rows?.[0];
      return Number(row?.barq_ready) === 1;
    }
  });
}

/**
 * Build a provider-neutral S3 object URL. The default preserves the existing
 * Tigris virtual-host URL; OBJECT_STORAGE_ENDPOINT can select another S3
 * endpoint, using {bucket} substitution or path-style bucket addressing.
 */
export function createObjectStorageUrl(env, objectKey, query = {}) {
  if (typeof objectKey !== "string" || !objectKey || objectKey.startsWith("/") ||
      objectKey.includes("\\\\") || objectKey.split("/").some(part => !part || part === "." || part === "..")) {
    throw new TypeError("A safe relative object key is required");
  }
  const bucket = String(env?.OBJECT_STORAGE_BUCKET || env?.TIGRIS_BUCKET || "siraj-media");
  const encodedKey = objectKey.split("/").map(encodeURIComponent).join("/");
  const configuredEndpoint = String(env?.OBJECT_STORAGE_ENDPOINT || "").trim();
  let base;
  if (!configuredEndpoint) {
    base = `https://${encodeURIComponent(bucket)}.t3.storage.dev`;
  } else if (configuredEndpoint.includes("{bucket}")) {
    base = configuredEndpoint.replaceAll("{bucket}", encodeURIComponent(bucket));
  } else {
    base = configuredEndpoint.replace(/\/+$/, "") + "/" + encodeURIComponent(bucket);
  }
  const url = new URL(base);
  url.pathname = url.pathname.replace(/\/+$/, "") + "/" + encodedKey;
  for (const [name, value] of Object.entries(query || {})) {
    if (value !== undefined && value !== null) url.searchParams.set(name, String(value));
  }
  return url.toString();
}

/**
 * S3-compatible object storage client factory. The runtime supplies its
 * transport client, allowing another runtime to inject a compatible client.
 */
export function createObjectStorageClient(env, Client) {
  if (typeof Client !== "function") throw new TypeError("Storage client implementation is required");
  const accessKeyId = env?.OBJECT_STORAGE_ACCESS_KEY_ID || env?.TIGRIS_ACCESS_KEY_ID;
  const secretAccessKey = env?.OBJECT_STORAGE_SECRET_ACCESS_KEY || env?.TIGRIS_SECRET_ACCESS_KEY;
  if (!accessKeyId || !secretAccessKey) {
    throw new Error("Object storage credentials are not configured");
  }
  return new Client({
    accessKeyId,
    secretAccessKey,
    service: "s3",
    region: env.OBJECT_STORAGE_REGION || "auto",
    retries: 2
  });
}


/**
 * Push transport contract. Authentication and message policy stay in the
 * domain layer; runtimes provide only an HTTP-compatible transport.
 */
export function createPushProvider(fetchImpl = globalThis.fetch) {
  if (typeof fetchImpl !== "function") throw new TypeError("Push transport must be a fetch-compatible function");
  return Object.freeze({
    request(url, init) {
      return fetchImpl(url, init);
    }
  });
}

/**
 * Durable-work boundary for request-scoped background tasks. A runtime
 * without waitUntil support returns false so callers can choose a safe
 * synchronous or persistent-queue fallback instead of silently dropping work.
 */
export function createBackgroundTaskScheduler(context) {
  return Object.freeze({
    schedule(task) {
      if (typeof task !== "function") throw new TypeError("Background task must be a function");
      if (!context || typeof context.waitUntil !== "function") return false;
      context.waitUntil(Promise.resolve().then(task));
      return true;
    }
  });
}
