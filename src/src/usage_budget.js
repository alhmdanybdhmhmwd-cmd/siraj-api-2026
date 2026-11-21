const GIB = 1024 ** 3;
const MILLION = 1_000_000;

function nonNegativeFinite(value, label) {
  const number = Number(value ?? 0);
  if (!Number.isFinite(number) || number < 0) {
    throw new RangeError(label + " must be a finite non-negative number");
  }
  return number;
}

/**
 * Estimate monthly infrastructure cost from provider-reported usage.
 * Unit rates are supplied by the operator; no vendor pricing is assumed.
 */
export function estimateMonthlyUsageCost(usage = {}, rates = {}) {
  const storageGiBMonths = nonNegativeFinite(usage.storageByteMonths, "storageByteMonths") / GIB;
  const egressGiB = nonNegativeFinite(usage.egressBytes, "egressBytes") / GIB;
  const requestsMillions = nonNegativeFinite(usage.requests, "requests") / MILLION;
  const databaseReadsMillions = nonNegativeFinite(usage.databaseReads, "databaseReads") / MILLION;
  const databaseWritesMillions = nonNegativeFinite(usage.databaseWrites, "databaseWrites") / MILLION;

  const cost = {
    storage: storageGiBMonths * nonNegativeFinite(rates.storagePerGiBMonth, "storagePerGiBMonth"),
    egress: egressGiB * nonNegativeFinite(rates.egressPerGiB, "egressPerGiB"),
    requests: requestsMillions * nonNegativeFinite(rates.requestsPerMillion, "requestsPerMillion"),
    databaseReads: databaseReadsMillions * nonNegativeFinite(rates.databaseReadsPerMillion, "databaseReadsPerMillion"),
    databaseWrites: databaseWritesMillions * nonNegativeFinite(rates.databaseWritesPerMillion, "databaseWritesPerMillion")
  };
  return Object.freeze({
    ...cost,
    total: Object.values(cost).reduce((sum, value) => sum + value, 0),
    units: Object.freeze({ storageGiBMonths, egressGiB, requestsMillions, databaseReadsMillions, databaseWritesMillions })
  });
}

/**
 * Compare measured usage with operator-defined monthly budgets.
 * Returns warnings only; it never blocks user traffic or deletes data.
 */
export function evaluateUsageBudgets(usage = {}, budgets = {}, warningRatio = 0.8) {
  const ratio = nonNegativeFinite(warningRatio, "warningRatio");
  if (ratio <= 0 || ratio >= 1) throw new RangeError("warningRatio must be greater than 0 and less than 1");
  const dimensions = ["storageBytes", "egressBytes", "requests", "databaseReads", "databaseWrites"];
  const results = dimensions.map(name => {
    const actual = nonNegativeFinite(usage[name], name);
    const limit = budgets[name] == null ? null : nonNegativeFinite(budgets[name], name + " budget");
    if (limit === null || limit === 0) return Object.freeze({ name, actual, limit, status: "unconfigured", utilization: null });
    const utilization = actual / limit;
    const status = utilization >= 1 ? "exceeded" : utilization >= ratio ? "warning" : "ok";
    return Object.freeze({ name, actual, limit, status, utilization });
  });
  return Object.freeze({
    results: Object.freeze(results),
    hasExceeded: results.some(item => item.status === "exceeded"),
    hasWarning: results.some(item => item.status === "warning" || item.status === "exceeded")
  });
}
