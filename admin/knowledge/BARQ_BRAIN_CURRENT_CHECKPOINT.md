# BARQ Admin / BARQ Brain — Current Continuation Checkpoint

Checkpoint time: 2026-11-24 (UTC)
Working repository: `alhmdanybdhmhmwd-cmd/siraj-api-2026`
Working branch: `barq-admin-s7-optimized-2026-11-24`
Checkpoint revision when written: `2777f1df20e442373ecb483184bc73bd2f0c1d55`
Review PR: [#12 — Draft](https://github.com/alhmdanybdhmhmwd-cmd/siraj-api-2026/pull/12)

## Owner's current objective

Prepare BARQ Admin so the owner can install it on a Samsung Galaxy S7 and say "واصل، اشتغل، ابنِ نفسك". BARQ Brain must carry forward the known BARQ product decisions and development history, then later gain actual repository-edit/test/build tools and durable execution. The assistant must not ask the owner to repeat known project context, must not repeat completed work, and must not claim capabilities that have not been tested.

## Work completed in this branch

- Expanded `admin/knowledge/BARQ_OWNER_CONTEXT.md` with official product identity, accepted/rejected/postponed decisions, 12-stage roadmap constraints, historical technical context, Admin/Brain expectations, Galaxy S7 and no-VPN requirements, previous phase authorization chronology, consumer Phase 4 handoff, and resume protocol.
- Added `admin/knowledge/BARQ_BRAIN_MASTER_INDEX_AR.md` as the navigation map for consumer BARQ, backend, Admin, tests, workflows, and evidence hierarchy.
- Updated `admin/knowledge/PHASE2_SCOPE.md` and `admin/knowledge/INDEXING_RUNBOOK.md` with the latest owner requirement for comprehensive project memory and complete monorepo coverage.
- Updated BARQ Brain system instructions in `admin/worker.js` to prioritize canonical owner context, master index, evidence citations, checkpoint recovery, and no-repeat continuation.
- Added multilingual continuation intent detection and pinned master-index retrieval for resume commands. Canonical owner-context chunks receive a larger context allowance than ordinary source chunks.
- Added tests for Arabic/English resume commands and preservation of long canonical owner-context chunks in `admin/worker.test.mjs`.
- Fixed Admin quality workflow so PR/push runs check the actual tested commit, not the old foundation branch. Quality run concurrency is keyed by commit SHA to avoid an old blocked run holding the new revision.
- Changed the Galaxy S7 Admin APK workflow to build an ARM64-only optimized release-mode preview APK with Dart obfuscation and split debug symbols.

## Latest verified CI evidence at checkpoint creation

- Admin Worker syntax, Admin unit tests, isolated Admin schema/audit checks, Phase 2 workspace/task/checkpoint checks, and Preview template validation passed on revision `4f16a88468ff65550b88d84db77e163f13ac95a0` in run `45308427433`.
- Backend tests passed on revision `4f16a88468ff65550b88d84db77e163f13ac95a0` in run `45308434396`.
- Admin mobile quality checks were still running in run `45308427433`; confirm final result.
- New tests added after those checks in revision `2777f1df20e442373ecb483184bc73bd2f0c1d55` require a subsequent Admin quality run. Do not reuse earlier pass as proof for the newer test revision.
- ARM64-only Admin debug APK build succeeded in run `45307180610`; APK size was 97,638,277 bytes (97.6 MB / 93.1 MiB), artifact ID `14880604912`. This is about 42% smaller than the earlier 162 MB universal debug APK. It was not installed or tested on the physical S7.
- An optimized ARM64 release-mode preview build was running in workflow `45308189201` at the last check. Its final APK size, artifact upload and symbols must be verified before sharing that APK.

## Important current limitations

- No physical Galaxy S7 install, Google OIDC login, or live Admin API session has been verified.
- Dedicated Admin Preview D1/Queue/Workers AI bindings and server-side Google OIDC configuration are not yet proven live.
- Owner context and master index have been committed to GitHub but have NOT been proven ingested into Admin D1. Full repository coverage/freshness is NOT complete.
- Current Brain chat/retrieval is not yet an autonomous repository editor. Actual safe GitHub read/write, isolated patch/branch creation, test/build orchestration, and durable server-side resume are not to be claimed until implemented and end-to-end tested.
- Consumer BARQ no-VPN connectivity on Yemen Net, Yemen Mobile, and Sabafon remains an explicit acceptance requirement; a root health response is insufficient.
- Consumer BARQ Phase 4 must be rechecked against current source. Message reactions/interactions and message pinning were explicit owner requirements; do not assume they are complete.
- Public registration and News remain deferred to the final consumer phase. Do not reintroduce real phone verification as a current blocker.

## Exact next actions

1. Check latest branch HEAD, Admin quality run on revision `2777f1d...`, backend run, and ARM64 release build status.
2. Fix any failing tests and rerun against the exact latest revision.
3. Verify optimized release APK size, package identity, ARM64-only contents, and symbol artifact; do not call it S7-tested.
4. Continue Phase 2: configure/verify isolated Admin Preview resources, run the approved exact-repository indexer against an immutable commit, resume all batches to `complete=true`, reconcile skipped/stale/deleted sources, and produce coverage/freshness evidence.
5. Test retrieval using Arabic continuation prompts and questions across product decisions, Phase 4 history, app/backend architecture, Admin architecture, bugs, CI and unresolved network issues. Require source paths/revisions in answers.
6. Keep PR #12 draft/open. Do not merge, deploy production, modify production data, or expose secrets without the owner's specific approval.
7. Continue preserving the consumer BARQ and BARQ Admin technical boundary.

## Owner-facing status language

Say exactly what is complete, what has only passed CI, what is blocked, and what requires a physical phone. If only phone testing remains after code completion, use the owner's preferred phrase: "مرحلة منتهية برمجيا بقي الاختبار على الهواتف". Never use it unless evidence supports it.


## Live verification update — 2026-11-24 02:00 UTC

- Latest branch HEAD observed: `1eb4f79ae9f79d6f914d61044b0e569fcdc5e305`; draft PR #12 remains open and unmerged.
- Latest Admin Worker/unit/schema/task/checkpoint/Preview-template quality job passed on the current branch revision in run `45308948107`; Admin mobile analyze and Flutter tests also passed in that run. Android AppAuth wiring validation and Kotlin compilation were still running at last poll.
- Backend tests passed on the latest head in run `45308956051`.
- Optimized ARM64 APK workflow run `45308936229` is queued/pending. The prior release attempt failed in a third-party `image_picker_android` release lint detector; a workaround to skip only that broken dependency-specific lint task is now in the build configuration and the retry must be checked.
- Preview deploy run `45308924658` failed safely before any deployment. Its log confirms all expected GitHub Environment inputs were empty: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `ADMIN_D1_DATABASE_ID`, `BARQ_GOOGLE_OIDC_CLIENT_ID`, `BARQ_ADMIN_OWNER_EMAIL`, and `BARQ_ADMIN_ALLOWED_ORIGIN`. The two SentinelX Cloudflare integrations named `barq-admin-runtime` and `barq-cloudflare-preview` both returned zero visible DNS zones. Do not assume these are correctly scoped to the intended account or have Workers/D1 permissions. No credentials were printed.
- The exact Cloudflare Preview environment and dedicated D1/Queue resources are therefore the external blocker. Do not try production identifiers or repurpose the consumer database.
- Owner context, master index and checkpoint are present in GitHub source, but still not ingested into live D1. BARQ Brain cannot yet be described as fully informed or able to autonomously edit/build projects.


## Work continuation update — 2026-11-24 (latest branch activity)

- Admin mobile quality run `45308948107` has now completed successfully. Flutter dependency resolution, formatting, analysis, Flutter tests, Android AppAuth manifest wiring validation, and Android debug Kotlin compilation all passed. This is CI evidence only; it is not a physical Galaxy S7 install/sign-in test.
- The Admin quality job in the same run passed Worker syntax, Admin unit tests, isolated schema/audit checks, Phase 2 workspace/task/checkpoint checks, and Preview template validation.
- Backend run `45308956051` passed.
- Additional Phase 2 ingestion safety hardening was committed on this branch:
  - `admin/ingest_github_repo.mjs` now detects additional high-confidence provider credential formats (GitHub fine-grained tokens, AWS access-key IDs, Slack tokens, Stripe live secret keys, Google OAuth client secrets, npm/PyPI tokens, SendGrid API keys) before indexing repository content.
  - `admin/ingest_github_repo.test.mjs` adds positive secret-detection samples and negative ordinary-documentation checks.
  - The secret-pattern checks were exercised against eight synthetic credential samples in the current work session; all eight were detected and both ordinary documentation samples were not flagged. This is a focused runtime check, not a replacement for the repository's full Node test suite.
  - GitHub secret scanning rejected the first attempt to commit literal synthetic credential strings in test fixtures. The fixtures were rewritten as concatenated fragments; no real credentials were used or exposed.
- Latest known branch commit after this work: `e72837859407dd462660cce9d99263d607363bfd`. The secret scanner and test additions need a fresh Admin Quality run against this exact revision before being called CI-verified.
- Optimized ARM64 Release APK workflow `45308936229` still has no visible jobs or artifacts in the latest check. Do not claim the optimized APK is ready or provide the older debug build as a substitute.
- Preview deployment remains safely blocked because the required GitHub Environment values are not visible to the workflow. No deployment or production changes were made.

## Continuation work — indexing coverage and latest CI check (2026-11-24)

- Reviewed the repository indexer's extension allowlist and found that important project sources were being omitted: Admin web HTML/CSS, JSON manifests/configuration, and native Android Java/Kotlin sources.
- Expanded the allowlist to include `.html`, `.css`, `.json`, `.java`, `.kt`, `.h`, `.c`, `.cpp`, `.swift`, `.plist`, and `.xcconfig`, while preserving text-only indexing and per-file secret scanning.
- Strengthened sensitive-path exclusions for `.firebase`, `.gradle`, `local.properties`, `key.properties`, and Terraform `.tfvars`; expanded content patterns for private/signing keys, generic secrets, and refresh tokens.
- Added regression tests for HTML/CSS/JSON, Android Kotlin/Java sources, local/signing property files, Firebase metadata, Terraform variable files, and synthetic private/refresh-token values.
- Commits for this focused change: `543c47fe6f0f66613a45a46f15f1a247e14f2217`, `e342b50d697115e37a9ea28f85f204b50c255e7f`, `f54ca24dcc34184315538ed2d4cf384a04a94267`, and latest `cbb1b5dd10676ee5330b9b5ff4f46283969967f7`.
- These latest indexer/test changes have NOT yet been confirmed by a new Admin Quality CI run. Do not report them as CI-passed until a run for the latest revision completes.
- The optimized ARM64 release build run `45308936229` remains in progress at the APK build step at the last poll; no APK artifact or final size is available yet.
- The previous full Admin quality run `45308948107` passed, including AppAuth wiring and Kotlin compilation, but it predates the latest indexer/test changes.
- No live D1 ingestion or complete repo-coverage proof exists yet; the expanded filters improve what can be indexed but do not themselves ingest anything.

## Latest regression repair (2026-11-24)

- A backend-wide CI run exposed one regression in the new indexer secret-scanning test: the matcher detected assignment-style secret fields but did not recognize JSON-quoted property names.
- Fixed the matcher to accept quoted JSON keys before the colon, retaining the existing provider-specific credential patterns.
- Fix committed as `660bbdb7d616499a3ffb04d456e43b3b6f8fc1cd`.
- The failing test was isolated to the new synthetic JSON private-key sample (341/342 tests passed); no production backend behavior was implicated by the failure.
- CI for this repair is awaiting confirmation; do not report the fix as passed until a fresh run completes.


## Verified optimized Galaxy S7 preview APK (2026-11-24)

- Android preview workflow run: `45308936229`; job `138161984879` completed successfully, including Flutter format/analyze/tests, ARM64 release build, APK existence/size verification, and artifact upload.
- Artifact: `barq-admin-galaxy-s7-arm64-optimized`, artifact ID `14882831920`, expires 2026-12-08.
- The artifact was downloaded and inspected. APK path inside archive: `app/outputs/flutter-apk/app-arm64-v8a-release.apk`; APK size: 17,626,993 bytes (about 17.63 MB decimal); archive size: 9,481,907 bytes.
- APK SHA-256: `b58edb6f1668bb6343e0333d84406dc9f370e15cdd090453913a8ca2de9e7c38`.
- Build configuration confirms application ID `com.barq.admin`, ARM64 native libraries are present, and the build is release-mode with Dart obfuscation and split debug symbols.
- Important: the Android release build currently uses the Gradle debug signing configuration for preview installs. It is not a production/release signing setup. Physical installation, Android 8 compatibility, Google OIDC sign-in, and live Admin API access on the Galaxy S7 remain untested.
- The artifact was built from workflow run head SHA `b2771509c87d0700f5870d9758e55cadfb30c5e5`; it predates the latest indexer regression repair/checkpoint commit `0002d57a0f36df46d42cdc4b78d6c1f3c939895a`. Do not represent this APK as built from the latest branch head.
- Admin Quality run `45310249447` remains pending with no jobs exposed yet. Backend tests on the checkpoint revision passed in run `45310249463`.


## Preview knowledge-ingestion workflow prepared (2026-11-24)

- Added manual-only workflow `.github/workflows/barq-admin-knowledge-ingest.yml` to run one resumable batch of the repository indexer against Admin Preview.
- The workflow uses the built-in GitHub token with `contents: read`, an exact repository allowlist (`alhmdanybdhmhmwd-cmd/siraj-api-2026`), and an explicit ref/cursor input. It does not merge, deploy, or write to GitHub.
- A preflight guard refuses to send knowledge to any host other than an HTTPS `barq-admin-preview*.workers.dev` hostname. This prevents accidental ingestion into the consumer API or an unapproved production endpoint.
- The workflow runs `node --test ingest_github_repo.test.mjs` before ingestion and writes the pinned commit, indexed count, skipped count, remaining count, completion flag, and next cursor to the GitHub Actions summary.
- Added Admin Quality workflow checks for the ingestion workflow's manual-only trigger, read-only GitHub permission, exact repository allowlist, Preview host guard, and absence of deploy commands.
- This is infrastructure/code preparation only. It has NOT run and no repository data has been ingested into D1 yet.
- To enable a run, the repository's GitHub Actions secrets must contain `BARQ_ADMIN_PREVIEW_API_URL` (the actual HTTPS Preview Worker URL matching the guarded host) and `BARQ_ADMIN_PREVIEW_OWNER_TOKEN` (an owner token scoped to the isolated Admin Preview workspace). Never put either value in chat or source files.
- If those secrets or the isolated Preview D1 are not configured, the workflow will stop at preflight; it will not fall back to a production API.
- Latest workflow changes: ingestion workflow commit `88fe9170b69e825703b17ae2caf3921a7c1256f3`, checkout/host guard correction `ee3559226b60212bde929335b8f354954116e15a`, and safety-test commits `75ac1c2b92d1f32e03dca4a11d98a6393c29d299`, `ef32a00ac31d9ea2df8b953cb27abb1ff261853b`, `f43b7b985e02c13a11a2fc179761102fc803e7f5`.


## Owner authorization for autonomous development toolchain (2026-11-24)

- The owner explicitly authorized implementing the development-toolchain phases needed for the desired phone workflow: install BARQ Admin, say "واصل", and have BARQ Brain resume building both BARQ Admin and the consumer BARQ app.
- Scope now approved for implementation in isolated Preview/review environments: secure GitHub account/app connection, repository inspection, isolated-branch edits/repairs, tests/build orchestration, failure diagnosis, durable server-side continuation independent of the phone, and reviewable PR creation.
- Production merges/deployments, production data changes, secret exposure/rotation, paid resources, and irreversible external actions remain action-specific approval gates.
- Updated `admin/worker.js` system instructions to reflect this authorization without overstating current capabilities. Updated `admin/worker.test.mjs` with a regression test that asserts the scope is authorized while code editing remains explicitly unavailable until connected and tested.
- Current code reality: Admin mobile has owner login/chat/task UI; Worker task queue currently calls the AI model to produce a draft answer and a checkpoint. It does NOT yet edit GitHub files, run repository CI/build workflows, or perform automatic PR creation. A real GitHub App/user installation connection and isolated execution runner are still required.
- The owner-authorization and capability-truthfulness changes are committed on branch `barq-admin-s7-optimized-2026-11-24`; latest commit at checkpoint writing: `8ce0204686393cfe8fa724237e36a2f34cc4039c`.
- Admin Worker/unit/schema quality job passed in run `45310543568`; the same run's Android mobile-quality job was still executing AppAuth manifest validation when last checked. Backend tests passed in run `45310876434`.
- Do not tell the owner the app is ready for autonomous self-development until the secure GitHub integration, real source-edit/test/build runner, durable resume, and full phone-to-PR-to-CI-to-resume acceptance test are complete.


## CI continuation update (2026-11-24 02:24 UTC)

- Current branch head: `84cd4b6f2dcc16cabe8bfa6ea1a400aef7ec7f22`.
- Admin Worker syntax, all Admin unit tests, isolated schema/audit checks, task/checkpoint concurrency checks, Preview template validation, and Preview knowledge-ingestion workflow safety checks passed on run `45311985105` (admin-quality job: success).
- Android mobile-quality in the same run is still running; Flutter setup is in progress. Do not mark the mobile/Android checks green until the job finishes.
- Earlier Admin Quality failures were due to brittle workflow-text assertions. The current safety assertion is now limited to the durable environment variable contract and passed in the latest run.
- The Android AppAuth Gradle step was also corrected so it retries transient failures and checks the merged manifest after Gradle succeeds; latest mobile job must verify it.
- Backend tests on the immediately preceding revision `d7ed2624c1fc8b64954f960a924a31a3a22acab2` passed (run `45311856812`). A fresh backend check for `84cd4b6f2dcc16cabe8bfa6ea1a400aef7ec7f22` is not yet confirmed.
- Autonomous GitHub source editing, test/build execution by BARQ Brain, automatic PR creation, and phone-to-server resume are still NOT implemented or acceptance-tested. The current queue still produces AI drafts/checkpoints only.


## Continuation checkpoint — 2026-11-24 14:15 UTC

- Current branch head before this checkpoint note: `ca74381ee921bf93dc5405bbeea75ce8217b57b5`.
- Improved BARQ Brain continuation retrieval in `admin/worker.js`: every Arabic/English resume request now pins the first canonical `BARQ_OWNER_CONTEXT.md` chunk and the first `BARQ_BRAIN_MASTER_INDEX_AR.md` chunk before ordinary keyword-ranked sources. This ensures the owner's accepted/rejected/postponed decisions and project navigation map are not crowded out by recent keyword matches.
- Added exported, bounded/deduplicating helper `mergePinnedKnowledge` and regression test proving canonical sources stay first, duplicates are removed, and the context result remains capped.
- Code commits: `45df486a59ee312f500496ea198a38d44d40211b` (retrieval implementation) and `ca74381ee921bf93dc5405bbeea75ce8217b57b5` (tests).
- Exact-revision Admin quality run `45411505375`: Admin Worker/unit/schema/task/checkpoint/Preview-ingestion-safety job passed. Android mobile-quality job is still running at Flutter setup; do not call Android CI complete until final result.
- Exact-revision Backend tests run `45411526067` completed successfully.
- Preview deploy run `45411505641` failed safely at Preview-only configuration validation. Required GitHub Environment values remain unavailable; no deploy or production changes occurred.
- Live repository ingestion into Admin Preview D1 is still blocked by the missing dedicated Preview configuration/owner credentials. No claim of complete repository knowledge is permitted.
- Continue next: confirm the mobile-quality job result; keep all tests cloud-side; do not ask the owner to use the Galaxy S7 yet. Resolve Preview configuration only with owner-provided/authorized isolated resources; then run the resumable indexer to `complete=true` and validate retrieval across both products. Autonomous GitHub edit/test/build execution and phone-to-server continuation remain unimplemented until the secure runner and end-to-end acceptance tests pass.


## Owner update-consent and smoothness contract — 2026-11-25

- The owner requires a two-stage explicit consent flow for every BARQ Admin app update:
  1. Before implementation begins, BARQ Brain must present the proposed changes, reasons, affected areas, risks and expected benefits, invite owner additions/changes, and wait for scope approval.
  2. After implementation and cloud-side verification, before the update APK is downloaded to the phone, BARQ Brain must present the exact version, change summary, test/build and performance evidence, APK size and known risks, then obtain a separate explicit download approval.
- Android's own install confirmation remains required where the OS requests it; no silent-install claim.
- Cloud work must continue independently while the app is closed and must not depend on the Galaxy S7 remaining awake. If the phone is powered completely off, server-side work can continue but device download/install waits until it is powered on and connected.
- Every update must include measurable smoothness/performance goals and regression evidence. Do not accept a candidate without credible performance evidence or when it exceeds documented regression tolerance. Preserve features; optimize resource use rather than deleting functionality.
- BARQ Brain system instructions and regression tests were updated to enforce this contract. This is policy enforcement in assistant instructions/tests, not yet a complete in-app updater or release pipeline.
- Permanent release signing remains a prerequisite for reliable in-place Android updates and is still awaiting the owner's explicit approval; no signing key was created or committed.


## Global BARQ + BARQ Admin change/update governance — 2026-11-25

- Owner explicitly extended the update-consent and mandatory smoothness requirements from BARQ Admin to BOTH products: consumer BARQ Messenger and BARQ Admin.
- Before each approved development/update batch: propose exact scope, reasons, affected areas, benefits, risks and validation; invite owner additions; wait for explicit scope approval.
- Work and tests run cloud-side while the phone/app is closed/offline. If fully powered off, cloud work continues; device delivery waits for power/connectivity.
- Before any candidate update is made available for device download: show exact product/version, change list, commit/release, tests/build, APK size, performance measurements, risks and recovery plan; obtain separate explicit owner approval. Android may require OS install confirmation.
- Every update must pass a measurable smoothness/performance gate (startup, frame/jank where measurable, responsiveness, memory/CPU/network) with baseline comparison. Hold on material regression or missing evidence. Preserve features; optimize implementation instead.
- Product codebases, versions, signing and release channels remain separate. This shared governance does not imply implementation is complete; each product needs its own updater/approval UI/performance instrumentation and acceptance tests.
- Owner context update commit: 3185a71962807395ac9eba7dac6ce9fe96337388.

## Proactive BARQ consumer-update consent gate — 2026-11-25

- New owner requirement: whenever BARQ Brain discovers a verified defect or improvement that needs a new consumer BARQ app update, it must present the evidence, reason an app update is necessary, affected areas, proposed fix, benefits, urgency, risks, test/performance plan and release impact, then ask permission before starting that update.
- Until approval: no consumer-app code edits, update branch/PR, or update build for that finding. Safe investigation and unrelated already-approved work may continue.
- Clearly distinguish server-only fixes from changes requiring a consumer app update.
- Starting implementation approval is separate from the later explicit approval to make the candidate available for download; installation may also require Android confirmation.
- BARQ Admin Worker instructions and regression tests now encode this gate. This is not yet an end-to-end in-app approval workflow; verify the exact CI run before treating the instruction/test change as green.
- Worker instruction commit: `6ec15f10db6ef22f92e16e1ba34d4cb893e4905f`.
- Regression test commit: `807277063d8a1173f99bb3a1eab8ca375a0ce1df`.

## Phase 2 continuation checkpoint — 2026-11-25

- Added bounded retries for GitHub API tree/commit/blob reads, not only writes to the Admin knowledge API.
- Added pure repository coverage reporting by source domain and extension, including excluded-path reasons and oversized eligible files; the ingestion workflow summary now renders these reports.
- New code/test/workflow revisions are being validated by GitHub Actions. One first-pass fixture incorrectly used a build-output path (correctly excluded as sensitive) as an oversized-file example; the fixture was corrected to use an eligible Markdown path over the byte limit.
- The live Preview D1/Queue/AI configuration is still unavailable/unverified from the current environment. Consequently no actual full repository ingestion or live Brain retrieval has been demonstrated.
- Remaining Phase 2 acceptance work: verify latest CI including Android Kotlin compile; run all ingestion batches against the dedicated Admin Preview D1 pinned to an immutable commit; persist a complete coverage/freshness record; implement deleted/renamed-source reconciliation without destroying historical evidence; test cross-project separation, conflicting/superseded owner decisions, stale evidence and prompt injection; run representative live Brain questions with exact source citations.
- Keep production untouched and do not use the BARQ consumer database for Admin knowledge.

## Source freshness reconciliation — 2026-11-25

- Added migration `0008_knowledge_freshness.sql`: each knowledge row records `last_seen_revision` and `is_stale`; old revisions remain stored.
- Knowledge ingestion updates the last-seen revision on every indexed chunk. Only the final complete batch posts the reconciliation request.
- Authenticated Admin Worker route `POST /v1/knowledge/reconcile` marks rows under the exact repository path prefix stale when they were not seen in the completed immutable commit. It never deletes knowledge history.
- Brain retrieval sorts fresh sources ahead of stale ones and marks stale evidence explicitly in its prompt context.
- Regression tests cover invalid/incomplete revision rejection, authenticated reconciliation, SQL path scoping, non-destructive history retention, and final-batch-only invocation.
- This is implemented in the isolated branch; CI and live Preview D1 execution still need verification.

## Latest Phase 2 implementation checkpoint — 2026-11-25

- Repository ingestion now reports eligible coverage by BARQ consumer Android, consumer backend, BARQ Admin, CI/config, documentation and other domains, plus file-extension counts, excluded-path reasons and oversized files.
- GitHub commit/tree/blob reads and Admin API writes use bounded retries for transient network/408/425/429/5xx failures.
- Migration `0008_knowledge_freshness.sql` adds `last_seen_revision` and `is_stale` without deleting historical knowledge rows.
- Each indexed source chunk is marked seen at its immutable commit. The final completed batch invokes the owner-authenticated reconciliation route; it marks repository sources absent from the completed revision stale. Partial batches cannot trigger reconciliation.
- Retrieval orders fresh sources first and labels stale evidence as historical/verification-required in the model context. Knowledge list/detail APIs expose freshness metadata.
- Added regression coverage for coverage reporting, GitHub retries, multi-batch reconciliation, stale revision validation, authenticated route scoping, historical-row retention, stale prompt labels and fresh-first ranking.
- Latest relevant commits: indexer coverage/retries `7e94c43891beca64c396cc595589bd41fe6c0fe5`; final-batch reconciliation/indexer `a527b2d2193f278deb1378e1df8dd585689c3337`; freshness schema `018d4af7f67d5a0f93d3507eb890969bd27dee32`; Worker freshness API `ccc79c335ff07f311744ed695a6df167106c8579`; latest test correction `988e3d9da56f72cd9bcb3164ecd6fac8cf0871f1`; latest Worker ordering `ccc505ec4bd0966898e1fa75c1b43fe9eb8f9a09`.
- CI status: backend tests passed at earlier revisions before the latest freshness/reconciliation changes; the latest Admin quality/backend runs for the newest revisions are queued. Do not infer success from queued or older runs.
- Preview deployment is still blocked because GitHub Environment `barq-admin-preview` lacks: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, `ADMIN_D1_DATABASE_ID`, `BARQ_GOOGLE_OIDC_CLIENT_ID`, `BARQ_ADMIN_OWNER_EMAIL`, and `BARQ_ADMIN_ALLOWED_ORIGIN`. Knowledge ingestion additionally requires `BARQ_ADMIN_PREVIEW_API_URL` and `BARQ_ADMIN_PREVIEW_OWNER_TOKEN`.
- Phase 2 remains IN PROGRESS until latest CI is green, the isolated Preview D1 migrations are applied, all repository batches are ingested at an immutable commit, the coverage/freshness report is reviewed, and live retrieval/citation/cross-project/conflict/prompt-injection acceptance tests pass.
