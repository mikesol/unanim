# Proxy Verification Validation Log

**Date:** 2026-02-10
**Issue:** #15 — Event log verification at proxyFetch boundary
**Spec-change:** #21 — Removed hash chain, simplified to sequence continuity
**Worker URL:** https://unanim-e2e-proxy.mike-solomon.workers.dev

## Test 1: Valid event — stored, API forwarded, secret injected

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-seq-v2-user1" \
  -d '{"events_since":0,"events":[{"sequence":1,"timestamp":"2026-02-10T14:00:00Z","event_type":"user_action","schema_version":1,"payload":"{\"action\":\"click\"}"}],"request":{"url":"https://httpbin.org/post","headers":{"Authorization":"Bearer <<SECRET:test-api-key>>","Content-Type":"application/json"},"method":"POST","body":"hello from simplified proxy"}}'
```

**Result:** `events_accepted: true`, httpbin echoed `Authorization: Bearer unanim-test-secret-12345` (secret injected correctly).

## Test 2: Chain continuation — event 2 chains from stored event 1

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-seq-v2-user1" \
  -d '{"events_since":1,"events":[{"sequence":2,"timestamp":"2026-02-10T14:01:00Z","event_type":"api_response","schema_version":1,"payload":"{\"status\":200}"}],"request":{"url":"https://httpbin.org/post","headers":{"Content-Type":"application/json"},"method":"POST","body":"event 2 chained"}}'
```

**Result:** `events_accepted: true`. Sequence 2 correctly follows stored sequence 1.

## Test 3: Sequence gap (wrong sequence) — rejected with 409

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-seq-v2-user2" \
  -d '{"events_since":0,"events":[{"sequence":5,"timestamp":"2026-02-10T14:00:00Z","event_type":"user_action","schema_version":1,"payload":"{\"action\":\"click\"}"}],"request":{"url":"https://httpbin.org/post","headers":{},"body":"should not reach"}}'
```

**Result:** `{"events_accepted":false,"error":"Sequence gap: expected 1, got 5","server_events":[],"response":null}` (HTTP 409). API call NOT forwarded.

## Test 4: Duplicate sequence (replay) — rejected with 409, server_events returned

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-seq-v2-user1" \
  -d '{"events_since":0,"events":[{"sequence":1,"timestamp":"2026-02-10T14:00:00Z","event_type":"user_action","schema_version":1,"payload":"{\"action\":\"replay\"}"}],"request":{"url":"https://httpbin.org/post","headers":{},"body":"replay attempt"}}'
```

**Result:** `{"events_accepted":false,"error":"Sequence gap: expected 3, got 1","server_events":[...2 events...]}` (HTTP 409). Server returns stored events for client reconciliation. API call NOT forwarded.

## Test 5: Events persisted after valid proxy calls

```bash
curl -s "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/events?since=0" -H "X-User-Id: test-seq-v2-user1"
```

**Result:** Both events returned with correct sequences (1, 2) and 5-field format (no hash fields).

```bash
curl -s "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/status" -H "X-User-Id: test-seq-v2-user1"
```

**Result:** `{"event_count":2,"latest_sequence":2}`

## Test 6: User isolation — rejected events not stored

```bash
curl -s "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/events?since=0" -H "X-User-Id: test-seq-v2-user2"
```

**Result:** `[]` — events with sequence gaps were not stored.

## Test 7: Proxy with no events — just API forwarding

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-seq-v2-user3" \
  -d '{"events_since":0,"events":[],"request":{"url":"https://httpbin.org/post","headers":{"Authorization":"Bearer <<SECRET:test-api-key>>"},"method":"POST","body":"no events, just proxy"}}'
```

**Result:** `events_accepted: true`, httpbin echoed `Authorization: Bearer unanim-test-secret-12345`. Works without events.

## Summary

All 7 tests passed. The `/proxy` endpoint with simplified sequence continuity (spec-change #21):
1. Verifies event sequence continuity (no gaps, no duplicates)
2. Rejects sequence gaps with 409 and structured error
3. Rejects replay/duplicate sequences with 409, returns server_events for reconciliation
4. Does NOT forward API calls when sequence check fails
5. Stores verified events in SQLite (5-field format, no hashes)
6. Injects secrets from Worker env into API requests
7. Works with empty event arrays (pure proxy mode)
8. Maintains user isolation via Durable Objects
