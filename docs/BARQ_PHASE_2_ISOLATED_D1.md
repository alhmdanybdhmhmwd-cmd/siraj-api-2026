# BARQ Phase 2 — isolated D1 test database

This workflow creates one dedicated Cloudflare D1 database named `barq-phase2-test-2026-11-20`.

## Safety guarantees
- Runs only on the dedicated phase-2 branch when this workflow file changes.
- Verifies the Cloudflare account token and confirms the known production database ID belongs to `siraj-db`.
- Refuses to create if the target name already exists.
- Creates a new D1 database; it does not bind, migrate, query, or write application data.
- Verifies the created database has a distinct ID and reports that ID in the Actions run summary.
- Never deploys a Worker or changes production configuration.

Required GitHub Actions settings:
- Secret: `BARQ_CLOUDFLARE_API_TOKEN`
- Variable: `BARQ_CLOUDFLARE_ACCOUNT_ID`
