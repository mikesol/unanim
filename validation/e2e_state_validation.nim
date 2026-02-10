## validation/e2e_state_validation.nim
## E2E state validation: generates Worker+DO deployment artifacts AND
## a browser test HTML page that exercises the full client <-> DO round-trip.
##
## Compile and run: nim c -r validation/e2e_state_validation.nim
## Outputs:
##   validation/e2e_state_deploy/worker.js + wrangler.toml
##   validation/e2e_state_test/index.html

import ../src/unanim/secret
import ../src/unanim/proxyfetch
import ../src/unanim/codegen
import ../src/unanim/clientgen

# --- Part 1: Artifact generation (compile-time) ---

# Stub proxyFetch so the analyze macro can walk it
proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""

# Register the API call pattern with the analyze macro
analyze:
  discard proxyFetch("https://httpbin.org/post",
    headers = {"Authorization": "Bearer " & secret("test-api-key")},
    body = "test")

# Generate Worker + DO artifacts at compile time
const deployDir = "validation/e2e_state_deploy"
static:
  generateArtifacts("unanim-e2e-state", deployDir)

# --- Part 2: Browser test page generation (compile-time const + runtime write) ---

const workerUrl = "https://unanim-e2e-state.mike-solomon.workers.dev"

const testHtml = "<!DOCTYPE html>\n<html>\n<head><meta charset=\"utf-8\"><title>E2E State Validation</title></head>\n<body>\n<pre id=\"output\"></pre>\n<script>\n" & generateIndexedDBJs() & "\n" & """
const log = (msg) => {
  document.getElementById("output").textContent += msg + "\n";
  console.log(msg);
};

const WORKER_URL = """ & "\"" & workerUrl & "\"" & """;

async function runTests() {
  try {
    // Generate a unique user ID per test run to avoid stale DO data
    const userId = "test-user-" + Date.now();
    log("Test run user ID: " + userId);

    // Test 0: Pre-check for persisted IndexedDB data (proves persistence on refresh)
    await unanimDB.openDatabase();
    const existing = await unanimDB.getAllEvents();
    if (existing.length > 0) {
      log("PASS: persistence confirmed - found " + existing.length + " events from prior session");
      log("All tests complete (persistence verified).");
      return;
    }
    log("PASS: openDatabase succeeded (fresh run)");

    // Test 1: Create 3 test events in IndexedDB
    const events = [
      { sequence: 1, timestamp: new Date().toISOString(), event_type: "user_action", schema_version: 1, payload: '{"action":"click","target":"button-1"}' },
      { sequence: 2, timestamp: new Date().toISOString(), event_type: "api_response", schema_version: 1, payload: '{"status":200,"endpoint":"/data"}' },
      { sequence: 3, timestamp: new Date().toISOString(), event_type: "user_action", schema_version: 1, payload: '{"action":"submit","form":"login"}' }
    ];
    await unanimDB.appendEvents(events);
    log("PASS: appendEvents succeeded (3 events in IndexedDB)");

    // Test 2: POST to /do/proxy with events + API request to httpbin.org
    log("Sending POST to /do/proxy...");
    const proxyBody = {
      events_since: 0,
      events: events,
      request: {
        url: "https://httpbin.org/post",
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer <<SECRET:test-api-key>>"
        },
        method: "POST",
        body: JSON.stringify({ test: "unanim-e2e-state-validation" })
      }
    };

    const proxyResp = await fetch(WORKER_URL + "/do/proxy", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-User-Id": userId
      },
      body: JSON.stringify(proxyBody)
    });

    const proxyData = await proxyResp.json();

    // Test 3: Verify events_accepted is true
    if (proxyData.events_accepted === true) {
      log("PASS: events_accepted is true");
    } else {
      log("FAIL: events_accepted is " + JSON.stringify(proxyData.events_accepted));
      log("  proxy response: " + JSON.stringify(proxyData));
    }

    // Test 4: Verify secret injection worked (httpbin echoes headers back)
    if (proxyData.response && proxyData.response.body) {
      let echoBody;
      try {
        echoBody = JSON.parse(proxyData.response.body);
      } catch (e) {
        echoBody = proxyData.response.body;
      }
      // httpbin echoes headers; the Authorization header should contain the actual secret value,
      // NOT the placeholder. We check it does NOT contain "<<SECRET:" (i.e., injection happened).
      const authHeader = echoBody.headers && (echoBody.headers["Authorization"] || echoBody.headers["authorization"]);
      if (authHeader && !authHeader.includes("<<SECRET:")) {
        log("PASS: secret injection worked (Authorization header resolved)");
        // Additionally check that the secret value is present (it should be "unanim-test-secret" from wrangler)
        if (authHeader.includes("unanim-test-secret")) {
          log("PASS: secret value confirmed (unanim-test-secret found in Authorization)");
        } else {
          log("INFO: Authorization header present but did not find 'unanim-test-secret' — value: " + authHeader);
        }
      } else if (authHeader && authHeader.includes("<<SECRET:")) {
        log("FAIL: secret injection did NOT work (placeholder still present)");
      } else {
        log("WARN: could not find Authorization header in httpbin echo");
        log("  echo body keys: " + JSON.stringify(Object.keys(echoBody || {})));
      }
    } else {
      log("FAIL: no response body from proxy");
      log("  proxyData: " + JSON.stringify(proxyData));
    }

    // Test 5: GET /do/events?since=0 to verify server stored all 3 events
    log("Fetching /do/events?since=0...");
    const eventsResp = await fetch(WORKER_URL + "/do/events?since=0", {
      method: "GET",
      headers: { "X-User-Id": userId }
    });
    const serverEvents = await eventsResp.json();
    if (Array.isArray(serverEvents) && serverEvents.length === 3) {
      log("PASS: server stored 3 events");
    } else {
      log("FAIL: expected 3 server events, got " + (Array.isArray(serverEvents) ? serverEvents.length : JSON.stringify(serverEvents)));
    }

    // Test 6: GET /do/status to verify event_count and latest_sequence
    log("Fetching /do/status...");
    const statusResp = await fetch(WORKER_URL + "/do/status", {
      method: "GET",
      headers: { "X-User-Id": userId }
    });
    const status = await statusResp.json();
    if (status.event_count === 3) {
      log("PASS: status.event_count is 3");
    } else {
      log("FAIL: expected event_count 3, got " + status.event_count);
    }
    if (status.latest_sequence === 3) {
      log("PASS: status.latest_sequence is 3");
    } else {
      log("FAIL: expected latest_sequence 3, got " + status.latest_sequence);
    }

    // Test 7: Send a 4th event via /do/proxy to test sequence continuity
    log("Sending 4th event (sequence 4) via /do/proxy...");
    const event4 = { sequence: 4, timestamp: new Date().toISOString(), event_type: "navigation", schema_version: 1, payload: '{"page":"/dashboard"}' };
    await unanimDB.appendEvents([event4]);
    const proxy4Body = {
      events_since: 3,
      events: [event4],
      request: {
        url: "https://httpbin.org/post",
        headers: { "Content-Type": "application/json" },
        method: "POST",
        body: JSON.stringify({ test: "event-4-continuity" })
      }
    };
    const proxy4Resp = await fetch(WORKER_URL + "/do/proxy", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-User-Id": userId
      },
      body: JSON.stringify(proxy4Body)
    });
    const proxy4Data = await proxy4Resp.json();
    if (proxy4Data.events_accepted === true) {
      log("PASS: 4th event accepted (sequence continuity works)");
    } else {
      log("FAIL: 4th event not accepted: " + JSON.stringify(proxy4Data));
    }

    // Test 8: Send a duplicate event (sequence 1) to verify 409 rejection
    log("Sending duplicate event (sequence 1) via /do/proxy...");
    const dupEvent = { sequence: 1, timestamp: new Date().toISOString(), event_type: "user_action", schema_version: 1, payload: '{"action":"duplicate"}' };
    const dupBody = {
      events_since: 0,
      events: [dupEvent],
      request: {
        url: "https://httpbin.org/post",
        headers: { "Content-Type": "application/json" },
        method: "POST",
        body: JSON.stringify({ test: "duplicate-should-fail" })
      }
    };
    const dupResp = await fetch(WORKER_URL + "/do/proxy", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-User-Id": userId
      },
      body: JSON.stringify(dupBody)
    });
    if (dupResp.status === 409) {
      log("PASS: duplicate event rejected with 409");
    } else {
      const dupData = await dupResp.json();
      log("FAIL: expected 409 for duplicate, got " + dupResp.status + ": " + JSON.stringify(dupData));
    }

    // Verify final state
    log("Fetching final /do/status...");
    const finalStatusResp = await fetch(WORKER_URL + "/do/status", {
      method: "GET",
      headers: { "X-User-Id": userId }
    });
    const finalStatus = await finalStatusResp.json();
    if (finalStatus.event_count === 4) {
      log("PASS: final event_count is 4");
    } else {
      log("FAIL: expected final event_count 4, got " + finalStatus.event_count);
    }
    if (finalStatus.latest_sequence === 4) {
      log("PASS: final latest_sequence is 4");
    } else {
      log("FAIL: expected final latest_sequence 4, got " + finalStatus.latest_sequence);
    }

    log("");
    log("=== PERSISTENCE TEST ===");
    log("Refresh this page. If IndexedDB events persist, you will see them below.");
    log("Events currently stored in IndexedDB: " + (await unanimDB.getAllEvents()).length);
    log("All tests complete.");
  } catch (e) {
    log("ERROR: " + e.message);
    console.error(e);
  }
}

runTests();
</script>
</body>
</html>"""

# --- Part 3: Runtime file output ---

import std/os

# Write browser test page
let testOutputDir = getCurrentDir() / "validation" / "e2e_state_test"
createDir(testOutputDir)
writeFile(testOutputDir / "index.html", testHtml)

echo "Deployment artifacts generated in: " & deployDir
echo "  - " & deployDir & "/worker.js"
echo "  - " & deployDir & "/wrangler.toml"
echo ""
echo "Browser test page generated at: " & testOutputDir & "/index.html"
echo "Open in browser to run E2E state validation tests."
echo "Refresh to verify IndexedDB persistence."
