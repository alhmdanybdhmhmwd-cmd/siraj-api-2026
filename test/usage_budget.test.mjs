import test from "node:test";
import assert from "node:assert/strict";
import { estimateMonthlyUsageCost, evaluateUsageBudgets } from "../src/src/usage_budget.js";

test("monthly usage cost estimator converts bytes and operation counts without assuming vendor prices", () => {
  const estimate = estimateMonthlyUsageCost({
    storageByteMonths: 2 * 1024 ** 3,
    egressBytes: 3 * 1024 ** 3,
    requests: 2_000_000,
    databaseReads: 4_000_000,
    databaseWrites: 1_000_000
  }, {
    storagePerGiBMonth: 0.02,
    egressPerGiB: 0.05,
    requestsPerMillion: 0.4,
    databaseReadsPerMillion: 0.1,
    databaseWritesPerMillion: 0.5
  });
  assert.deepEqual(estimate.units, {
    storageGiBMonths: 2, egressGiB: 3, requestsMillions: 2,
    databaseReadsMillions: 4, databaseWritesMillions: 1
  });
  assert.equal(estimate.total, 1.29);
});

test("budget monitor warns at 80 percent and marks exceeded budgets without blocking", () => {
  const report = evaluateUsageBudgets(
    { storageBytes: 80, egressBytes: 101, requests: 10, databaseReads: 0, databaseWrites: 5 },
    { storageBytes: 100, egressBytes: 100, requests: 100, databaseReads: 100, databaseWrites: 10 }
  );
  assert.equal(report.hasWarning, true);
  assert.equal(report.hasExceeded, true);
  assert.equal(report.results.find(item => item.name === "storageBytes").status, "warning");
  assert.equal(report.results.find(item => item.name === "egressBytes").status, "exceeded");
  assert.equal(report.results.find(item => item.name === "databaseReads").status, "ok");
});

test("unconfigured budgets remain visible and do not masquerade as zero-cost limits", () => {
  const report = evaluateUsageBudgets({ storageBytes: 5 }, {});
  assert.ok(report.results.every(item => item.status === "unconfigured"));
  assert.equal(report.hasWarning, false);
  assert.equal(report.hasExceeded, false);
});

test("cost and budget inputs reject negative, infinite, and invalid threshold values", () => {
  assert.throws(() => estimateMonthlyUsageCost({ egressBytes: -1 }, {}), /non-negative/);
  assert.throws(() => evaluateUsageBudgets({ requests: Infinity }, { requests: 100 }), /finite/);
  assert.throws(() => evaluateUsageBudgets({}, {}, 1), /warningRatio/);
});
