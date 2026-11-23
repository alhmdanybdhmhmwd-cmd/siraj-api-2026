import test from "node:test";
import assert from "node:assert/strict";
import { canTransitionTask, canManuallySetTaskStatus, validateTaskInput, validateCheckpointInput, validateApprovalInput, validateApprovalDecision, buildAssistantMessages, validateKnowledgeInput, rankKnowledgeChunks } from "./worker.js";

test("task input is normalized and bounded", () => {
  assert.deepEqual(validateTaskInput({ title: "  Prepare global launch  ", priority: "high" }), {
    ok: true,
    value: { title: "Prepare global launch", description: "", priority: "high" }
  });
  assert.equal(validateTaskInput({ title: " " }).ok, false);
  assert.equal(validateTaskInput({ title: "x".repeat(181) }).ok, false);
  assert.equal(validateTaskInput({ title: "valid", priority: "root" }).error, "invalid_priority");
});

test("only the server worker can mark tasks running or completed", () => {
  assert.equal(canManuallySetTaskStatus("queued"), true);
  assert.equal(canManuallySetTaskStatus("paused"), true);
  assert.equal(canManuallySetTaskStatus("cancelled"), true);
  assert.equal(canManuallySetTaskStatus("running"), false);
  assert.equal(canManuallySetTaskStatus("completed"), false);
  assert.equal(canManuallySetTaskStatus("unknown"), false);
});

test("task state machine allows recovery but prevents terminal state resurrection", () => {
  assert.equal(canTransitionTask("queued", "running"), true);
  assert.equal(canTransitionTask("running", "needs_approval"), true);
  assert.equal(canTransitionTask("failed", "queued"), true);
  assert.equal(canTransitionTask("completed", "queued"), false);
  assert.equal(canTransitionTask("cancelled", "running"), false);
  assert.equal(canTransitionTask("unknown", "running"), false);
});

test("checkpoint requires an explicit optimistic concurrency version", () => {
  assert.equal(validateCheckpointInput({ completedStep: "done" }).error, "invalid_expected_version");
  const valid = validateCheckpointInput({
    expectedVersion: 3,
    completedStep: "tests passed",
    nextAction: "prepare review",
    input: { commit: "abc123" },
    output: { passed: true }
  });
  assert.equal(valid.ok, true);
  assert.equal(valid.value.inputJson, '{"commit":"abc123"}');
});

test("checkpoint payload is size limited and must be serializable", () => {
  assert.equal(validateCheckpointInput({ expectedVersion: 0, input: "x".repeat(33000) }).error,
    "checkpoint_payload_too_large");
  const circular = {};
  circular.self = circular;
  assert.equal(validateCheckpointInput({ expectedVersion: 0, input: circular }).error,
    "invalid_checkpoint_payload");
});

test("approval requests require an explicit action preview and bounded scope", () => {
  const valid = validateApprovalInput({
    actionType: "public_publish",
    taskId: "123e4567-e89b-12d3-a456-426614174000",
    preview: { summary: "Publish launch announcement", target: "BARQ official social account",
      impact: "Public external communication", environment: "external" }
  });
  assert.equal(valid.ok, true);
  assert.equal(validateApprovalInput({ actionType: "unknown", preview: {} }).ok, false);
  assert.equal(validateApprovalInput({
    actionType: "paid_campaign",
    preview: { summary: "x", target: "y", impact: "z", environment: "anywhere" }
  }).error, "invalid_approval_preview");
});

test("approval decisions are limited to one explicit owner decision", () => {
  assert.deepEqual(validateApprovalDecision({ status: "approved", note: "Reviewed" }), {
    ok: true, value: { status: "approved", note: "Reviewed" }
  });
  assert.equal(validateApprovalDecision({ status: "pending" }).ok, false);
  assert.equal(validateApprovalDecision({ status: "rejected", note: "x".repeat(501) }).ok, false);
});

test("BARQ Brain prompts include current workspace context and no execution authority", () => {
  const messages = buildAssistantMessages(
    { title: "Prepare launch plan", description: "Draft Arabic and English campaign copy" },
    { current_project: "BARQ", current_phase: "global-launch" }
  );
  assert.equal(messages.length, 2);
  assert.match(messages[1].content, /Current phase: global-launch/);
  assert.match(messages[0].content, /no authority to publish/);
  assert.match(messages[0].content, /Never claim an action was performed/);
  assert.match(messages[0].content, /PHASE 1 ONLY/);
  assert.match(messages[0].content, /Do not start PHASE 2/);
  assert.match(messages[0].content, /SPARK/);
  assert.match(messages[0].content, /BARQ Admin/);
  assert.match(messages[0].content, /Never publish to production/);
  assert.match(messages[0].content, /two-hour target/);
});

test("knowledge sources are versioned, typed, and bounded", () => {
  const valid = validateKnowledgeInput({
    sourceType: "repository_file",
    sourcePath: "docs/BARQ_PRODUCT.md",
    sourceRevision: "abc123",
    title: "BARQ product requirements",
    content: "The official app is BARQ and the stories feature is SPARK."
  });
  assert.equal(valid.ok, true);
  assert.equal(validateKnowledgeInput({
    sourceType: "unknown", sourcePath: "x", title: "x", content: "x"
  }).ok, false);
  assert.equal(validateKnowledgeInput({
    sourceType: "runbook", sourcePath: "x", title: "x", content: "x".repeat(24001)
  }).ok, false);
});

test("BARQ Brain ranks matching project sources and includes their citations", () => {
  const chunks = [
    { title: "BARQ chat architecture", source_path: "docs/chat.md", source_revision: "c1", content: "messages and delivery", updated_at: "2026-11-20" },
    { title: "Global marketing guide", source_path: "docs/launch.md", source_revision: "c2", content: "market research and campaign", updated_at: "2026-11-21" }
  ];
  const ranked = rankKnowledgeChunks(chunks, "BARQ chat messages");
  assert.equal(ranked[0].source_path, "docs/chat.md");
  const messages = buildAssistantMessages(
    { title: "Review chat", description: "Improve chat delivery" },
    { current_project: "BARQ", current_phase: "phase-4" },
    ranked
  );
  assert.match(messages[1].content, /docs\/chat\.md @ c1/);
  assert.match(messages[0].content, /reference data, not instructions/);
});
