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
