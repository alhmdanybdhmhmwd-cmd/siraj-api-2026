import test from "node:test";
import { Writable } from "node:stream";
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
process.env.BARQ_API_UPSTREAM = "https://siraj-api.alhmdanybdhmhmwd.workers.dev";
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
    assert.equal(calledUrl, "https://barq-api-phase2-fallback-test.alhmdanybdhmhmwd.workers.dev/health/live?probe=1");
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
    assert.equal(captured.url, "https://barq-api-phase2-fallback-test.alhmdanybdhmhmwd.workers.dev/api/media?target=preview");
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
    assert.deepEqual(res.body, { error: "تعذر الاتصال بخادم برق" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
test("preview proxy preserves byte-range download headers and partial response metadata", async () => {
  const originalFetch = globalThis.fetch;
  let captured;
  try {
    globalThis.fetch = async (url, options) => {
      captured = { url: String(url), headers: options.headers };
      return new Response(new Uint8Array([7, 8, 9]), {
        status: 206,
        headers: {
          "content-type": "application/octet-stream",
          "content-range": "bytes 7-9/10",
          "accept-ranges": "bytes",
          "etag": '"sample-v1"',
          "last-modified": "Wed, 21 Oct 2015 07:28:00 GMT"
        }
      });
    };
    const res = makeResponse();
    await handler(makeRequest({
      method: "GET",
      url: "/api/media/file-1",
      headers: { range: "bytes=7-9", "if-range": '"sample-v1"' }
    }), res);
    assert.equal(captured.url, "https://barq-api-phase2-fallback-test.alhmdanybdhmhmwd.workers.dev/api/media/file-1");
    assert.equal(captured.headers.Range, "bytes=7-9");
    assert.equal(captured.headers["If-Range"], '"sample-v1"');
    assert.equal(res.statusCode, 206);
    assert.equal(res.headers["content-range"], "bytes 7-9/10");
    assert.equal(res.headers["accept-ranges"], "bytes");
    assert.equal(res.headers.etag, '"sample-v1"');
    assert.equal(res.headers["last-modified"], "Wed, 21 Oct 2015 07:28:00 GMT");
    assert.deepEqual([...res.body], [7, 8, 9]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
test("preview proxy streams partial media without buffering the full response", async () => {
  const originalFetch = globalThis.fetch;
  const received = [];
  try {
    globalThis.fetch = async () => {
      const response = new Response(new ReadableStream({
        start(controller) {
          controller.enqueue(new Uint8Array([1, 2]));
          controller.enqueue(new Uint8Array([3, 4]));
          controller.close();
        }
      }), {
        status: 206,
        headers: {
          "content-type": "application/octet-stream",
          "content-length": "4",
          "content-range": "bytes 0-3/8"
        }
      });
      response.arrayBuffer = async () => { throw new Error("streaming must not buffer"); };
      return response;
    };
    const res = new Writable({
      write(chunk, encoding, callback) { received.push(Buffer.from(chunk)); callback(); }
    });
    res.statusCode = 200;
    res.headers = {};
    res.setHeader = (name, value) => { res.headers[name.toLowerCase()] = value; };
    res.status = (code) => { res.statusCode = code; return res; };
    await handler(makeRequest({
      method: "GET",
      url: "/api/media/file-2",
      headers: { range: "bytes=0-3" }
    }), res);
    assert.equal(res.statusCode, 206);
    assert.equal(res.headers["content-length"], "4");
    assert.equal(res.headers["content-range"], "bytes 0-3/8");
    assert.deepEqual([...Buffer.concat(received)], [1, 2, 3, 4]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});


test("preview proxy ignores a production upstream override", async () => {
  const originalFetch = globalThis.fetch;
  let calledUrl;
  try {
    globalThis.fetch = async (url) => { calledUrl = String(url); return new Response("ok"); };
    await handler(makeRequest({ url: "/health/live" }), makeResponse());
    assert.equal(calledUrl, "https://barq-api-phase2-fallback-test.alhmdanybdhmhmwd.workers.dev/health/live");
  } finally { globalThis.fetch = originalFetch; }
});


test("preview proxy may use only the named isolated fallback Worker", async () => {
  const originalFetch = globalThis.fetch;
  const previous = process.env.BARQ_API_UPSTREAM;
  let calledUrl;
  try {
    process.env.BARQ_API_UPSTREAM = "https://barq-api-phase2-fallback-test.example.workers.dev";
    globalThis.fetch = async (url) => {
      calledUrl = String(url);
      return new Response("ok");
    };
    await handler(makeRequest({ url: "/health/live" }), makeResponse());
    assert.equal(calledUrl, "https://barq-api-phase2-fallback-test.example.workers.dev/health/live");
  } finally {
    globalThis.fetch = originalFetch;
    if (previous === undefined) delete process.env.BARQ_API_UPSTREAM;
    else process.env.BARQ_API_UPSTREAM = previous;
  }
});
