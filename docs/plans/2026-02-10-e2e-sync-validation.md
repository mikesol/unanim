# E2E Sync Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Browser-based E2E validation of the sync protocol against real Cloudflare, exercising event sync, 409 reconciliation, offline queue, and persistence.

**Architecture:** Single Nim file (`validation/e2e_sync_validation.nim`) following the `e2e_state_validation.nim` pattern — compile-time artifact generation, plus a browser test page that runs 8 automated test scenarios against the deployed `unanim-todo` Worker. Chrome DevTools MCP for validation.

**Tech Stack:** Nim (compile-time codegen), JavaScript (browser tests), Cloudflare Workers + Durable Objects, Chrome DevTools MCP

---

### Task 1: Create e2e_sync_validation.nim with all test scenarios

**Files:**
- Create: `validation/e2e_sync_validation.nim`

**Step 1: Write the Nim source**

The file follows the e2e_state_validation.nim pattern:
- Part 1: Compile-time artifact generation (reuse existing pattern)
- Part 2: HTML test page with 8 automated test scenarios
- Part 3: Runtime file output

Uses the already-deployed `unanim-todo` Worker (from #28). Each test run uses a unique `X-User-Id` to avoid stale DO data.

Test scenarios in the generated HTML:
1. Event creation + proxyFetch sync — create 3 events, sync via proxyFetch, verify server received them
2. Bidirectional sync — verify server_events returned in response
3. 409 reconciliation — send events with wrong sequence, verify 409, verify client reconciles
4. Sync-only endpoint — call unanimSync.sync(), verify events flushed
5. Offline queue — override fetch to simulate network failure, verify events buffered, restore, verify flush
6. Client persistence — verify events survive page load (checked at start)
7. Server persistence — query /do/status and /do/events, verify server has all events
8. Sequence continuity after reconnect — after offline flush, verify subsequent syncs work

Each test logs PASS/FAIL with timing. Latency measurements for assumption validation.

**Step 2: Compile**

Run: `cd /home/mikesol/Documents/GitHub/unanim/unanim-30 && ~/.nimble/bin/nim c -r validation/e2e_sync_validation.nim`

**Step 3: Commit**

```bash
git add validation/e2e_sync_validation.nim
git commit -m "feat(#30): add E2E sync validation with 8 test scenarios"
```

---

### Task 2: Deploy artifacts and browser validation

**Step 1: Deploy (if needed — may reuse unanim-todo)**

Verify `unanim-todo` Worker is still deployed and responding.

**Step 2: Serve test page and run in Chrome**

```bash
cd validation/e2e_sync_test && python3 -m http.server 8092
```

Open in Chrome, watch tests run automatically.

**Step 3: Take screenshot**

**Step 4: Commit generated files**

```bash
git add validation/e2e_sync_test/ validation/e2e_sync_deploy/
git commit -m "feat(#30): add generated sync validation artifacts"
```

---

### Task 3: Write validation log and finalize

**Step 1: Write validation log**

Create `validation/VALIDATION_LOG_SYNC.md` with:
- All 8 test results (PASS/FAIL)
- Latency measurements
- Assumption validation findings (5 assumptions from design doc)
- Screenshot reference

**Step 2: Run nimble test**

**Step 3: Commit and create PR**
