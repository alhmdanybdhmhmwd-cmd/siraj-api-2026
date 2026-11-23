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

test("proxy forwards SPARK media metadata and idempotency headers", async () => {
  const originalFetch = globalThis.fetch;
  let forwarded;
  globalThis.fetch = async (url, options) => {
    forwarded = { url: String(url), headers: options.headers };
    return new Response(JSON.stringify({ status: { id: "spark-1" } }), {
      status: 201, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    await handler(makeRequest({
      url: "/api/statuses/media",
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "video/mp4",
        "x-file-name": "clip.mp4",
        "x-status-caption": "لقطة برق",
        "x-status-id": "spark-existing",
        "x-idempotency-key": "upload-once-123"
      },
      chunks: [Buffer.from([1, 2, 3])]
    }), res);
    assert.equal(res.statusCode, 201);
    assert.equal(forwarded.headers.Authorization, "Bearer test-token");
    assert.equal(forwarded.headers["X-File-Name"], "clip.mp4");
    assert.equal(forwarded.headers["X-Status-Caption"], "لقطة برق");
    assert.equal(forwarded.headers["X-Status-Id"], "spark-existing");
    assert.equal(forwarded.headers["X-Idempotency-Key"], "upload-once-123");
    assert.match(res.headers["Access-Control-Allow-Headers"], /X-Status-Caption/);
    assert.match(res.headers["Access-Control-Allow-Headers"], /X-Audio-Duration-Ms/);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("proxy forwards SPARK audio reply duration metadata", async () => {
  const originalFetch = globalThis.fetch;
  let forwarded;
  globalThis.fetch = async (url, options) => {
    forwarded = { url: String(url), headers: options.headers };
    return new Response(JSON.stringify({ ok: true }), {
      status: 201, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    await handler(makeRequest({
      url: "/api/statuses/spark-1/audio-replies",
      method: "POST",
      headers: {
        authorization: "Bearer test-token",
        "content-type": "audio/mp4",
        "x-audio-duration-ms": "4200"
      },
      chunks: [Buffer.from([4, 5, 6])]
    }), res);
    assert.equal(res.statusCode, 201);
    assert.equal(forwarded.headers["X-Audio-Duration-Ms"], "4200");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("media proxy rejects oversized declared Content-Length before reading or forwarding", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/media", method: "POST",
      headers: { "content-length": String(4 * 1024 * 1024 + 1) },
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

test("profile photo proxy rejects uploads above 4 MB before reading or forwarding", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/profile/photo/me", method: "POST",
      headers: { "content-length": String(4 * 1024 * 1024 + 1) },
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

test("media proxy rejects streamed bodies over 4 MiB when Content-Length is absent", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    const req = makeRequest({
      headers: {},
      chunks: [Buffer.alloc(4 * 1024 * 1024), Buffer.from([1])]
    });
    await handler(req, res);
    assert.equal(res.statusCode, 413);
    assert.equal(fetchCalled, false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("proxy preserves upstream security headers on API responses", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: {
      "content-type": "application/json",
      "x-content-type-options": "nosniff",
      "x-frame-options": "DENY",
      "referrer-policy": "no-referrer",
      "content-security-policy": "default-src 'none'",
      "strict-transport-security": "max-age=31536000"
    }
  });
  try {
    const res = makeResponse();
    await handler(makeRequest({ url: "/api/health", method: "GET" }), res);
    assert.equal(res.headers["x-content-type-options"], "nosniff");
    assert.equal(res.headers["x-frame-options"], "DENY");
    assert.equal(res.headers["referrer-policy"], "no-referrer");
    assert.equal(res.headers["content-security-policy"], "default-src 'none'");
    assert.equal(res.headers["strict-transport-security"], "max-age=31536000");
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

test("profile photo proxy preserves private image response headers and bytes", async () => {
  const originalFetch = globalThis.fetch;
  const image = Buffer.from([0xff, 0xd8, 0xff, 0x01, 0x02]);
  let forwarded = null;
  globalThis.fetch = async (url, options) => {
    forwarded = { url, method: options.method, headers: options.headers };
    return new Response(image, {
      status: 200,
      headers: {
        "content-type": "image/jpeg",
        "cache-control": "private, max-age=300"
      }
    });
  };
  try {
    const res = makeResponse();
    const req = makeRequest({
      url: "/api/profile/photo/user-2",
      method: "GET",
      headers: { authorization: "Bearer friend-token" }
    });
    await handler(req, res);
    assert.equal(res.statusCode, 200);
    assert.equal(forwarded.method, "GET");
    assert.equal(forwarded.headers.Authorization, "Bearer friend-token");
    assert.equal(res.headers["Content-Type"], "image/jpeg");
    assert.equal(res.headers["Cache-Control"], "private, max-age=300");
    assert.deepEqual(res.body, image);
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


test("proxy forwards authenticated POST requests for device-scoped logout", async () => {
  const originalFetch = globalThis.fetch;
  let forwarded = null;
  globalThis.fetch = async (url, options) => {
    forwarded = { url, method: options.method, headers: options.headers, body: options.body };
    return new Response(JSON.stringify({ message: "تم تسجيل الخروج من هذا الجهاز." }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    const req = makeRequest({
      url: "/api/logout",
      method: "POST",
      headers: { authorization: "Bearer device-session-token" }
    });
    await handler(req, res);
    assert.equal(res.statusCode, 200);
    assert.equal(forwarded.url, "https://siraj-api.alhmdanybdhmhmwd.workers.dev/api/logout");
    assert.equal(forwarded.method, "POST");
    assert.equal(forwarded.headers.Authorization, "Bearer device-session-token");
    assert.equal(Buffer.isBuffer(forwarded.body), true);
    assert.equal(forwarded.body.length, 0);
    assert.deepEqual(JSON.parse(res.body.toString()), { message: "تم تسجيل الخروج من هذا الجهاز." });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("proxy preserves upstream request IDs and retry diagnostics", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => new Response(JSON.stringify({ status: "alive", service: "barq-api" }), {
      status: 200,
      headers: {
        "content-type": "application/json",
        "x-request-id": "barq-probe-01",
        "retry-after": "3",
        "server-timing": "origin;dur=12",
        "vary": "Accept-Encoding"
      }
    });
    const res = makeResponse();
    await handler(makeRequest({ url: "/health/live", method: "GET", chunks: [] }), res);
    assert.equal(res.statusCode, 200);
    assert.equal(res.headers["x-request-id"], "barq-probe-01");
    assert.equal(res.headers["retry-after"], "3");
    assert.equal(res.headers["server-timing"], "origin;dur=12");
    assert.equal(res.headers.vary, "Accept-Encoding");
    assert.deepEqual(JSON.parse(res.body.toString()), { status: "alive", service: "barq-api" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("proxy reports BARQ identity when upstream connection fails", async () => {
  const originalFetch = globalThis.fetch;
  try {
    globalThis.fetch = async () => { throw new Error("simulated upstream failure"); };
    const res = makeResponse();
    await handler(makeRequest({ url: "/health/live", method: "GET", chunks: [] }), res);
    assert.equal(res.statusCode, 502);
    assert.deepEqual(res.body, { error: "تعذر الاتصال بخادم برق" });
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("proxy CORS permits edits, resumable media, and byte-range downloads", async () => {
  const res = makeResponse();
  await handler(makeRequest({ url: "/api/media/file-1", method: "OPTIONS" }), res);
  assert.equal(res.statusCode, 204);
  assert.match(res.headers["Access-Control-Allow-Methods"], /PATCH/);
  assert.match(res.headers["Access-Control-Allow-Methods"], /PUT/);
  assert.match(res.headers["Access-Control-Allow-Headers"], /Range/);
  assert.match(res.headers["Access-Control-Allow-Headers"], /X-Idempotency-Key/);
  assert.match(res.headers["Access-Control-Expose-Headers"], /Content-Range/);
  assert.match(res.headers["Access-Control-Expose-Headers"], /Accept-Ranges/);
});

test("production API gateway retries an opt-in HTTPS fallback after upstream 503", async () => {
  const originalFetch = globalThis.fetch;
  const previousFallback = process.env.BARQ_API_FALLBACK_UPSTREAM;
  const previousEnvironment = process.env.VERCEL_ENV;
  const calls = [];
  process.env.BARQ_API_FALLBACK_UPSTREAM = "https://barq-fallback.example";
  delete process.env.VERCEL_ENV;
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    if (calls.length === 1) return new Response("temporarily unavailable", { status: 503 });
    return new Response(JSON.stringify({ status: "alive", service: "barq-api" }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    await handler(makeRequest({ url: "/health/live", method: "GET", chunks: [] }), res);
    assert.deepEqual(calls, [
      "https://siraj-api.alhmdanybdhmhmwd.workers.dev/health/live",
      "https://barq-fallback.example/health/live"
    ]);
    assert.equal(res.statusCode, 200);
  } finally {
    globalThis.fetch = originalFetch;
    if (previousFallback === undefined) delete process.env.BARQ_API_FALLBACK_UPSTREAM;
    else process.env.BARQ_API_FALLBACK_UPSTREAM = previousFallback;
    if (previousEnvironment === undefined) delete process.env.VERCEL_ENV;
    else process.env.VERCEL_ENV = previousEnvironment;
  }
});

test("Preview gateway remains pinned to its isolated upstream and ignores fallback configuration", () => {
  const candidates = handler.getUpstreamCandidates({
    VERCEL_ENV: "preview",
    BARQ_API_UPSTREAM: "https://production-override.example",
    BARQ_API_FALLBACK_UPSTREAM: "https://production-fallback.example"
  });
  assert.deepEqual(candidates, [
    "https://barq-api-phase2-fallback-test.alhmdanybdhmhmwd.workers.dev"
  ]);
});

test("gateway ignores non-HTTPS and malformed fallback upstreams", () => {
  assert.deepEqual(handler.getUpstreamCandidates({
    BARQ_API_FALLBACK_UPSTREAM: "http://insecure.example"
  }), ["https://siraj-api.alhmdanybdhmhmwd.workers.dev"]);
  assert.deepEqual(handler.getUpstreamCandidates({
    BARQ_API_FALLBACK_UPSTREAM: "not a URL"
  }), ["https://siraj-api.alhmdanybdhmhmwd.workers.dev"]);
});

test("gateway does not replay non-idempotent POST requests to fallback", async () => {
  const originalFetch = globalThis.fetch;
  const previousFallback = process.env.BARQ_API_FALLBACK_UPSTREAM;
  const previousEnvironment = process.env.VERCEL_ENV;
  let calls = 0;
  process.env.BARQ_API_FALLBACK_UPSTREAM = "https://barq-fallback.example";
  delete process.env.VERCEL_ENV;
  globalThis.fetch = async () => {
    calls += 1;
    return new Response("temporarily unavailable", { status: 503 });
  };
  try {
    const res = makeResponse();
    await handler(makeRequest({
      url: "/api/messages",
      method: "POST",
      headers: { "content-type": "application/json" },
      chunks: [Buffer.from(JSON.stringify({ text: "one message" }))]
    }), res);
    assert.equal(calls, 1);
    assert.equal(res.statusCode, 503);
  } finally {
    globalThis.fetch = originalFetch;
    if (previousFallback === undefined) delete process.env.BARQ_API_FALLBACK_UPSTREAM;
    else process.env.BARQ_API_FALLBACK_UPSTREAM = previousFallback;
    if (previousEnvironment === undefined) delete process.env.VERCEL_ENV;
    else process.env.VERCEL_ENV = previousEnvironment;
  }
});

test("gateway retries a network failure on GET through the configured fallback", async () => {
  const originalFetch = globalThis.fetch;
  const previousFallback = process.env.BARQ_API_FALLBACK_UPSTREAM;
  const previousEnvironment = process.env.VERCEL_ENV;
  const calls = [];
  process.env.BARQ_API_FALLBACK_UPSTREAM = "https://barq-fallback.example";
  delete process.env.VERCEL_ENV;
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    if (calls.length === 1) throw new Error("simulated DNS failure");
    return new Response(JSON.stringify({ status: "alive", service: "barq-api" }), {
      status: 200, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    await handler(makeRequest({ url: "/health/live", method: "GET", chunks: [] }), res);
    assert.equal(calls.length, 2);
    assert.match(calls[1], /^https:\/\/barq-fallback\.example\//);
    assert.equal(res.statusCode, 200);
  } finally {
    globalThis.fetch = originalFetch;
    if (previousFallback === undefined) delete process.env.BARQ_API_FALLBACK_UPSTREAM;
    else process.env.BARQ_API_FALLBACK_UPSTREAM = previousFallback;
    if (previousEnvironment === undefined) delete process.env.VERCEL_ENV;
    else process.env.VERCEL_ENV = previousEnvironment;
  }
});

test("gateway retries a POST only when an idempotency key is supplied", async () => {
  const originalFetch = globalThis.fetch;
  const previousFallback = process.env.BARQ_API_FALLBACK_UPSTREAM;
  const previousEnvironment = process.env.VERCEL_ENV;
  const calls = [];
  process.env.BARQ_API_FALLBACK_UPSTREAM = "https://barq-fallback.example";
  delete process.env.VERCEL_ENV;
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return new Response(calls.length === 1 ? "temporarily unavailable" : JSON.stringify({ ok: true }), {
      status: calls.length === 1 ? 503 : 201,
      headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    await handler(makeRequest({
      url: "/api/media/uploads/session-1/complete",
      method: "POST",
      headers: { "x-idempotency-key": "complete-once-1" },
      chunks: [Buffer.from("{}")]
    }), res);
    assert.equal(calls.length, 2);
    assert.equal(res.statusCode, 201);
  } finally {
    globalThis.fetch = originalFetch;
    if (previousFallback === undefined) delete process.env.BARQ_API_FALLBACK_UPSTREAM;
    else process.env.BARQ_API_FALLBACK_UPSTREAM = previousFallback;
    if (previousEnvironment === undefined) delete process.env.VERCEL_ENV;
    else process.env.VERCEL_ENV = previousEnvironment;
  }
});

test("Vercel proxy forwards authenticated private-memory photo uploads", async () => {
  const originalFetch = globalThis.fetch;
  let forwarded = null;
  const bytes = Buffer.from([0xff, 0xd8, 0xff, 0x01]);
  globalThis.fetch = async (url, options) => {
    forwarded = { url: String(url), headers: options.headers, body: Buffer.from(options.body) };
    return new Response(JSON.stringify({ photo: { id: "photo-1" } }), {
      status: 201, headers: { "content-type": "application/json" }
    });
  };
  try {
    const res = makeResponse();
    await handler(makeRequest({
      url: "/api/private-memories/memory-1/media",
      method: "POST",
      headers: {
        authorization: "Bearer memory-token",
        "content-type": "image/jpeg",
        "x-file-name": "memory.jpg",
        "content-length": String(bytes.length)
      },
      chunks: [bytes]
    }), res);
    assert.equal(res.statusCode, 201);
    assert.match(forwarded.url, /\/api\/private-memories\/memory-1\/media$/);
    assert.equal(forwarded.headers.Authorization, "Bearer memory-token");
    assert.equal(forwarded.headers["X-File-Name"], "memory.jpg");
    assert.deepEqual(forwarded.body, bytes);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("SPARK media proxy rejects payloads above the Vercel-safe 4 MiB limit", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/statuses/media", method: "POST",
      headers: { "content-length": String(4 * 1024 * 1024 + 1) },
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

test("private-memory photo proxy rejects oversized uploads before reading", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/private-memories/memory-1/media", method: "POST",
      headers: { "content-length": String(4 * 1024 * 1024 + 1) },
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

test("SPARK audio reply proxy rejects payloads above the Vercel-safe 4 MiB limit", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/statuses/spark-1/audio-replies", method: "POST",
      headers: { "content-length": String(4 * 1024 * 1024 + 1) },
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

test("transcription proxy rejects payloads above the Worker 2 MiB limit before reading", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/transcribe", method: "POST",
      headers: { "content-length": String(2 * 1024 * 1024 + 1) },
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

test("generic API proxy bodies are capped at 256 KiB before reading", async () => {
  const originalFetch = globalThis.fetch;
  let fetchCalled = false;
  globalThis.fetch = async () => { fetchCalled = true; throw new Error("unexpected upstream request"); };
  try {
    const res = makeResponse();
    let streamRead = false;
    const req = {
      url: "/api/messages", method: "POST",
      headers: { "content-length": String(256 * 1024 + 1) },
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
