
const http = require("http");

const UPSTREAM = "https://siraj-api.alhmdanybdhmhmwd.workers.dev";

const server = http.createServer(async (req, res) => {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
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
        },
        body: ["GET", "HEAD"].includes(req.method) ? undefined : body,
      }
    );

    const responseBody = await response.arrayBuffer();

    res.writeHead(response.status, {
      ...cors,
      "Content-Type":
        response.headers.get("content-type") || "application/json",
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
