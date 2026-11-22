const UPSTREAM = "https://siraj-api.alhmdanybdhmhmwd.workers.dev";

module.exports = async (req, res) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader(
    "Access-Control-Allow-Headers",
    "Content-Type, Authorization"
  );

  if (req.method === "OPTIONS") {
    return res.status(204).end();
  }

  try {
    const chunks = [];

    for await (const chunk of req) {
      chunks.push(chunk);
    }

    const body = Buffer.concat(chunks);

    const headers = {};

    if (req.headers["content-type"]) {
      headers["Content-Type"] = req.headers["content-type"];
    }

    if (req.headers.authorization) {
      headers["Authorization"] = req.headers.authorization;
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
