## End-to-end validation: IndexedDB event storage in real browser.
## Generates an HTML file that exercises all IndexedDB operations.
import ../src/unanim/clientgen

const testHtml = "<!DOCTYPE html>\n<html>\n<head><meta charset=\"utf-8\"><title>IndexedDB Test</title></head>\n<body>\n<pre id=\"output\"></pre>\n<script>\n" & generateIndexedDBJs() & "\n" & """
const log = (msg) => {
  document.getElementById("output").textContent += msg + "\n";
  console.log(msg);
};

async function runTests() {
  try {
    // Test 1: Open database
    await unanimDB.openDatabase();
    log("PASS: openDatabase succeeded");

    // Test 2: Append events
    await unanimDB.appendEvents([
      { sequence: 1, timestamp: "2026-02-10T12:00:00Z", event_type: "user_action", schema_version: 1, payload: '{"action":"click"}' },
      { sequence: 2, timestamp: "2026-02-10T12:01:00Z", event_type: "api_response", schema_version: 1, payload: '{"status":200}' },
      { sequence: 3, timestamp: "2026-02-10T12:02:00Z", event_type: "user_action", schema_version: 1, payload: '{"action":"submit"}' }
    ]);
    log("PASS: appendEvents succeeded (3 events)");

    // Test 3: getAllEvents
    const all = await unanimDB.getAllEvents();
    log(all.length === 3 ? "PASS: getAllEvents returned 3 events" : "FAIL: getAllEvents returned " + all.length);

    // Test 4: getEventsSince
    const since1 = await unanimDB.getEventsSince(1);
    log(since1.length === 2 ? "PASS: getEventsSince(1) returned 2 events" : "FAIL: getEventsSince(1) returned " + since1.length);
    log(since1[0].sequence === 2 ? "PASS: first event has sequence 2" : "FAIL: first event has sequence " + since1[0].sequence);

    // Test 5: getLatestEvent
    const latest = await unanimDB.getLatestEvent();
    log(latest.sequence === 3 ? "PASS: getLatestEvent returned sequence 3" : "FAIL: getLatestEvent returned sequence " + latest?.sequence);
    log(latest.event_type === "user_action" ? "PASS: latest event_type is user_action" : "FAIL: latest event_type is " + latest?.event_type);

    // Test 6: getEventsSince(0) returns all
    const sinceZero = await unanimDB.getEventsSince(0);
    log(sinceZero.length === 3 ? "PASS: getEventsSince(0) returned all 3 events" : "FAIL: getEventsSince(0) returned " + sinceZero.length);

    // Test 7: getEventsSince(3) returns empty
    const sinceAll = await unanimDB.getEventsSince(3);
    log(sinceAll.length === 0 ? "PASS: getEventsSince(3) returned 0 events" : "FAIL: getEventsSince(3) returned " + sinceAll.length);

    // Test 8: Persistence — log a message for manual refresh test
    log("");
    log("=== PERSISTENCE TEST ===");
    log("Refresh this page. If events persist, you will see them below.");
    log("Events currently stored: " + all.length);
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

import std/os

let outputDir = getCurrentDir() / "validation" / "indexeddb_test"
createDir(outputDir)
writeFile(outputDir / "index.html", testHtml)

echo "IndexedDB test page generated at: " & outputDir & "/index.html"
echo "Open in browser to run tests. Refresh to verify persistence."
