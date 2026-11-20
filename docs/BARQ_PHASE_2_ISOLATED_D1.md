# BARQ Phase 2 — isolated D1 test database

The dedicated Cloudflare D1 test database has been created and verified.

- Name: `barq-phase2-test-2026-11-20`
- ID: `5bfada32-4f9b-4edb-85dd-3b3b30ab73b0`
- Test-only Wrangler config: `wrangler.test.toml`
- Isolation regression test: `test/barq_wrangler_config.test.py`
- Production database `siraj-db` remains separate and unchanged.

## Safety guarantees
- The provisioning workflow confirmed the Cloudflare account and exact production database ID before creation.
- It refused duplicate target names and verified the created database ID was distinct from production.
- It did not run migrations, deploy a Worker, or write application data.
- `wrangler.test.toml` binds only the isolated test database. It deliberately has no production media bucket, production routes, or production variables.
- CI now checks that the test config uses the dedicated D1 ID and differs from production.
- The production `wrangler.toml` remains unchanged.

## Next validation
Before running migrations, inspect the full baseline schema and migration order. Do not run migration commands with the production `wrangler.toml`. Use only `--config wrangler.test.toml` after the schema baseline has been validated.

Required GitHub Actions settings:
- Secret: `BARQ_CLOUDFLARE_API_TOKEN`
- Variable: `BARQ_CLOUDFLARE_ACCOUNT_ID`
