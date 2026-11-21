import { readFile, writeFile } from "node:fs/promises";

const workerSource = await readFile(new URL("../src/src/index.js", import.meta.url), "utf8");
const summarySource = await readFile(new URL("../src/src/conversation_summary.js", import.meta.url), "utf8");
let source = workerSource.replace(
  'import { prepareConversationSummaryTranscript, buildConversationSummaryMessages, extractConversationSummaryText } from "./conversation_summary.js";',
  summarySource
);
source = source.replace(
  'import { AwsClient } from "aws4fetch";',
  'class AwsClient { async fetch(url, options) { return globalThis.__fakeTigrisHandler(url, options); } }'
);
source += "\nexport { signToken, verifyToken, authenticate, hashPassword, sendSirajPush, detectProfileImageType, readRequestBodyLimited, rollbackSparkMediaUpload };\n";
await writeFile("/tmp/barq-worker-auth-transformed.mjs", source, "utf8");
console.log("Prepared transformed Worker module for syntax validation.");
