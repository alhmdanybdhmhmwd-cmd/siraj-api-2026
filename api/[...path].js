const UPSTREAM = "https://siraj-api.alhmdanybdhmhmwd.workers.dev";

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization, X-File-Name, X-Recipient-Id, X-Group-Id"
  );
  res.setHeader("Access-Control-Expose-Headers", "Content-Disposition");

  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }

  try {
    const isMediaUpload = req.method === "POST" &&
      new URL(req.url, "https://vercel.invalid").pathname === "/api/media";
    const maxMediaBytes = 60 * 1024 * 1024;
    const declaredLength = Number(req.headers["content-length"]);
    if (isMediaUpload && Number.isFinite(declaredLength) && declaredLength > maxMediaBytes) {
      return res.status(413).json({ error: "File must be between 1 byte and 60 MB" });
    }

    const chunks = [];
    let receivedBytes = 0;

    for await (const chunk of req) {
      const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
      receivedBytes += buffer.length;
      if (isMediaUpload && receivedBytes > maxMediaBytes) {
        return res.status(413).json({ error: "File must be between 1 byte and 60 MB" });
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

    const response = await fetch(UPSTREAM + req.url, {
      method: req.method,
      headers,
      body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
    });

    const responseBody = await response.arrayBuffer();

    res.status(response.status);

    res.setHeader(
      "Content-Type",
      response.headers.get("content-type") || "application/json"
    );
    const disposition = response.headers.get("content-disposition");
    if (disposition) res.setHeader("Content-Disposition", disposition);
    const cacheControl = response.headers.get("cache-control");
    if (cacheControl) res.setHeader("Cache-Control", cacheControl);

    return res.send(Buffer.from(responseBody));
  } catch (error) {
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

// Disable Vercel's default JSON body parser so the proxy can forward the
// original request stream to the Worker without silently sending an empty body.
module.exports.config = {
  api: {
    bodyParser: false,
  },
};
