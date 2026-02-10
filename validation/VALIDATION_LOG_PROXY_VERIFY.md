# Proxy Verification Validation Log

**Date:** 2026-02-10
**Issue:** #15 — Event log verification at proxyFetch boundary
**Worker URL:** https://unanim-e2e-proxy.mike-solomon.workers.dev

## Test Events

Generated via `validation/gen_test_events.nim` using Nim's `eventlog` module (nimcrypto SHA-256).

Event 1:
```json
{"sequence":1,"timestamp":"2026-02-10T08:22:57Z","event_type":"user_action","schema_version":1,"payload":"{\"action\":\"click\"}","state_hash_after":"e4ede6386b82cf65e0df9933c57448ff9710728d5f326d452d6c5ca0ef4e94d0","parent_hash":"0000000000000000000000000000000000000000000000000000000000000000"}
```

Event 2 (chains from event 1):
```json
{"sequence":2,"timestamp":"2026-02-10T08:22:57Z","event_type":"api_response","schema_version":1,"payload":"{\"status\":200}","state_hash_after":"58e9921f14fe2632e89380e51061e581441ba79c3d7590f092d8e52a4a0f97b9","parent_hash":"6a1908d86d6db085285ccb068510ca8991798946452a9b5e4f46c6ce2cbd3c86"}
```

## Test 1: Valid chain — event stored, API forwarded

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-user-1" \
  -d '{"events_since":0,"events":[{"sequence":1,"timestamp":"2026-02-10T08:22:57Z","event_type":"user_action","schema_version":1,"payload":"{\"action\":\"click\"}","state_hash_after":"e4ede6386b82cf65e0df9933c57448ff9710728d5f326d452d6c5ca0ef4e94d0","parent_hash":"0000000000000000000000000000000000000000000000000000000000000000"}],"request":{"url":"https://httpbin.org/post","headers":{"Authorization":"Bearer <<SECRET:test-api-key>>","Content-Type":"application/json"},"method":"POST","body":"hello from proxy verify"}}'
```

**Result:** `events_accepted: true`, httpbin echoed `Authorization: Bearer unanim-test-secret-12345` (secret injected correctly).

## Test 2: Valid chain continuation — event 2 chains from stored event 1

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-user-1" \
  -d '{"events_since":1,"events":[{"sequence":2,"timestamp":"2026-02-10T08:22:57Z","event_type":"api_response","schema_version":1,"payload":"{\"status\":200}","state_hash_after":"58e9921f14fe2632e89380e51061e581441ba79c3d7590f092d8e52a4a0f97b9","parent_hash":"6a1908d86d6db085285ccb068510ca8991798946452a9b5e4f46c6ce2cbd3c86"}],"request":{"url":"https://httpbin.org/post","headers":{"Content-Type":"application/json"},"method":"POST","body":"event 2 chained"}}'
```

**Result:** `events_accepted: true`. Anchor hash correctly computed from stored event 1 via `hashEvent(full_event)`.

## Test 3: Tampered chain (wrong state_hash_after) — rejected with 409

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-user-2" \
  -d '{"events_since":0,"events":[{"sequence":1,"timestamp":"2026-02-10T12:00:00Z","event_type":"user_action","schema_version":1,"payload":"{\"action\":\"click\"}","state_hash_after":"abc123","parent_hash":"0000000000000000000000000000000000000000000000000000000000000000"}],"request":{"url":"https://httpbin.org/post","headers":{},"body":"should not reach"}}'
```

**Result:** `{"events_accepted":false,"error":"Event 1: state_hash_after mismatch. Expected 9d5be2919bea536c..., got abc123...","failed_at":0,"server_events":[],"response":null}` (HTTP 409). API call NOT forwarded.

## Test 4: Tampered chain (wrong parent_hash) — rejected with 409

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-user-3" \
  -d '{"events_since":0,"events":[{"sequence":1,"timestamp":"2026-02-10T12:00:00Z","event_type":"user_action","schema_version":1,"payload":"{\"action\":\"click\"}","state_hash_after":"abc123","parent_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}],"request":{"url":"https://httpbin.org/post","headers":{},"body":"should not reach"}}'
```

**Result:** `{"events_accepted":false,"error":"Event 1: parent_hash mismatch. Expected 0000000000000000..., got aaaaaaaaaaaaaaaa...","failed_at":0,"server_events":[],"response":null}` (HTTP 409).

## Test 5: Events persisted after valid proxy calls

```bash
curl -s "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/events?since=0" -H "X-User-Id: test-user-1"
```

**Result:** Both events returned with correct hashes matching Nim-generated values.

```bash
curl -s "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/status" -H "X-User-Id: test-user-1"
```

**Result:** `{"event_count":2,"latest_sequence":2}`

## Test 6: User isolation — rejected events not stored

```bash
curl -s "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/events?since=0" -H "X-User-Id: test-user-2"
```

**Result:** `[]` — tampered events were not stored.

## Test 7: Proxy with no events — just API forwarding

```bash
curl -s -X POST "https://unanim-e2e-proxy.mike-solomon.workers.dev/do/proxy" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: test-user-4" \
  -d '{"events_since":0,"events":[],"request":{"url":"https://httpbin.org/post","headers":{"Authorization":"Bearer <<SECRET:test-api-key>>"},"method":"POST","body":"no events, just proxy"}}'
```

**Result:** `events_accepted: true`, httpbin echoed `Authorization: Bearer unanim-test-secret-12345`. Works without events.

## Cross-platform hash compatibility

Verified that the JS Web Crypto API (in Cloudflare DO) produces the same SHA-256 hashes as Nim's nimcrypto library:

- Nim generates events with hashes computed by nimcrypto
- JS DO verifies those same hashes using Web Crypto API `crypto.subtle.digest("SHA-256", ...)`
- Both use identical canonical form: `sequence|timestamp|event_type|schema_version|payload|state_hash_after|parent_hash`
- Event 1 generated by Nim was accepted by JS verification — hashes match cross-platform

## Bug found and fixed

During validation preparation, discovered a hash chain verification bug:

- `hashEvent(event)` was zeroing `state_hash_after` before hashing, but Nim's `hashEvent` hashes the full canonical form (including populated `state_hash_after`)
- `verifyChain` was using `event.state_hash_after` as the next expected `parent_hash`, but Nim sets `parent_hash = hashEvent(previous)` which is the hash of the FULL event
- Fix: split into `hashEvent` (hashes as-is) and `computeStateHash` (zeros state_hash_after first); anchor hash computed via `hashEvent(full_event)` not `state_hash_after`
- Committed as `fix(#15): correct hash chain verification in DO`

## Summary

All 7 tests passed. The `/proxy` endpoint:
1. Verifies event hash chain integrity (cross-platform Nim <-> JS)
2. Rejects tampered events with 409 and structured error
3. Does NOT forward API calls when chain is invalid
4. Stores verified events in SQLite
5. Injects secrets from Worker env into API requests
6. Works with empty event arrays (pure proxy mode)
7. Maintains user isolation via Durable Objects
