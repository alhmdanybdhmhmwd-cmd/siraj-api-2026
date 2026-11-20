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
The isolated database provisioning and separation checks passed. The migration workflow applies the repository migration set only to the test database; its result must be checked in GitHub Actions before considering the test schema initialized.

Required GitHub Actions settings:
- Secret: `BARQ_CLOUDFLARE_API_TOKEN`
- Variable: `BARQ_CLOUDFLARE_ACCOUNT_ID`
