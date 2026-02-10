# Client-side IndexedDB Storage Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Generate client-side IndexedDB wrapper JS that persists events across browser refreshes, integrated into `clientgen.nim`.

**Architecture:** Add a `generateIndexedDBJs()` proc to `clientgen.nim` that produces standalone JavaScript providing `openDatabase()`, `appendEvents()`, `getEventsSince()`, `getLatestEvent()`, and `getAllEvents()`. The generated JS uses the browser's native IndexedDB API (no libraries). The wrapper is included in the client HTML shell via an inline `<script>` tag. The Event schema matches the server-side 5-field format (sequence, timestamp, event_type, schema_version, payload) per spec-change #21.

**Tech Stack:** Nim (codegen), JavaScript (IndexedDB API), browser for validation

**Key context:**
- Issue #16 references "hash chain integration" but spec-change #21 removed hash chains. We use sequence continuity only.
- `clientgen.nim` already has `generateHtmlShell()` and `compileClientJs()`.
- The Event type has 5 fields: `sequence`, `timestamp`, `event_type`, `schema_version`, `payload`.
- IndexedDB object store key path: `sequence`. Indexes on `event_type` and `timestamp`.
- The generated JS must be standalone (ejectability principle).

---

### Task 1: Generate IndexedDB wrapper JS

**Files:**
- Modify: `src/unanim/clientgen.nim` (add `generateIndexedDBJs` proc)
- Test: `tests/test_clientgen.nim` (add new test blocks)

**Step 1: Write the failing test**

Add to `tests/test_clientgen.nim`:

```nim
# --- Task 8: generateIndexedDBJs basic structure ---
block testGenerateIndexedDBJsBasic:
  let js = generateIndexedDBJs()
  doAssert "indexedDB" in js,
    "IndexedDB JS should reference indexedDB API"
  doAssert "openDatabase" in js,
    "IndexedDB JS should have openDatabase function"
  doAssert "appendEvents" in js,
    "IndexedDB JS should have appendEvents function"
  doAssert "getEventsSince" in js,
    "IndexedDB JS should have getEventsSince function"
  doAssert "getLatestEvent" in js,
    "IndexedDB JS should have getLatestEvent function"
  doAssert "getAllEvents" in js,
    "IndexedDB JS should have getAllEvents function"

echo "test_clientgen: Task 8 passed."
```

**Step 2: Run test to verify it fails**

Run: `~/.nimble/bin/nim c -r tests/test_clientgen.nim`
Expected: FAIL with "undeclared identifier: 'generateIndexedDBJs'"

**Step 3: Write minimal implementation**

Add to `src/unanim/clientgen.nim`:

```nim
proc generateIndexedDBJs*(): string =
  ## Generate standalone JavaScript that provides IndexedDB-based event storage.
  ## The generated code exposes these async functions on the global `unanimDB` object:
  ## - openDatabase() — open/create the IndexedDB database
  ## - appendEvents(events) — store events in IndexedDB
  ## - getEventsSince(sequence) — retrieve events after a given sequence
  ## - getLatestEvent() — get the most recent event
  ## - getAllEvents() — retrieve the full event log
  ##
  ## Object store schema:
  ##   Key path: sequence
  ##   Indexes: event_type, timestamp
  ##
  ## Events use the 5-field format: sequence, timestamp, event_type, schema_version, payload
  result = """
// Unanim IndexedDB Event Storage
// This module is standalone — copy it to any project and it works.
const unanimDB = (() => {
  const DB_NAME = "unanim_events";
  const DB_VERSION = 1;
  const STORE_NAME = "events";

  let dbInstance = null;

  function openDatabase() {
    if (dbInstance) return Promise.resolve(dbInstance);
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION);
      request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains(STORE_NAME)) {
          const store = db.createObjectStore(STORE_NAME, { keyPath: "sequence" });
          store.createIndex("event_type", "event_type", { unique: false });
          store.createIndex("timestamp", "timestamp", { unique: false });
        }
      };
      request.onsuccess = (event) => {
        dbInstance = event.target.result;
        resolve(dbInstance);
      };
      request.onerror = (event) => {
        reject(new Error("Failed to open IndexedDB: " + event.target.error));
      };
    });
  }

  async function appendEvents(events) {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readwrite");
      const store = tx.objectStore(STORE_NAME);
      for (const event of events) {
        store.put(event);
      }
      tx.oncomplete = () => resolve();
      tx.onerror = (event) => reject(new Error("Failed to append events: " + event.target.error));
    });
  }

  async function getEventsSince(sequence) {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readonly");
      const store = tx.objectStore(STORE_NAME);
      const range = IDBKeyRange.lowerBound(sequence, true);
      const request = store.getAll(range);
      request.onsuccess = () => resolve(request.result);
      request.onerror = (event) => reject(new Error("Failed to get events: " + event.target.error));
    });
  }

  async function getLatestEvent() {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readonly");
      const store = tx.objectStore(STORE_NAME);
      const request = store.openCursor(null, "prev");
      request.onsuccess = (event) => {
        const cursor = event.target.result;
        resolve(cursor ? cursor.value : null);
      };
      request.onerror = (event) => reject(new Error("Failed to get latest event: " + event.target.error));
    });
  }

  async function getAllEvents() {
    const db = await openDatabase();
    return new Promise((resolve, reject) => {
      const tx = db.transaction(STORE_NAME, "readonly");
      const store = tx.objectStore(STORE_NAME);
      const request = store.getAll();
      request.onsuccess = () => resolve(request.result);
      request.onerror = (event) => reject(new Error("Failed to get all events: " + event.target.error));
    });
  }

  return { openDatabase, appendEvents, getEventsSince, getLatestEvent, getAllEvents };
})();
"""
```

**Step 4: Run test to verify it passes**

Run: `~/.nimble/bin/nim c -r tests/test_clientgen.nim`
Expected: PASS (all tasks including Task 8)

**Step 5: Commit**

```bash
git add src/unanim/clientgen.nim tests/test_clientgen.nim
git commit -m "feat(#16): add generateIndexedDBJs proc to clientgen"
```

---

### Task 2: Test IndexedDB JS schema details

**Files:**
- Test: `tests/test_clientgen.nim` (add schema validation tests)

**Step 1: Write the failing tests**

Add to `tests/test_clientgen.nim`:

```nim
# --- Task 9: IndexedDB schema details ---
block testIndexedDBSchema:
  let js = generateIndexedDBJs()
  doAssert "unanim_events" in js,
    "Database name should be unanim_events"
  doAssert "keyPath" in js,
    "Object store should have a keyPath"
  doAssert "\"sequence\"" in js,
    "Key path should be 'sequence'"

echo "test_clientgen: Task 9a passed."

block testIndexedDBIndexes:
  let js = generateIndexedDBJs()
  doAssert "createIndex" in js,
    "Should create indexes"
  doAssert "event_type" in js,
    "Should index on event_type"
  doAssert "timestamp" in js,
    "Should index on timestamp"

echo "test_clientgen: Task 9b passed."

block testIndexedDBStandalone:
  let js = generateIndexedDBJs()
  doAssert "import " notin js,
    "IndexedDB JS must be standalone — no imports"
  doAssert "require(" notin js,
    "IndexedDB JS must be standalone — no requires"
  doAssert "unanimDB" in js,
    "Should expose unanimDB global object"

echo "test_clientgen: Task 9c passed."
```

**Step 2: Run test to verify it passes**

These tests validate what Task 1 already implemented. They should pass immediately.

Run: `~/.nimble/bin/nim c -r tests/test_clientgen.nim`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/test_clientgen.nim
git commit -m "test(#16): add IndexedDB schema and standalone validation tests"
```

---

### Task 3: Integrate IndexedDB JS into HTML shell

**Files:**
- Modify: `src/unanim/clientgen.nim:282-295` (update `generateHtmlShell`)
- Test: `tests/test_clientgen.nim` (add integration test)

**Step 1: Write the failing test**

Add to `tests/test_clientgen.nim`:

```nim
# --- Task 10: HTML shell includes IndexedDB ---
block testHtmlShellIncludesIndexedDB:
  let html = generateHtmlShell("app.js", includeIndexedDB = true)
  doAssert "unanimDB" in html,
    "HTML shell should include IndexedDB wrapper when enabled"
  doAssert "openDatabase" in html,
    "HTML shell should include IndexedDB functions"
  doAssert "<script src=\"app.js\"></script>" in html,
    "HTML shell should still include app script"

echo "test_clientgen: Task 10a passed."

block testHtmlShellWithoutIndexedDB:
  let html = generateHtmlShell("app.js")
  doAssert "unanimDB" notin html,
    "HTML shell should NOT include IndexedDB wrapper by default"

echo "test_clientgen: Task 10b passed."
```

**Step 2: Run test to verify it fails**

Run: `~/.nimble/bin/nim c -r tests/test_clientgen.nim`
Expected: FAIL — `generateHtmlShell` doesn't accept `includeIndexedDB` parameter

**Step 3: Update `generateHtmlShell` to accept `includeIndexedDB` parameter**

Modify `src/unanim/clientgen.nim` — update the `generateHtmlShell` proc signature and body:

```nim
proc generateHtmlShell*(scriptFile: string, title: string = "App",
                        includeIndexedDB: bool = false): string =
  ## Generate a minimal standalone HTML shell that loads the compiled JS.
  ## SCAFFOLD(Phase 1, #5): This is a minimal scaffold. Will be replaced
  ## by the islands DSL in later phases.
  result = "<!DOCTYPE html>\n" &
    "<html>\n" &
    "<head>\n" &
    "  <meta charset=\"utf-8\">\n" &
    "  <title>" & title & "</title>\n" &
    "</head>\n" &
    "<body>\n"
  if includeIndexedDB:
    result &= "  <script>\n" & generateIndexedDBJs() & "\n  </script>\n"
  result &= "  <script src=\"" & scriptFile & "\"></script>\n" &
    "</body>\n" &
    "</html>\n"
```

**Step 4: Run test to verify it passes**

Run: `~/.nimble/bin/nim c -r tests/test_clientgen.nim`
Expected: PASS (all tasks including Task 10a and 10b)

**Step 5: Commit**

```bash
git add src/unanim/clientgen.nim tests/test_clientgen.nim
git commit -m "feat(#16): integrate IndexedDB JS into HTML shell"
```

---

### Task 4: Node.js syntax validation of generated IndexedDB JS

**Files:**
- Test: `tests/test_clientgen_jscompile.nim` (add syntax validation)

**Step 1: Write the test**

Add to `tests/test_clientgen_jscompile.nim`:

```nim
# Test 7: IndexedDB JS is syntactically valid
block testIndexedDBJsSyntax:
  import ../src/unanim/clientgen
  const indexedDBJs = generateIndexedDBJs()
  # Write to file and validate with node --check
  const tmpFile = "/tmp/unanim_test_indexeddb.js"
  static:
    writeFile(tmpFile, indexedDBJs)
  const nodeCheck = gorgeEx("which node")
  when nodeCheck[1] == 0:
    const checkResult = gorgeEx("node --check " & tmpFile)
    doAssert checkResult[1] == 0,
      "Generated IndexedDB JS should be syntactically valid. Error: " & checkResult[0]
    echo "test_clientgen_jscompile: Test 7 passed (node --check verified)."
  else:
    echo "test_clientgen_jscompile: Test 7 skipped (node not available)."
```

Note: the `import` here is already at the top of the file. Instead, since `clientgen` is already imported at the top of `test_clientgen_jscompile.nim`, just add the block without the extra import. Use `static` to call `generateIndexedDBJs()` at compile-time and write it to a temp file, then check with `node --check`.

Actually, since `generateIndexedDBJs` is a runtime proc (not `{.compileTime.}`), we just write it in a static block:

```nim
# Test 7: IndexedDB JS is syntactically valid
block testIndexedDBJsSyntax:
  const indexedDBJs = static(generateIndexedDBJs())
  const tmpFile = "/tmp/unanim_test_indexeddb.js"
  static:
    writeFile(tmpFile, indexedDBJs)
  const nodeCheck = gorgeEx("which node")
  when nodeCheck[1] == 0:
    const checkResult = gorgeEx("node --check " & tmpFile)
    doAssert checkResult[1] == 0,
      "Generated IndexedDB JS should be syntactically valid. Error: " & checkResult[0]
    echo "test_clientgen_jscompile: Test 7 passed (node --check verified)."
  else:
    echo "test_clientgen_jscompile: Test 7 skipped (node not available)."
```

**Step 2: Run test**

Run: `~/.nimble/bin/nim c -r tests/test_clientgen_jscompile.nim`
Expected: PASS

**Step 3: Commit**

```bash
git add tests/test_clientgen_jscompile.nim
git commit -m "test(#16): validate IndexedDB JS syntax with node --check"
```

---

### Task 5: Add test_indexeddb_browser.nim for real browser validation

**Files:**
- Create: `validation/e2e_indexeddb.nim` (generates test HTML)
- Create: `validation/VALIDATION_LOG_INDEXEDDB.md` (test results)

**Step 1: Create browser test artifact generator**

Create `validation/e2e_indexeddb.nim`:

```nim
## End-to-end validation: IndexedDB event storage in real browser.
## Generates an HTML file that exercises all IndexedDB operations.
import ../src/unanim/clientgen

const testHtml = """<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>IndexedDB Test</title></head>
<body>
<pre id="output"></pre>
<script>
""" & generateIndexedDBJs() & """

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
    log("Refresh this page. If events persist, you'll see them below.");
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

const outputDir = "validation/indexeddb_test"
static:
  discard gorge("mkdir -p " & outputDir)
  writeFile(outputDir & "/index.html", testHtml)

echo "IndexedDB test page generated at: " & outputDir & "/index.html"
echo "Open in browser to run tests. Refresh to verify persistence."
```

**Step 2: Compile and run to generate the test page**

Run: `~/.nimble/bin/nim c -r validation/e2e_indexeddb.nim`

**Step 3: Open in browser and run tests**

Open `validation/indexeddb_test/index.html` in a browser. Check:
- All 8 tests show PASS
- Refresh page — events still present
- Record results in `validation/VALIDATION_LOG_INDEXEDDB.md`

**Step 4: Commit**

```bash
git add validation/e2e_indexeddb.nim validation/VALIDATION_LOG_INDEXEDDB.md
git commit -m "docs(#16): add browser validation for IndexedDB storage"
```

---

### Task 6: Add test to nimble and run full suite

**Files:**
- Modify: `unanim.nimble` — no new test file needed (existing test files cover it)

**Step 1: Run the full test suite**

Run: `~/.nimble/bin/nimble test -y`
Expected: All tests pass

**Step 2: Commit any remaining changes and push**

```bash
git push -u origin issue-16
```

**Step 3: Create PR**

```bash
gh pr create --title "feat(#16): client-side IndexedDB storage" --body "$(cat <<'EOF'
Closes #16

## What this does

Adds `generateIndexedDBJs()` to `clientgen.nim` that produces standalone JavaScript providing IndexedDB-based event storage. The wrapper exposes `unanimDB.openDatabase()`, `appendEvents()`, `getEventsSince()`, `getLatestEvent()`, and `getAllEvents()`. Events use the 5-field format (sequence, timestamp, event_type, schema_version, payload) matching the server-side DO schema. The `generateHtmlShell()` proc now accepts `includeIndexedDB` to inline the wrapper.

## Spec compliance

- **Section 4.1 (Architecture):** IndexedDB stores the event log on the client. No WASM SQLite, zero bundle overhead.
- **Section 4.2 (Event Log):** Event schema matches: sequence (key path), timestamp, event_type, schema_version, payload.
- **Spec-change #21:** No hash fields — uses sequence continuity only.

## Validation performed

All tests run in real browser (see `validation/VALIDATION_LOG_INDEXEDDB.md`):
1. openDatabase creates DB and object store
2. appendEvents stores 3 events
3. getAllEvents retrieves all stored events
4. getEventsSince filters by sequence
5. getLatestEvent returns highest-sequence event
6. Events persist across page refresh
EOF
)"
```
