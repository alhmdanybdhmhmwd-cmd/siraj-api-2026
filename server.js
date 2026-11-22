const http = require("node:http");
const { Readable } = require("node:stream");
const { pipeline } = require("node:stream/promises");

const UPSTREAM = (process.env.BARQ_API_UPSTREAM || "https://siraj-api.alhmdanybdhmhmwd.workers.dev").replace(/\/+$/, "");
const parsedUpstream = new URL(UPSTREAM);
if (parsedUpstream.protocol !== "https:" || parsedUpstream.origin !== UPSTREAM) {
  throw new Error("BARQ_API_UPSTREAM must be a clean HTTPS origin");
}

const server = http.createServer(async (req, res) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, Range, If-Range, X-File-Name, X-Recipient-Id, X-Group-Id, X-Status-Caption, X-Status-Id, X-Audio-Duration-Ms, X-Idempotency-Key",
    "Access-Control-Expose-Headers": "Accept-Ranges, Content-Range, Content-Disposition, ETag, X-Request-Id",
  };

  if (req.method === "OPTIONS") {
    res.writeHead(204, cors);
    return res.end();
  }

  try {
    const headers = {
      "Content-Type": req.headers["content-type"] || "application/json",
      ...(req.headers.authorization ? { Authorization: req.headers.authorization } : {}),
      ...(req.headers.range ? { Range: req.headers.range } : {}),
      ...(req.headers["if-range"] ? { "If-Range": req.headers["if-range"] } : {}),
      ...(req.headers["x-file-name"] ? { "X-File-Name": req.headers["x-file-name"] } : {}),
      ...(req.headers["x-recipient-id"] ? { "X-Recipient-Id": req.headers["x-recipient-id"] } : {}),
      ...(req.headers["x-group-id"] ? { "X-Group-Id": req.headers["x-group-id"] } : {}),
      ...(req.headers["x-status-caption"] ? { "X-Status-Caption": req.headers["x-status-caption"] } : {}),
      ...(req.headers["x-status-id"] ? { "X-Status-Id": req.headers["x-status-id"] } : {}),
      ...(req.headers["x-audio-duration-ms"] ? { "X-Audio-Duration-Ms": req.headers["x-audio-duration-ms"] } : {}),
      ...(req.headers["x-idempotency-key"] ? { "X-Idempotency-Key": req.headers["x-idempotency-key"] } : {}),
    };
    const hasBody = !["GET", "HEAD"].includes(req.method);
    const response = await fetch(UPSTREAM + req.url, {
      method: req.method,
      headers,
      ...(hasBody ? { body: Readable.toWeb(req), duplex: "half" } : {}),
      signal: AbortSignal.timeout(120_000),
    });

    const responseHeaders = {
      ...cors,
      "Content-Type": response.headers.get("content-type") || "application/json",
    };
    for (const name of [
      "content-disposition", "cache-control", "content-range", "content-length",
      "accept-ranges", "etag", "last-modified", "x-request-id",
      "x-content-type-options", "x-frame-options", "referrer-policy",
      "x-permitted-cross-domain-policies", "content-security-policy",
      "strict-transport-security", "retry-after", "vary",
    ]) {
      const value = response.headers.get(name);
      if (value) responseHeaders[name] = value;
    }
    res.writeHead(response.status, responseHeaders);
    if (!response.body || req.method === "HEAD") return res.end();
    await pipeline(Readable.fromWeb(response.body), res);
  } catch (error) {
    if (res.headersSent) return res.destroy(error);
    res.writeHead(502, {
      ...cors,
      "Content-Type": "application/json; charset=utf-8",
      "X-Content-Type-Options": "nosniff",
    });
    res.end(JSON.stringify({ error: "تعذر الاتصال بخادم برق" }));
  }
});

server.requestTimeout = 120_000;
server.headersTimeout = 30_000;
server.keepAliveTimeout = 5_000;

const PORT = process.env.PORT || 3000;
server.listen(PORT, "0.0.0.0", () => {
  console.log("BARQ proxy is running on port " + PORT);
});
