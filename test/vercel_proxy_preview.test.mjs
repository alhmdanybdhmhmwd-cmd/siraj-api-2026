import test from "node:test";
import assert from "node:assert/strict";
import { readFile, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";

const source = await readFile(new URL("../api/[...path].js", import.meta.url), "utf8");
const modulePath = `/tmp/barq-vercel-proxy-${process.pid}.cjs`;
await writeFile(modulePath, source, "utf8");

const previousEnv = {
  VERCEL_ENV: process.env.VERCEL_ENV,
  BARQ_API_UPSTREAM: process.env.BARQ_API_UPSTREAM
};
process.env.VERCEL_ENV = "preview";
process.env.BARQ_API_UPSTREAM = "https://preview-worker.example.workers.dev";
const proxyModule = await import(pathToFileURL(modulePath).href);
const handler = proxyModule.default || proxyModule;
process.env.VERCEL_ENV = previousEnv.VERCEL_ENV;
process.env.BARQ_API_UPSTREAM = previousEnv.BARQ_API_UPSTREAM;

function makeResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) { this.headers[name.toLowerCase()] = value; },
    status(code) { this.statusCode = code; return this; },
    json(value) { this.body = value; return this; },
    send(value) { this.body = value; return this; },
    end() { this.ended = true; return this; }
  };
}

function makeRequest({ method = "GET", url = "/health/live", headers = {}, chunks = [] } = {}) {
  return {
    method, url, headers,
    async *[Symbol.asyncIterator]() {
      for (const chunk of chunks) yield Buffer.from(chunk);
    }
  };
}

test("preview proxy selects the isolated Preview upstream", async () => {
  const originalFetch = globalThis.fetch;
  let calledUrl;
  try {
    globalThis.fetch = async (url) => {
      calledUrl = String(url);
      return new Response(JSON.stringify({ status: "alive" }), {
        status: 200, headers: { "content-type": "application/json" }
      });
    };
    const res = makeResponse();
    await handler(makeRequest({ url: "/health/live?probe=1" }), res);
    assert.equal(calledUrl, "https://preview-worker.example.workers.dev/health/live?probe=1");
    assert.equal(res.statusCode, 200);
    assert.deepEqual(JSON.parse(res.body.toString()), { status: "alive" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("preview proxy forwards only supported request headers and body", async () => {
  const originalFetch = globalThis.fetch;
  let captured;
  try {
    globalThis.fetch = async (url, options) => {
      captured = { url: String(url), options };
      return new Response("accepted", { status: 202, headers: { "content-type": "text/plain" } });
    };
    const res = makeResponse();
    await handler(makeRequest({
      method: "POST",
      url: "/api/media?target=preview",
      headers: {
        "content-type": "application/octet-stream",
        authorization: "Bearer preview-token",
        "x-file-name": "sample.bin",
        cookie: "must-not-forward"
      },
      chunks: [Buffer.from([1, 2]), Buffer.from([3, 4])]
    }), res);
    assert.equal(captured.url, "https://preview-worker.example.workers.dev/api/media?target=preview");
    assert.equal(captured.options.method, "POST");
    assert.equal(captured.options.headers.Authorization, "Bearer preview-token");
    assert.equal(captured.options.headers["X-File-Name"], "sample.bin");
    assert.equal(captured.options.headers.cookie, undefined);
    assert.deepEqual([...captured.options.body], [1, 2, 3, 4]);
    assert.equal(res.statusCode, 202);
    assert.equal(res.body.toString(), "accepted");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("preview proxy handles CORS preflight without contacting the upstream", async () => {
  const originalFetch = globalThis.fetch;
  let called = false;
  try {
    globalThis.fetch = async () => { called = true; throw new Error("must not fetch"); };
    const res = makeResponse();
    await handler(makeRequest({ method: "OPTIONS", url: "/api/media" }), res);
    assert.equal(res.statusCode, 204);
    assert.equal(res.ended, true);
    assert.equal(called, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("preview proxy returns a bounded gateway error when upstream fetch fails", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => { throw new Error("simulated upstream failure"); };
    const res = makeResponse();
    await handler(makeRequest({ url: "/health/ready" }), res);
    assert.equal(res.statusCode, 502);
    assert.deepEqual(res.body, { error: "تعذر الاتصال بخادم سراج" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
