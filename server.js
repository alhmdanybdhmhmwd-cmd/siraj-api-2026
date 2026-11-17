const http = require("http");

const UPSTREAM = "https://siraj-api.alhmdanybdhmhmwd.workers.dev";

const server = http.createServer(async (req, res) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization, X-File-Name, X-Recipient-Id, X-Group-Id",
    "Access-Control-Expose-Headers": "Content-Disposition, Content-Length",
  };

  if (req.method === "OPTIONS") {
    res.writeHead(204, cors);
    return res.end();
  }

  try {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const body = Buffer.concat(chunks);

    const response = await fetch(UPSTREAM + req.url, {
      method: req.method,
      headers: {
        "Content-Type": req.headers["content-type"] || "application/json",
        "Authorization": req.headers.authorization || "",
        ...(req.headers["x-file-name"] ? { "X-File-Name": req.headers["x-file-name"] } : {}),
        ...(req.headers["x-recipient-id"] ? { "X-Recipient-Id": req.headers["x-recipient-id"] } : {}),
        ...(req.headers["x-group-id"] ? { "X-Group-Id": req.headers["x-group-id"] } : {}),
      },
      body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
    });

    const responseBody = await response.arrayBuffer();
    const responseHeaders = {
      ...cors,
      "Content-Type": response.headers.get("content-type") || "application/json",
    };

    // Preserve attachment metadata so clients can save downloads with the
    // original filename and know the exact response size.
    const disposition = response.headers.get("content-disposition");
    const length = response.headers.get("content-length");
    const cacheControl = response.headers.get("cache-control");
    if (disposition) responseHeaders["Content-Disposition"] = disposition;
    if (length) responseHeaders["Content-Length"] = length;
    if (cacheControl) responseHeaders["Cache-Control"] = cacheControl;

    res.writeHead(response.status, responseHeaders);
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
