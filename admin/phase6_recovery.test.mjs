import test from "node:test";
import assert from "node:assert/strict";
import { processAdminDeadLetterMessage } from "./worker.js";

function message(actions, body) {
  return {
    body,
    ack() { actions.push("ack"); },
    retry(options) { actions.push(["retry", options]); }
  };
}

test("dead-letter recovery retries safely when the Admin database is unavailable", async () => {
  const actions = [];
  await processAdminDeadLetterMessage(
    message(actions, { taskId: "task-db-offline", workspaceId: "workspace-1" }),
    {}
  );
  assert.deepEqual(actions, [["retry", { delaySeconds: 60 }]]);
});

test("dead-letter recovery preserves a queued task when runtime bindings are missing", async () => {
  const actions = [];
  const calls = [];
  const env = {
    ADMIN_DB: {
      prepare(sql) {
        return {
          bind(...args) {
            return {
              async first() {
                calls.push({ kind: "read", sql, args });
                return { status: "queued", lease_active: 0 };
              },
              async run() {
                calls.push({ kind: "write", sql, args });
                throw new Error("must_not_mutate_without_runtime_bindings");
              }
            };
          }
        };
      }
    }
  };

  await processAdminDeadLetterMessage(
    message(actions, { taskId: "task-no-bindings", workspaceId: "workspace-2" }),
    env
  );

  assert.deepEqual(actions, [["retry", { delaySeconds: 300 }]]);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].kind, "read");
});

test("dead-letter recovery acknowledges malformed queue payloads without database access", async () => {
  const actions = [];
  const env = {
    ADMIN_DB: {
      prepare() {
        throw new Error("malformed_payload_must_not_query_database");
      }
    }
  };

  await processAdminDeadLetterMessage(
    message(actions, { taskId: "task-missing-workspace" }),
    env
  );

  assert.deepEqual(actions, ["ack"]);
});
