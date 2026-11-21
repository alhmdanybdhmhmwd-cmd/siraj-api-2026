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
