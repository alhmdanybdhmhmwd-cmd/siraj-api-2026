import test from "node:test";
import assert from "node:assert/strict";
import handler from "../api/[...path].js";

function makeResponse() {
  return {
    statusCode: 200,
    headers: {},
    body: undefined,
    setHeader(name, value) { this.headers[name] = value; },
    status(code) { this.statusCode = code; return this; },
    json(value) { this.body = value; return this; },
    send(value) { this.body = value; return this; },
    end() { return this; }
  };
}

function makeRequest({ url = "/api/media", method = "POST", headers = {}, chunks = [] } = {}) {
  return {
    url, method, headers,
    async *[Symbol.asyncIterator]() {
      for (const chunk of chunks) yield chunk;
    }
  };
}

test("media proxy rejects oversized declared Content-Length before reading or forwarding", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/media", method: "POST",
      headers: { "content-length": String(20 * 1024 * 1024 + 1) },
      async *[Symbol.asyncIterator]() { streamRead = true; }
    };
    await handler(req, res);
    assert.equal(res.statusCode, 413);
    assert.equal(streamRead, false);
    assert.equal(fetchCalled, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("media proxy rejects streamed bodies over 20 MB when Content-Length is absent", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    const req = makeRequest({
      headers: {},
      chunks: [Buffer.alloc(20 * 1024 * 1024), Buffer.from([1])]
    });
    await handler(req, res);
    assert.equal(res.statusCode, 413);
    assert.equal(fetchCalled, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
