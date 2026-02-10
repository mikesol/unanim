# Phase 3: Sync — Design Document

**Date:** 2026-02-10
**Phase:** 3 (Sync — Lean)
**Builds on:** Phase 2 (State) — all 5 issues merged (#13-#17)

## Goal

Wire together the Phase 2 building blocks (client IndexedDB, server DO SQLite, proxyFetch with sequence verification) into a working bidirectional sync protocol. Client automatically creates events, attaches deltas to proxyFetch calls, handles 409 reconciliation, and queues events when offline.

## Architecture

Phase 3 adds a **sync glue layer** between existing pieces. No new Nim library modules — this is changes to `codegen.nim` (DO JS generation) and `clientgen.nim` (client JS generation), plus a reference app and CI size budgets.

**What Phase 3 does NOT include (deferred to Phase 3b):** WebSocket channel, three-layer lease mechanism, fencing tokens, server takeover during offline, sendBeacon/Background Sync secondary channels, `navigator.storage.persist()`. See "Phase 3b: Real-Time & Lease" section below and VISION.md updates for rationale.

## The Client Sync Layer (`unanimSync`)

A generated JavaScript module (like `unanimDB`) that sits between the app's proxyFetch calls and the network.

### proxyFetch flow with sync

```text
App calls proxyFetch("https://api.openai.com/...", {headers, body})
    │
    ▼
unanimSync.proxyFetch(url, options)
    │
    ├─ 1. Read last synced sequence from IndexedDB
    ├─ 2. Get events since that sequence (the delta)
    ├─ 3. Build request: {events_since, events: [...delta], request: {url, headers, body}}
    ├─ 4. POST to /do/proxy with X-User-Id header
    │
    ▼
Response received
    │
    ├─ 200 + events_accepted: true
    │   ├─ Update last synced sequence
    │   ├─ Store any server_events in IndexedDB
    │   └─ Return API response to app
    │
    ├─ 409 + events_accepted: false
    │   ├─ Store server_events in IndexedDB (server is authoritative)
    │   ├─ Update last synced sequence to server's latest
    │   ├─ Retry the proxyFetch with corrected delta
    │   └─ Return API response to app (after retry succeeds)
    │
    └─ Network error (offline)
        ├─ Events remain in IndexedDB (already stored locally)
        ├─ Mark request as failed
        └─ Return a rejected promise with {offline: true, queued: true}
```

### Last synced sequence tracking

The client tracks which events the server has seen via a single number stored in IndexedDB (in a separate object store or a metadata key). On successful sync, it advances to the highest sequence acknowledged. On 409, it resets to the server's latest.

### 409 reconciliation

Server wins, always. When the server rejects:
1. Accept server_events as truth (store them in IndexedDB)
2. Advance last synced sequence to server's latest (conflicting local events are superseded — they remain in IndexedDB but fall below the sync marker, so they won't be re-sent)
3. Retry the proxyFetch with a corrected delta

This matches VISION.md: "the server is always authoritative."

### Offline queue

Deliberately simple: queue events locally, retry on reconnect. No lease detection, no server takeover, no background sync API.

1. User takes action → event created in IndexedDB (always succeeds)
2. App calls proxyFetch → sync layer tries network call
3. Network fails → rejected promise with `{offline: true, queued: true}`
4. User keeps working → more events accumulate in IndexedDB
5. Network returns → next proxyFetch carries full delta of queued events
6. Server verifies batch → if sequences valid, all queued events accepted

**Events are always queued. API calls are NOT queued.** The failure is part of the user's story — they saw "offline," adjusted their behavior, kept working. Their post-failure events reflect adjusted context. Replaying pre-failure API calls would rewrite history from a context that no longer exists. On reconnect, events flush via `/do/sync` (no API call). The app re-triggers specific API calls if still relevant.

**Not handled (deferred to Phase 3b):**
- Tab close while offline (sendBeacon)
- Safari 7-day eviction (navigator.storage.persist)
- Server processing webhooks during offline (requires lease)

## DO Changes

### Bidirectional server_events

The `/do/proxy` endpoint currently returns `server_events: []`. Phase 3 makes this real: after storing client events, the DO queries for events the client hasn't seen (sequence > `events_since` that weren't in the client's batch). For now this is an empty set (no webhook/cron generating server-side events yet), but the plumbing is ready for Phase 3b.

### New endpoint: `POST /do/sync`

A lightweight sync-only endpoint — identical to `/do/proxy` but without API forwarding. Request body:

```json
{
  "events_since": 1023,
  "events": [...]
}
```

Response identical to `/do/proxy` but `response` is always `null`. Used for:
- Flushing local events without an API call
- Pulling missed server events
- Reconnect: flush queued events before resuming normal proxyFetch

## Reference App: Todo

Minimal Todo app exercising the sync protocol:

| Capability | How Todo uses it |
|---|---|
| Event creation | Each add/toggle/delete is an event |
| proxyFetch with sync | "Save to cloud" triggers proxyFetch with event delta |
| 409 reconciliation | Two tabs, create events in both, sync — one gets 409 |
| Offline queue | Airplane mode, add todos, come back, events flush |
| IndexedDB persistence | Refresh page, todos still there |
| Server persistence | Clear IndexedDB, sync from server, todos restored |

The Todo app is a benchmark vehicle. Performance measurements:
- Bundle size: generated JS against Section 8.2 budgets
- Proxy overhead: proxyFetch round-trip vs direct fetch
- CI: gzipped sizes checked against budgets, warn on exceed

## CI Size Budget Warnings

Per VISION.md Section 8.4, Phase 3 introduces size budgets as CI warnings:

| Artifact | Budget (gzipped) |
|---|---|
| Worker JS (framework overhead) | 5 KiB |
| IndexedDB wrapper | 3 KiB |
| HTML shell | 2 KiB |
| Per-route client JS (framework overhead) | 2 KiB |

A script measures `gzip -c <artifact> | wc -c` and compares against budgets. Warnings on PRs touching `codegen` or `clientgen`. Not failures — that's Phase 4.

## Issue Breakdown

### Issue F: VISION.md Phase 3/3b split + assumption flags
- Update Section 14 build order
- Add Phase 3b description
- Add assumption validation markers to Sections 4.3, 4.9, 9.6
- No code changes

### Issue A: Client sync layer generation (`unanimSync`)
- Add `generateSyncJs()` to `clientgen.nim`
- Generates: proxyFetch wrapper, delta attachment, 200/409/error handling
- Tracks last synced sequence in IndexedDB
- Offline queue: events stored locally, API calls rejected when offline
- Unit tests for generated JS structure

### Issue B: DO bidirectional events + `/do/sync` endpoint
- Modify `generateDurableObjectJs()` in `codegen.nim`
- `/do/proxy` returns missed server_events
- New `/do/sync` endpoint for event-only exchange
- Unit tests for generated JS

### Issue C: Todo reference app
- Nim source using proxyFetch + events for add/toggle/delete
- Generates Worker+DO + client HTML+JS with unanimSync + unanimDB
- Deploy to Cloudflare, validate in browser
- Measure bundle sizes and proxy overhead

### Issue D: CI size budget warnings
- Script measuring gzipped artifact sizes
- Compare against Section 8.2 budgets
- Warn on exceed (Phase 3 enforcement level)
- Runs on PRs touching codegen/clientgen

### Issue E: E2E sync validation
- Browser-based validation against real Cloudflare
- Tests: event sync, 409 reconciliation, offline queue + flush, persistence
- Airplane mode test

### Dependency order

```text
F (spec update)
├─ A (client sync layer)     ─┐
├─ B (DO bidirectional + sync) ├─ C (Todo app) ─── D (CI budgets)
└──────────────────────────────┘                 └─ E (E2E validation)
```

F first. A and B are independent (parallel). C needs both A and B. D and E need C.

## Phase 3b: Real-Time & Lease (deferred)

What Phase 3b would add on top of lean Phase 3:

- **WebSocket channel to DO** — hibernated connection, server→client push, proxyFetch-over-WebSocket
- **Three-layer lease mechanism** — proxyFetch renewal, WebSocket auto-response, DO Alarm timeout
- **Fencing tokens** — monotonic token per lease transfer, stale-writer prevention
- **Server takeover** — process webhooks/crons while client offline, generate events
- **sendBeacon** — flush events on tab close/visibilitychange
- **Background Sync API** — retry failed syncs when connectivity returns (Chrome)
- **`navigator.storage.persist()`** — protect IndexedDB from eviction

Phase 3b depends on Phase 3 working correctly. If Phase 3 reveals that the sync protocol has fundamental issues (bad latency, budget overruns, reconciliation UX problems), Phase 3b's design may need to change.

## Assumptions to Validate

These assumptions are flagged in VISION.md and must be validated during Phase 3:

1. **proxyFetch overhead < 20ms** — Measure real round-trip with event delta vs without. If overhead is significant, consider separate sync endpoint vs piggybacking.

2. **409 reconciliation UX** — Does "server wins, discard local events" produce acceptable UX? Or does it need explicit conflict UI?

3. **IndexedDB write latency** — Every user action writes to IndexedDB before proxyFetch. If this adds perceptible lag, consider in-memory buffer with async flush.

4. **Sync glue fits 2 KiB budget** — Measure the generated unanimSync code. If it exceeds budget, either adjust budget (spec-change) or lazy-load sync code.

5. **proxyFetch-only sync is sufficient** — Without heartbeat/visibilitychange, purely-local sessions never sync. If users lose data from tab close without proxyFetch, pull heartbeat into Phase 3.

6. **Simple offline queue works** — Without lease, server can't process webhooks while client is away. If real apps need this, Phase 3b becomes urgent.
