// Keep Preview pinned to its isolated Worker. Production fallback is opt-in
// and remains inert until a separately provisioned HTTPS upstream is configured.
const PREVIEW_UPSTREAM = "https://barq-api-phase2-test.alhmdanybdhmhmwd.workers.dev";
const DEFAULT_PRODUCTION_UPSTREAM = "https://siraj-api.alhmdanybdhmhmwd.workers.dev";

function getUpstreamCandidates(env = process.env) {
  if (env.VERCEL_ENV === "preview") return [PREVIEW_UPSTREAM];
  const primary = env.BARQ_API_UPSTREAM || DEFAULT_PRODUCTION_UPSTREAM;
  const candidates = [primary];
  const fallback = env.BARQ_API_FALLBACK_UPSTREAM;
  if (fallback && fallback !== primary) {
    try {
      const parsed = new URL(fallback);
      const normalized = fallback.replace(/\\/$/, "");
      if (parsed.protocol === "https:" && parsed.origin === normalized) candidates.push(normalized);
    } catch (_) {
      // Ignore malformed fallback configuration; never route to an unsafe URL.
    }
  }
  return candidates;
}

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, Range, X-File-Name, X-Recipient-Id, X-Group-Id, X-Idempotency-Key, X-Status-Caption, X-Status-Id, X-Audio-Duration-Ms"
  );
  res.setHeader(
    "Access-Control-Expose-Headers",
    "Accept-Ranges, Content-Range, Content-Disposition, ETag, X-Request-Id"
  );

  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }

  try {
    const requestPath = new URL(req.url, "https://vercel.invalid").pathname;
    const isMediaUpload = req.method === "POST" && requestPath === "/api/media";
    const isMultipartChunkUpload = req.method === "PUT" &&
      /^\/api\/media\/uploads\/[A-Za-z0-9-]{1,128}\/chunks\/\d+$/.test(requestPath);
    const isMultipartPartUpload = req.method === "PUT" &&
      /^\/api\/media\/uploads\/[A-Za-z0-9-]{1,128}\/parts\/\d+$/.test(requestPath);
    const isProfilePhotoUpload = req.method === "POST" &&
      requestPath.startsWith("/api/profile/photo/");
    const maxMediaBytes = 60 * 1024 * 1024;
    const maxMultipartChunkBytes = 1 * 1024 * 1024;
    const maxMultipartPartBytes = 5 * 1024 * 1024;
    const maxProfilePhotoBytes = 4 * 1024 * 1024;
    const declaredLength = Number(req.headers["content-length"]);
    if (isMediaUpload && Number.isFinite(declaredLength) && declaredLength > maxMediaBytes) {
      return res.status(413).json({ error: "File must be between 1 byte and 60 MB" });
    }
    if (isMultipartChunkUpload && Number.isFinite(declaredLength) && declaredLength > maxMultipartChunkBytes) {
      return res.status(413).json({ error: "Transport chunk must not exceed 1 MiB" });
    }
    if (isMultipartPartUpload && Number.isFinite(declaredLength) && declaredLength > maxMultipartPartBytes) {
      return res.status(413).json({ error: "Multipart part must not exceed 5 MiB" });
    }
    if (isProfilePhotoUpload && Number.isFinite(declaredLength) && declaredLength > maxProfilePhotoBytes) {
      return res.status(413).json({ error: "Profile photo must not exceed 4 MiB" });
    }

    const chunks = [];
    let receivedBytes = 0;

    for await (const chunk of req) {
      const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      receivedBytes += buffer.length;
      if (isMediaUpload && receivedBytes > maxMediaBytes) {
        return res.status(413).json({ error: "File must be between 1 byte and 60 MB" });
      }
      if (isMultipartChunkUpload && receivedBytes > maxMultipartChunkBytes) {
        return res.status(413).json({ error: "Transport chunk must not exceed 1 MiB" });
      }
      if (isMultipartPartUpload && receivedBytes > maxMultipartPartBytes) {
        return res.status(413).json({ error: "Multipart part must not exceed 5 MiB" });
      }
      if (isProfilePhotoUpload && receivedBytes > maxProfilePhotoBytes) {
        return res.status(413).json({ error: "Profile photo must not exceed 4 MiB" });
      }
      chunks.push(buffer);
    }

    const body = Buffer.concat(chunks);

    const headers = {};

    if (req.headers["content-type"]) {
      headers["Content-Type"] = req.headers["content-type"];
    }

    if (req.headers.authorization) {
      headers["Authorization"] = req.headers.authorization;
    }
    if (req.headers["x-file-name"]) {
      headers["X-File-Name"] = req.headers["x-file-name"];
    }
    if (req.headers["x-recipient-id"]) {
      headers["X-Recipient-Id"] = req.headers["x-recipient-id"];
    }
    if (req.headers["x-group-id"]) {
      headers["X-Group-Id"] = req.headers["x-group-id"];
    }
    // Preserve BARQ media metadata headers across the public API gateway.
    // These are required by SPARK publishing and voice-reply validation.
    if (req.headers["x-idempotency-key"]) {
      headers["X-Idempotency-Key"] = req.headers["x-idempotency-key"];
    }
    if (req.headers["x-status-caption"]) {
      headers["X-Status-Caption"] = req.headers["x-status-caption"];
    }
    if (req.headers["x-status-id"]) {
      headers["X-Status-Id"] = req.headers["x-status-id"];
    }
    if (req.headers["x-audio-duration-ms"]) {
      headers["X-Audio-Duration-Ms"] = req.headers["x-audio-duration-ms"];
    }
    // Preserve byte-range semantics for resumable/large media downloads.
    if (req.headers.range) headers.Range = req.headers.range;
    if (req.headers["if-range"]) headers["If-Range"] = req.headers["if-range"];

    const upstreams = getUpstreamCandidates();
    let response = null;
    let lastError = null;
    for (let index = 0; index < upstreams.length; index += 1) {
      try {
        response = await fetch(upstreams[index] + req.url, {
          method: req.method,
          headers,
          body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
        });
        // Retry only gateway/service-unavailable responses. Application errors
        // (including auth and validation failures) must not be replayed elsewhere.
        if (![502, 503, 504].includes(response.status) || index === upstreams.length - 1) break;
      } catch (error) {
        lastError = error;
        if (index === upstreams.length - 1) throw error;
      }
    }
    if (!response) throw lastError || new Error("No BARQ upstream responded");

    res.status(response.status);

    res.setHeader(
      "Content-Type",
      response.headers.get("content-type") || "application/json"
    );
    const disposition = response.headers.get("content-disposition");
    if (disposition) res.setHeader("Content-Disposition", disposition);
    const cacheControl = response.headers.get("cache-control");
    if (cacheControl) res.setHeader("Cache-Control", cacheControl);
    for (const name of ["content-range", "content-length", "accept-ranges", "etag", "last-modified", "x-request-id", "retry-after", "server-timing", "vary"]) {
      const value = response.headers.get(name);
      if (value) res.setHeader(name, value);
    }

    // Stream media instead of buffering the complete upstream response in memory.
    // Keep a small fallback for non-Writable response doubles used by unit tests.
    if (response.body && typeof res.write === "function" && typeof res.end === "function") {
      const { Readable } = require("node:stream");
      const { pipeline } = require("node:stream/promises");
      await pipeline(Readable.fromWeb(response.body), res);
      return;
    }

    const responseBody = await response.arrayBuffer();
    return res.send(Buffer.from(responseBody));
  } catch (error) {
    // Once streaming has started, a JSON gateway response would corrupt the partial file.
    if (res.headersSent) {
      res.destroy(error);
      return;
    }
    return res.status(502).json({
      error: "تعذر الاتصال بخادم برق",
    });
  }
};

module.exports.config = {
  api: {
    bodyParser: false,
  },
};

module.exports.getUpstreamCandidates = getUpstreamCandidates;
