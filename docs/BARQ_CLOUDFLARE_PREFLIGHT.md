# BARQ Cloudflare preflight (read-only)

This workflow verifies that the temporary Cloudflare token can authenticate and list D1 databases. It does **not** deploy a Worker, create/alter/delete a database, run migrations, or write application data.

## Add the two GitHub Actions values

In the repository, open **Settings → Secrets and variables → Actions**.

1. Under **Secrets**, add:
   - Name: `BARQ_CLOUDFLARE_API_TOKEN`
   - Secret: paste the Cloudflare API token you created. Do not put it in chat, source files, Vercel environment variables, or workflow YAML.
2. Under **Variables**, add:
   - Name: `BARQ_CLOUDFLARE_ACCOUNT_ID`
   - Value: the Cloudflare Account ID for the account where the token was created. Find it in the Cloudflare dashboard account overview / Workers & Pages account details. This ID is not the API token.

Do not add either value to Vercel. Do not create a production deployment.

## Run the preflight

After this branch is available, open **Actions → BARQ Cloudflare preflight (read-only) → Run workflow** and select branch `barq/phase-2-cloudflare-preflight-2026-11-20`.

Expected result: token identity verification succeeds and D1 database listing completes. The listing is read-only. We will use the returned database IDs to verify/create a separate test database in a later, separately reviewed step. The repository's current `wrangler.toml` points to the production D1 database, so this preflight deliberately runs Wrangler from the runner temporary directory and never deploys or runs migrations.

## Safety

- Token scope should be limited to Workers Scripts: Edit and D1: Edit, with a short expiry.
- The workflow uses repository secrets/variables and never echoes the token.
- This workflow is manual-only and read-only.
- No PR is merged and no production deployment is triggered by this change.
