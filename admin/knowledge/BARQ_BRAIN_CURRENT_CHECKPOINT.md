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
