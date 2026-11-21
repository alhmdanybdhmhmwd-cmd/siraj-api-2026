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
