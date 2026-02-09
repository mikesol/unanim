# Issue #14 Validation Log: Durable Object with SQLite Storage

## Deployment

- Worker: `unanim-e2e-do`
- URL: `https://unanim-e2e-do.mike-solomon.workers.dev`
- Version: `119faf23-2872-4fc9-8a23-279dc52d020b`
- Edge: CDG (Paris)

## Key finding: `new_sqlite_classes` required

Initial deployment used `new_classes` in `[[migrations]]`. Cloudflare returned error 1101:

> This Durable Object is not backed by SQLite storage, so the SQL API is not available.
> SQL can be enabled on a new Durable Object class by using the `new_sqlite_classes`
> instead of `new_classes` under `[[migrations]]` in your wrangler.toml

Fixed by changing `new_classes` to `new_sqlite_classes`. Had to delete and recreate the Worker since an existing DO class cannot be converted to SQLite.

## Test results

### Test 1: Store events (POST /do/events)

```
curl -X POST .../do/events -H "X-User-Id: test-user-1" \
  -d '[{"sequence":1,...}]'
→ {"stored":1}
```

### Test 2: Retrieve events (GET /do/events?since=0)

```
curl ".../do/events?since=0" -H "X-User-Id: test-user-1"
→ [{"sequence":1,"timestamp":"2026-02-09T12:00:00Z","event_type":"user_action",
    "schema_version":1,"payload":"{\"action\":\"click\"}",
    "state_hash_after":"abc123",
    "parent_hash":"0000000000000000000000000000000000000000000000000000000000000000"}]
```

### Test 3: Status (GET /do/status)

```
curl .../do/status -H "X-User-Id: test-user-1"
→ {"event_count":1,"latest_sequence":1}
```

### Test 4: Store second event

```
curl -X POST .../do/events -H "X-User-Id: test-user-1" \
  -d '[{"sequence":2,"event_type":"api_response",...}]'
→ {"stored":1}
```

### Test 5: Since filter (GET /do/events?since=1)

```
curl ".../do/events?since=1" -H "X-User-Id: test-user-1"
→ [{"sequence":2,...}]   (only event 2 returned)
```

### Test 6: User isolation

```
curl .../do/status -H "X-User-Id: test-user-2"
→ {"event_count":0,"latest_sequence":0}
```

Different user ID maps to different DO instance with empty state.

### Test 7: Proxy route still works

```
curl -X POST .../  -d '{"url":"https://httpbin.org/post",
  "headers":{"Authorization":"Bearer <<SECRET:test-api-key>>"},...}'
→ Auth: Bearer unanim-test-secret-12345
→ Body: hello from DO e2e
```

Secret injection and proxy forwarding unaffected by DO addition.

## All acceptance criteria met

- [x] `generateDurableObjectJs` produces valid JS for a DO class
- [x] DO creates SQLite table for events on first access
- [x] Events can be stored and retrieved via the DO API
- [x] `generateWranglerToml` includes DO bindings (with `new_sqlite_classes`)
- [x] Router Worker forwards requests to the correct DO
- [x] Deploy to real Cloudflare, store events, retrieve events (persistence verified)
- [x] `node --check` passes on generated JS
- [x] All existing tests still pass (23 codegen tests, 8 test suites)
