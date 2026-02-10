import std/strutils
import std/osproc
import std/os
import ../src/unanim/guard
import ../src/unanim/codegen

# --- Task 1: guard() macro compiles without error ---
block testGuardCompiles:
  guard("credits")
  doAssert true, "guard() macro should compile without error"

echo "test_guard: Task 1 passed."

# --- Task 2: getGuardedStates() returns registered states ---
block testGetGuardedStates:
  # "credits" was registered above
  let states = getGuardedStates()
  doAssert "credits" in states,
    "getGuardedStates() should include 'credits'"

echo "test_guard: Task 2 passed."

# --- Task 3: Multiple guard() calls register multiple states ---
block testMultipleGuards:
  guard("tokens")
  guard("api_calls")
  let states = getGuardedStates()
  doAssert "credits" in states,
    "getGuardedStates() should include 'credits'"
  doAssert "tokens" in states,
    "getGuardedStates() should include 'tokens'"
  doAssert "api_calls" in states,
    "getGuardedStates() should include 'api_calls'"
  doAssert states.len >= 3,
    "getGuardedStates() should have at least 3 entries"

echo "test_guard: Task 3 passed."

# --- Task 4: DO JS rejects client-submitted proxy_minted events ---
block testDORejectsClientProxyMinted:
  let js = generateDurableObjectJs()
  doAssert "rejectClientProxyMinted" in js,
    "DO JS should have rejectClientProxyMinted method"
  doAssert "proxy_minted" in js,
    "DO JS should check for proxy_minted event type"
  doAssert "Client cannot submit proxy_minted events" in js,
    "DO JS should have rejection error message"
  doAssert "403" in js,
    "DO JS should return 403 for guard violations"

echo "test_guard: Task 4 passed."

# --- Task 5: DO JS has mintProxyEvent method ---
block testDOHasMintProxyEvent:
  let js = generateDurableObjectJs()
  doAssert "mintProxyEvent" in js,
    "DO JS should have mintProxyEvent method"
  doAssert "proxy_minted" in js,
    "mintProxyEvent should create events with type proxy_minted"
  doAssert "new Date().toISOString()" in js,
    "mintProxyEvent should generate ISO timestamps"
  doAssert "SCAFFOLD(phase4, #36)" in js,
    "mintProxyEvent should have SCAFFOLD marker"

echo "test_guard: Task 5 passed."

# --- Task 6: Generated JS passes node --check ---
block testGeneratedJsNodeCheck:
  let (_, whichExitCode) = execCmdEx("which node")
  if whichExitCode != 0:
    echo "test_guard: Task 6 skipped (node not found on PATH)."
  else:
    let js = generateDurableObjectJs()
    let tmpDir = "/tmp/unanim_guard_test"
    createDir(tmpDir)
    let jsFile = tmpDir & "/do_guard_test.js"
    writeFile(jsFile, js)
    let (output, exitCode) = execCmdEx("node --check " & jsFile)
    doAssert exitCode == 0,
      "DO JS with guard enforcement must pass node --check. Errors: " & output
    echo "test_guard: Task 6 passed (node --check verified)."

# --- Task 7: Guard enforcement in storeEvents ---
block testGuardEnforcementInStoreEvents:
  let js = generateDurableObjectJs()
  # storeEvents should call rejectClientProxyMinted
  let storeEventsPos = js.find("async storeEvents")
  let getEventsPos = js.find("async getEvents")
  doAssert storeEventsPos > 0 and getEventsPos > 0,
    "Both storeEvents and getEvents must exist"
  let storeEventsBody = js[storeEventsPos..getEventsPos]
  doAssert "rejectClientProxyMinted" in storeEventsBody,
    "storeEvents should call rejectClientProxyMinted"

echo "test_guard: Task 7 passed."

# --- Task 8: Guard enforcement in verifyAndStoreEvents ---
block testGuardEnforcementInVerifyAndStore:
  let js = generateDurableObjectJs()
  # verifyAndStoreEvents should call rejectClientProxyMinted
  let verifyPos = js.find("async verifyAndStoreEvents")
  let handleProxyPos = js.find("async handleProxy")
  doAssert verifyPos > 0 and handleProxyPos > 0,
    "Both verifyAndStoreEvents and handleProxy must exist"
  let verifyBody = js[verifyPos..handleProxyPos]
  doAssert "rejectClientProxyMinted" in verifyBody,
    "verifyAndStoreEvents should call rejectClientProxyMinted"

echo "test_guard: Task 8 passed."

# --- Task 9: guardedStates metadata embedded in DO JS ---
block testGuardedStatesMetadata:
  let js = generateDurableObjectJs(guardedStates = @["credits", "tokens"])
  doAssert "this.guardedStates" in js,
    "DO should store guardedStates on this"
  doAssert "\"credits\"" in js,
    "DO should include 'credits' in guardedStates array"
  doAssert "\"tokens\"" in js,
    "DO should include 'tokens' in guardedStates array"

echo "test_guard: Task 9 passed."

# --- Task 10: Empty guardedStates produces empty array ---
block testEmptyGuardedStates:
  let js = generateDurableObjectJs(guardedStates = @[])
  doAssert "this.guardedStates = []" in js,
    "DO with no guarded states should have empty array"

echo "test_guard: Task 10 passed."

# --- Task 11: DO JS with guarded states passes node --check ---
block testGuardedStatesNodeCheck:
  let (_, whichExitCode) = execCmdEx("which node")
  if whichExitCode != 0:
    echo "test_guard: Task 11 skipped (node not found on PATH)."
  else:
    let js = generateDurableObjectJs(guardedStates = @["credits", "tokens", "api_calls"])
    let tmpDir = "/tmp/unanim_guard_test"
    createDir(tmpDir)
    let jsFile = tmpDir & "/do_guard_states_test.js"
    writeFile(jsFile, js)
    let (output, exitCode) = execCmdEx("node --check " & jsFile)
    doAssert exitCode == 0,
      "DO JS with guarded states must pass node --check. Errors: " & output
    echo "test_guard: Task 11 passed (node --check verified)."

# --- Task 12: Combined Worker+DO with guard passes node --check ---
block testCombinedGuardNodeCheck:
  let (_, whichExitCode) = execCmdEx("which node")
  if whichExitCode != 0:
    echo "test_guard: Task 12 skipped (node not found on PATH)."
  else:
    let workerJs = generateWorkerJs(@[], @[], hasDO = true)
    let doJs = generateDurableObjectJs(guardedStates = @["credits"])
    let combined = workerJs & "\n" & doJs
    let tmpDir = "/tmp/unanim_guard_test"
    createDir(tmpDir)
    let jsFile = tmpDir & "/combined_guard_test.js"
    writeFile(jsFile, combined)
    let (output, exitCode) = execCmdEx("node --check " & jsFile)
    doAssert exitCode == 0,
      "Combined Worker+DO with guard must pass node --check. Errors: " & output
    echo "test_guard: Task 12 passed (node --check verified)."

# --- Task 13: Ejectability - no framework imports ---
block testGuardEjectability:
  let js = generateDurableObjectJs(guardedStates = @["credits"])
  doAssert not js.contains("import unanim"),
    "DO JS with guard must be standalone -- no framework imports"
  doAssert not js.contains("require(\"unanim"),
    "DO JS with guard must be standalone -- no framework requires"
  doAssert "export class UserDO" in js,
    "DO JS with guard must have named export"

echo "test_guard: Task 13 passed."

# --- Task 14: mintProxyEvent creates proper event structure ---
block testMintProxyEventStructure:
  let js = generateDurableObjectJs()
  # mintProxyEvent should build a complete event
  let mintPos = js.find("mintProxyEvent(payload)")
  doAssert mintPos > 0,
    "mintProxyEvent should exist"
  let mintSection = js[mintPos..min(mintPos + 1000, js.len - 1)]
  doAssert "sequence:" in mintSection,
    "mintProxyEvent should set sequence"
  doAssert "timestamp:" in mintSection,
    "mintProxyEvent should set timestamp"
  doAssert "event_type:" in mintSection,
    "mintProxyEvent should set event_type"
  doAssert "schema_version:" in mintSection,
    "mintProxyEvent should set schema_version"
  doAssert "payload:" in mintSection,
    "mintProxyEvent should set payload"
  doAssert "INSERT INTO events" in mintSection,
    "mintProxyEvent should store event in SQLite"

echo "test_guard: Task 14 passed."

echo "All guard tests passed."
