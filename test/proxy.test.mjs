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
      headers: { "content-length": String(60 * 1024 * 1024 + 1) },
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

test("profile photo proxy rejects uploads above 5 MB before reading or forwarding", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/profile/photo/me", method: "POST",
      headers: { "content-length": String(5 * 1024 * 1024 + 1) },
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

test("profile photo proxy forwards authenticated binary image uploads", async () => {
  const originalFetch = globalThis.fetch;
  let forwarded = null;
  const bytes = Buffer.from([0xff, 0xd8, 0xff, 0x00]);
  globalThis.fetch = async (url, options) => {
    forwarded = { url, method: options.method, headers: options.headers, body: Buffer.from(options.body) };
    return new Response(JSON.stringify({ photoUrl: "/api/profile/photo/user-1" }), {
      status: 201, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    const req = makeRequest({
      url: "/api/profile/photo/me",
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "image/jpeg",
        "content-length": String(bytes.length)
      },
      chunks: [bytes]
    });
    await handler(req, res);
    assert.equal(res.statusCode, 201);
    assert.equal(forwarded.url, "https://siraj-api.alhmdanybdhmhmwd.workers.dev/api/profile/photo/me");
    assert.equal(forwarded.method, "POST");
    assert.equal(forwarded.headers.Authorization, "Bearer test-token");
    assert.equal(forwarded.headers["Content-Type"], "image/jpeg");
    assert.deepEqual(forwarded.body, bytes);
    assert.deepEqual(JSON.parse(res.body.toString()), { photoUrl: "/api/profile/photo/user-1" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("media proxy rejects streamed bodies over 60 MB when Content-Length is absent", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    const req = makeRequest({
      headers: {},
      chunks: [Buffer.alloc(60 * 1024 * 1024), Buffer.from([1])]
    });
    await handler(req, res);
    assert.equal(res.statusCode, 413);
    assert.equal(fetchCalled, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("proxy forwards authenticated DELETE requests for device token revocation", async () => {
  const originalFetch = globalThis.fetch;
  let forwarded = null;
  globalThis.fetch = async (url, options) => {
    forwarded = { url, method: options.method, headers: options.headers, body: options.body };
    return new Response(JSON.stringify({ message: "Device token unregistered", removed: 1 }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    const req = makeRequest({
      url: "/api/devices/token",
      method: "DELETE",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "application/json"
      },
      chunks: [Buffer.from(JSON.stringify({ fcmToken: "device-token" }))]
    });
    await handler(req, res);
    assert.equal(res.statusCode, 200);
    assert.equal(forwarded.method, "DELETE");
    assert.equal(forwarded.headers.Authorization, "Bearer test-token");
    assert.equal(forwarded.body.toString(), JSON.stringify({ fcmToken: "device-token" }));
    assert.match(res.headers["Access-Control-Allow-Methods"], /DELETE/);
    assert.deepEqual(JSON.parse(res.body.toString()), {
      message: "Device token unregistered", removed: 1
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("proxy forwards explicitly requested binary audio to the transcription Worker route", async () => {
  const originalFetch = globalThis.fetch;
  let forwarded = null;
  const audio = Buffer.from([1, 2, 3, 4, 5]);
  globalThis.fetch = async (url, options) => {
    forwarded = { url, method: options.method, headers: options.headers, body: Buffer.from(options.body) };
    return new Response(JSON.stringify({ text: "مرحبا" }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    const req = makeRequest({
      url: "/api/transcribe",
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "audio/wav",
        "content-length": String(audio.length)
      },
      chunks: [audio]
    });
    await handler(req, res);
    assert.equal(res.statusCode, 200);
    assert.equal(forwarded.url, "https://siraj-api.alhmdanybdhmhmwd.workers.dev/api/transcribe");
    assert.equal(forwarded.method, "POST");
    assert.equal(forwarded.headers.Authorization, "Bearer test-token");
    assert.equal(forwarded.headers["Content-Type"], "audio/wav");
    assert.deepEqual(forwarded.body, audio);
    assert.deepEqual(JSON.parse(res.body.toString()), { text: "مرحبا" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});
