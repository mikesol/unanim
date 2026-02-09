# Phase 1: End-to-End Validation Log

**Date:** 2026-02-09
**Issue:** #6 — End-to-end validation: deploy to Cloudflare, verify round-trip

## Environment

- Nim: 2.2.6 (Linux amd64)
- Node: v22.14.0
- Wrangler: 4.59.2
- OS: Linux 6.17.9-76061709-generic (Pop!_OS)
- Cloudflare Account: mike.solomon@hey.com

## Step 1: Codegen

Compiled `validation/e2e_codegen.nim` which uses the framework macros (`secret()`, `analyze`, `generateArtifacts`) to produce artifacts at compile time.

```
$ nim c -r validation/e2e_codegen.nim
Artifacts generated in validation/deploy
```

Generated files:
- `validation/deploy/worker.js` — Cloudflare Worker (ES modules format) with secret injection
- `validation/deploy/wrangler.toml` — Deployment config for `unanim-e2e-test`

Syntax validation:
```
$ node --check validation/deploy/worker.js
(no errors)
```

## Step 2: Deployment

```
$ cd validation/deploy && npx wrangler deploy
Total Upload: 3.07 KiB / gzip: 0.99 KiB
Uploaded unanim-e2e-test (5.52 sec)
Deployed unanim-e2e-test triggers (4.01 sec)
  https://unanim-e2e-test.mike-solomon.workers.dev
Current Version ID: 421fb5d4-d751-4cbb-8f1e-600123b49ae6
```

## Step 3: Secret Configuration

```
$ echo "unanim-test-secret-12345" | npx wrangler secret put TEST_API_KEY
Creating the secret for the Worker "unanim-e2e-test"
Success! Uploaded secret TEST_API_KEY
```

## Step 4: Curl Verification

### Secret injection test

```
$ curl -s -X POST https://unanim-e2e-test.mike-solomon.workers.dev \
  -H "Content-Type: application/json" \
  -d '{"url":"https://httpbin.org/anything","headers":{"Authorization":"Bearer <<SECRET:test-api-key>>","X-Custom":"no-secret-here"},"requestBody":"hello from unanim"}'
```

Response (httpbin echoes headers back):
```json
{
  "headers": {
    "Authorization": "Bearer unanim-test-secret-12345",
    "X-Custom": "no-secret-here"
  },
  "data": "hello from unanim",
  "method": "POST",
  "url": "https://httpbin.org/anything"
}
```

- `Authorization` contains the real secret value (`unanim-test-secret-12345`), NOT the placeholder
- `X-Custom` passed through unchanged
- Request body forwarded correctly

### CORS preflight test

```
$ curl -s -X OPTIONS https://unanim-e2e-test.mike-solomon.workers.dev \
  -H "Origin: http://localhost:8080" \
  -H "Access-Control-Request-Method: POST" -D - -o /dev/null

HTTP/2 204
access-control-allow-origin: *
access-control-allow-headers: Content-Type
access-control-allow-methods: POST, OPTIONS
```

## Step 5: Browser Validation

Served `validation/client/index.html` via `npx serve -l 8080 .` and opened in Chrome.

### Results

| Check | Status | Detail |
|-------|--------|--------|
| Response received | PASS | Status: 200 |
| Secret injected by Worker | PASS | Authorization: Bearer unanim-test-secret-12345 |
| No secret placeholder leaked | PASS | Clean |
| Non-secret header preserved | PASS | X-Custom: no-secret-here |
| Request body forwarded | PASS | Body: hello from unanim e2e test |

**Round-trip latency:** 574.2ms (client -> Cloudflare Worker -> httpbin.org -> Worker -> client)

Screenshot: `validation/e2e-browser-test.png`

## Step 6: Latency Breakdown

Total round-trip: **574.2ms**

This includes:
- Browser -> Cloudflare edge (CDG datacenter)
- Worker execution + secret injection
- Worker -> httpbin.org (AWS-hosted)
- httpbin.org response -> Worker
- Worker -> Browser

This is the baseline. No optimization was attempted (per issue scope).

## Conclusion

**Phase 1 end-to-end validation: PASSED**

The complete pipeline works against real infrastructure:
1. Nim compile-time macros (`secret()`, `analyze`) correctly register secrets and API routes
2. `generateArtifacts` produces a valid, deployable Cloudflare Worker with secret injection
3. The Worker correctly replaces `<<SECRET:name>>` placeholders with environment variables
4. Non-secret headers and request bodies pass through unchanged
5. No secret values leak to the client
6. CORS preflight works for browser-based clients

## Issues Encountered

1. **Cloudflare API transient error** — First `wrangler deploy` returned "Service unavailable [code: 7010]". Retry succeeded immediately.
2. **CORS not in initial codegen** — `generateWorkerJs` didn't include CORS headers. Added OPTIONS preflight handler and `Access-Control-Allow-Origin: *` to all responses before browser testing.
