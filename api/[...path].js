// Keep production isolated on its existing upstream. Preview deployments
// route through the isolated BARQ test Worker so reachability can be verified
// without changing production traffic or data.
const UPSTREAM = process.env.BARQ_API_UPSTREAM ||
  (process.env.VERCEL_ENV === "preview"
    ? "https://barq-api-phase2-test.alhmdanybdhmhmwd.workers.dev"
    : "https://siraj-api.alhmdanybdhmhmwd.workers.dev");

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-File-Name, X-Recipient-Id, X-Group-Id, X-Idempotency-Key"
  );
  res.setHeader("Access-Control-Expose-Headers", "Content-Disposition");

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
    // Preserve byte-range semantics for resumable/large media downloads.
    if (req.headers.range) headers.Range = req.headers.range;
    if (req.headers["if-range"]) headers["If-Range"] = req.headers["if-range"];

    const response = await fetch(UPSTREAM + req.url, {
      method: req.method,
      headers,
      body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
    });

    res.status(response.status);

    res.setHeader(
      "Content-Type",
      response.headers.get("content-type") || "application/json"
    );
    const disposition = response.headers.get("content-disposition");
    if (disposition) res.setHeader("Content-Disposition", disposition);
    const cacheControl = response.headers.get("cache-control");
    if (cacheControl) res.setHeader("Cache-Control", cacheControl);
    for (const name of ["content-range", "content-length", "accept-ranges", "etag", "last-modified"]) {
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
      error: "تعذر الاتصال بخادم سراج",
    });
  }
};

module.exports.config = {
  api: {
    bodyParser: false,
  },
};
