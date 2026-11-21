import test from "node:test";
import assert from "node:assert/strict";
import { createAiProvider } from "./runtime_adapters.js";

test("AI adapter reports unavailable when no provider is configured", async () => {
  const provider = createAiProvider(null);
  assert.equal(provider.isAvailable(), false);
  await assert.rejects(provider.run("model", {}), /not configured/);
});

test("AI adapter preserves provider model, input, and result", async () => {
  const expected = { text: "hello" };
  const calls = [];
  const provider = createAiProvider({
    async run(model, input) {
      calls.push({ model, input });
      return expected;
    }
  });
  const input = { messages: [{ role: "user", content: "hello" }] };
  assert.equal(provider.isAvailable(), true);
  assert.equal(await provider.run("summary-model", input), expected);
  assert.deepEqual(calls, [{ model: "summary-model", input }]);
});

test("AI adapter binds provider method receiver", async () => {
  const binding = {
    marker: "bound",
    async run() { return this.marker; }
  };
  assert.equal(await createAiProvider(binding).run("model", {}), "bound");
});

test("object storage adapter supplies S3-compatible credentials and retry policy", () => {
  let received;
  class FakeClient {
    constructor(options) { received = options; }
  }
  const env = {
    TIGRIS_ACCESS_KEY_ID: "preview-access",
    TIGRIS_SECRET_ACCESS_KEY: "preview-secret"
  };
  const client = createObjectStorageClient(env, FakeClient);
  assert.ok(client instanceof FakeClient);
  assert.deepEqual(received, {
    accessKeyId: "preview-access",
    secretAccessKey: "preview-secret",
    service: "s3",
    region: "auto",
    retries: 2
  });
});
