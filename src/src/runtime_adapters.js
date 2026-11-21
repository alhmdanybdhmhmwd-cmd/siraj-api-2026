/**
 * Provider-neutral AI capability contract.
 *
 * Worker bindings and independent runtime providers can implement the same
 * { run(model, input) } contract. Keep provider-specific SDKs outside domain
 * handlers so the API can be hosted beyond Cloudflare without changing routes.
 */
import { AwsClient } from "aws4fetch";

/**
 * S3-compatible object storage client contract. Provider credentials stay in
 * the runtime adapter; domain routes only receive a fetch-capable client.
 */
export function createObjectStorageClient(env, Client = AwsClient) {
  return new Client({
    accessKeyId: env.TIGRIS_ACCESS_KEY_ID,
    secretAccessKey: env.TIGRIS_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
    retries: 2
  });
}

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
