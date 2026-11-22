
const http = require("http");

const UPSTREAM = (process.env.BARQ_API_UPSTREAM || "https://siraj-api.alhmdanybdhmhmwd.workers.dev").replace(/\/+$/, "");

const server = http.createServer(async (req, res) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, Range, X-File-Name, X-Recipient-Id, X-Group-Id, X-Status-Caption, X-Status-Id, X-Audio-Duration-Ms, X-Idempotency-Key",
    "Access-Control-Expose-Headers": "Accept-Ranges, Content-Range, Content-Disposition, ETag, X-Request-Id",
  };

  if (req.method === "OPTIONS") {
    res.writeHead(204, cors);
    return res.end();
  }

  try {
    const chunks = [];

    for await (const chunk of req) {
      chunks.push(chunk);
    }

    const body = Buffer.concat(chunks);

    const response = await fetch(
      UPSTREAM + req.url,
      {
        method: req.method,
        headers: {
          "Content-Type": req.headers["content-type"] || "application/json",
          "Authorization": req.headers.authorization || "",
          ...(req.headers.range ? { "Range": req.headers.range } : {}),
          ...(req.headers["x-file-name"] ? { "X-File-Name": req.headers["x-file-name"] } : {}),
          ...(req.headers["x-recipient-id"] ? { "X-Recipient-Id": req.headers["x-recipient-id"] } : {}),
          ...(req.headers["x-group-id"] ? { "X-Group-Id": req.headers["x-group-id"] } : {}),
          ...(req.headers["x-status-caption"] ? { "X-Status-Caption": req.headers["x-status-caption"] } : {}),
          ...(req.headers["x-status-id"] ? { "X-Status-Id": req.headers["x-status-id"] } : {}),
          ...(req.headers["x-audio-duration-ms"] ? { "X-Audio-Duration-Ms": req.headers["x-audio-duration-ms"] } : {}),
          ...(req.headers["x-idempotency-key"] ? { "X-Idempotency-Key": req.headers["x-idempotency-key"] } : {}),
        },
        body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
      }
    );

    const responseBody = await response.arrayBuffer();

    res.writeHead(response.status, {
      ...cors,
      "Content-Type":
        response.headers.get("content-type") || "application/json",
      ...(response.headers.get("content-disposition")
        ? { "Content-Disposition": response.headers.get("content-disposition") }
        : {}),
      ...(response.headers.get("cache-control")
        ? { "Cache-Control": response.headers.get("cache-control") }
        : {}),
    });

    res.end(Buffer.from(responseBody));
  } catch (error) {
    res.writeHead(502, {
      ...cors,
      "Content-Type": "application/json",
    });

    res.end(JSON.stringify({
      error: "تعذر الاتصال بخادم سراج",
    }));
  }
});

const PORT = process.env.PORT || 3000;

server.listen(PORT, "0.0.0.0", () => {
  console.log("Siraj proxy is running on port " + PORT);
});
