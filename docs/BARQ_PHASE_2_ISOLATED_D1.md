# BARQ Phase 2 — isolated D1 test database

The dedicated Cloudflare D1 test database has been created and verified.

- Name: `barq-phase2-test-2026-11-20`
- ID: `5bfada32-4f9b-4edb-85dd-3b3b30ab73b0`
- Test-only Wrangler config: `wrangler.test.toml`
- Isolation regression test: `test/barq_wrangler_config.test.py`
- Test-only migration workflow: `.github/workflows/barq-test-db-migrations.yml`
- Production database `siraj-db` remains separate and unchanged.

## Safety guarantees
- The provisioning workflow confirmed the Cloudflare account and exact production database ID before creation.
- It refused duplicate target names and verified the created database ID was distinct from production.
- The migration workflow runs only on the dedicated branch, checks the isolated config, and uses `--config wrangler.test.toml` with the test database name.
- It does not deploy a Worker or use the production `wrangler.toml`.
- `wrangler.test.toml` binds only the isolated test database. It deliberately has no production media bucket, production routes, or production variables.
- CI checks that the test config uses the dedicated D1 ID and differs from production.
- The production `wrangler.toml` remains unchanged.

## Validation status
- Isolated database provisioning: passed.
- Database identity and production-separation verification: passed.
- Test-only Wrangler configuration guard: passed in CI.
- Migration `0001_recovery_codes.sql`: successfully applied to the isolated test database (4 SQL commands executed).
- No migration was applied to production.

## Remaining phase-2 checks
- Local Worker runtime HTTP probes (`/health/live` and `/health/ready`) using Wrangler and isolated local D1 state: passed in GitHub Actions run 44645892897.
- Runtime HTTP probes against a deployed test Worker: not run; no Worker deployment was performed.
- Flutter/Dart analysis and build validation: pending because Flutter/Dart are not installed in the current build environment.
- Do not deploy or merge to production as part of these checks.

Required GitHub Actions settings:
- Secret: `BARQ_CLOUDFLARE_API_TOKEN`
- Variable: `BARQ_CLOUDFLARE_ACCOUNT_ID`
