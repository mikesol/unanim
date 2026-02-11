import std/strutils
import std/osproc
import ../src/unanim/cron
import ../src/unanim/after
import ../src/unanim/codegen

# --- Task 1: cron() macro compiles ---
block testCronMacroCompiles:
  proc myHandler() = discard
  cron("0 */6 * * *", myHandler)
  doAssert true, "cron() macro should compile without error"

echo "test_cron_after: Task 1 passed."

# --- Task 2: getCronSchedules() returns registered schedules ---
block testGetCronSchedules:
  proc anotherHandler() = discard
  cron("0 0 * * *", anotherHandler)
  let schedules = getCronSchedules()
  doAssert schedules.len >= 2,
    "getCronSchedules() should return at least 2 registered schedules"
  doAssert "0 */6 * * *" in schedules,
    "getCronSchedules() should contain the first registered schedule"
  doAssert "0 0 * * *" in schedules,
    "getCronSchedules() should contain the second registered schedule"

echo "test_cron_after: Task 2 passed."

# --- Task 3: after() macro compiles ---
block testAfterMacroCompiles:
  proc delayedHandler() = discard
  after(7.days, delayedHandler)
  doAssert true, "after() macro should compile without error"

echo "test_cron_after: Task 3 passed."

# --- Task 4: hasAfterHandlers() returns correct boolean ---
block testHasAfterHandlers:
  doAssert hasAfterHandlers() == true,
    "hasAfterHandlers() should return true after after() was called"

echo "test_cron_after: Task 4 passed."

# --- Task 5: Worker JS includes scheduled handler when crons registered ---
block testWorkerJsScheduledHandler:
  let js = generateWorkerJs(@[], @[], hasDO = true,
                             cronSchedules = @["0 */6 * * *"])
  doAssert "async scheduled(event, env, ctx)" in js,
    "Worker JS should contain scheduled handler when crons are registered"
  doAssert "__cron__" in js,
    "Worker scheduled handler should route to DO with __cron__ name"
  doAssert "event.cron" in js,
    "Worker scheduled handler should pass event.cron to DO"
  doAssert "event.scheduledTime" in js,
    "Worker scheduled handler should pass event.scheduledTime to DO"

echo "test_cron_after: Task 5 passed."

# --- Task 6: Worker JS does NOT include scheduled when no crons ---
block testWorkerJsNoScheduledHandler:
  let js = generateWorkerJs(@[], @[], hasDO = true)
  doAssert "async scheduled" notin js,
    "Worker JS should NOT contain scheduled handler when no crons"

echo "test_cron_after: Task 6 passed."

# --- Task 7: DO JS includes handleCron method when hasCron=true ---
block testDoJsHandleCron:
  let js = generateDurableObjectJs(hasCron = true)
  doAssert "handleCron" in js,
    "DO JS should include handleCron method when hasCron=true"
  doAssert "cron_result" in js,
    "DO handleCron should store a cron_result event"
  doAssert "\"/cron\"" in js,
    "DO should route /cron path when hasCron=true"

echo "test_cron_after: Task 7 passed."

# --- Task 8: DO JS includes alarm() method when hasAfter=true ---
block testDoJsAlarm:
  let js = generateDurableObjectJs(hasAfter = true)
  doAssert "async alarm()" in js,
    "DO JS should include alarm() method when hasAfter=true"
  doAssert "__alarm_meta__" in js,
    "DO alarm() should read alarm metadata from storage"
  doAssert "alarm_fired" in js,
    "DO alarm() should store an alarm_fired event"

echo "test_cron_after: Task 8 passed."

# --- Task 9: DO JS includes scheduleAlarm method when hasAfter=true ---
block testDoJsScheduleAlarm:
  let js = generateDurableObjectJs(hasAfter = true)
  doAssert "scheduleAlarm" in js,
    "DO JS should include scheduleAlarm method when hasAfter=true"
  doAssert "setAlarm" in js,
    "DO scheduleAlarm should call state.storage.setAlarm"
  doAssert "handleScheduleAlarm" in js,
    "DO JS should include handleScheduleAlarm endpoint"
  doAssert "\"/schedule-alarm\"" in js,
    "DO should route /schedule-alarm path when hasAfter=true"

echo "test_cron_after: Task 9 passed."

# --- Task 10: DO JS does NOT include alarm/cron when not needed ---
block testDoJsNoAlarmNoCron:
  let js = generateDurableObjectJs()
  doAssert "handleCron" notin js,
    "DO JS should NOT include handleCron when hasCron=false"
  doAssert "async alarm()" notin js,
    "DO JS should NOT include alarm() when hasAfter=false"
  doAssert "scheduleAlarm" notin js,
    "DO JS should NOT include scheduleAlarm when hasAfter=false"
  doAssert "handleScheduleAlarm" notin js,
    "DO JS should NOT include handleScheduleAlarm when hasAfter=false"
  doAssert "\"/cron\"" notin js,
    "DO JS should NOT route /cron when hasCron=false"
  doAssert "\"/schedule-alarm\"" notin js,
    "DO JS should NOT route /schedule-alarm when hasAfter=false"

echo "test_cron_after: Task 10 passed."

# --- Task 11: wrangler.toml includes [triggers] section with cron schedules ---
block testWranglerTomlTriggers:
  let toml = generateWranglerToml("cron-app", @[],
                                   cronSchedules = @["0 */6 * * *", "0 0 * * *"])
  doAssert "[triggers]" in toml,
    "wrangler.toml should include [triggers] section when crons are present"
  doAssert "crons = [" in toml,
    "wrangler.toml triggers should have crons array"
  doAssert "\"0 */6 * * *\"" in toml,
    "wrangler.toml should include first cron schedule"
  doAssert "\"0 0 * * *\"" in toml,
    "wrangler.toml should include second cron schedule"

echo "test_cron_after: Task 11 passed."

# --- Task 12: wrangler.toml does NOT include triggers when no crons ---
block testWranglerTomlNoTriggers:
  let toml = generateWranglerToml("no-cron-app", @[])
  doAssert "[triggers]" notin toml,
    "wrangler.toml should NOT include [triggers] section when no crons"

echo "test_cron_after: Task 12 passed."

# --- Task 13: Generated JS passes node --check (Worker + DO with cron + after) ---
block testGeneratedJsNodeCheck:
  let (_, whichExitCode) = execCmdEx("which node")
  if whichExitCode != 0:
    echo "test_cron_after: Task 13 skipped (node not available)."
  else:
    # Test Worker JS with scheduled handler
    let workerJs = generateWorkerJs(@[], @[], hasDO = true,
                                     cronSchedules = @["0 */6 * * *"])
    let tmpFile = "/tmp/unanim_test_cron_worker.js"
    writeFile(tmpFile, workerJs)
    let (workerOutput, workerExit) = execCmdEx("node --check " & tmpFile)
    doAssert workerExit == 0,
      "Worker JS with scheduled handler must pass node --check. Error: " & workerOutput

    # Test DO JS with cron + after
    let doJs = generateDurableObjectJs(hasCron = true, hasAfter = true)
    let tmpDoFile = "/tmp/unanim_test_cron_do.js"
    writeFile(tmpDoFile, doJs)
    let (doOutput, doExit) = execCmdEx("node --check " & tmpDoFile)
    doAssert doExit == 0,
      "DO JS with cron + after must pass node --check. Error: " & doOutput

    # Test combined Worker + DO
    let combinedJs = workerJs & "\n" & doJs
    let tmpCombinedFile = "/tmp/unanim_test_cron_combined.js"
    writeFile(tmpCombinedFile, combinedJs)
    let (combinedOutput, combinedExit) = execCmdEx("node --check " & tmpCombinedFile)
    doAssert combinedExit == 0,
      "Combined Worker + DO with cron + after must pass node --check. Error: " & combinedOutput

    echo "test_cron_after: Task 13 passed (node --check verified)."

# --- Task 14: Backward compatibility - existing callers work unchanged ---
block testBackwardCompatibility:
  # generateWorkerJs with no cronSchedules (default)
  let js1 = generateWorkerJs(@[], @[])
  doAssert "export default" in js1
  doAssert "async fetch" in js1
  doAssert "async scheduled" notin js1

  # generateDurableObjectJs with no params (default)
  let js2 = generateDurableObjectJs()
  doAssert "export class UserDO" in js2
  doAssert "handleCron" notin js2
  doAssert "async alarm()" notin js2

  # generateWranglerToml with no cronSchedules (default)
  let toml = generateWranglerToml("compat-app", @[])
  doAssert "[triggers]" notin toml

echo "test_cron_after: Task 14 passed."

# --- Task 15: DO JS with both cron and after ---
block testDoJsCronAndAfter:
  let js = generateDurableObjectJs(hasCron = true, hasAfter = true)
  doAssert "handleCron" in js,
    "DO JS with both should include handleCron"
  doAssert "async alarm()" in js,
    "DO JS with both should include alarm()"
  doAssert "scheduleAlarm" in js,
    "DO JS with both should include scheduleAlarm"
  doAssert "handleScheduleAlarm" in js,
    "DO JS with both should include handleScheduleAlarm"
  doAssert "\"/cron\"" in js,
    "DO JS with both should route /cron"
  doAssert "\"/schedule-alarm\"" in js,
    "DO JS with both should route /schedule-alarm"

echo "test_cron_after: Task 15 passed."

# --- Task 16: Worker JS export structure is valid with scheduled ---
block testWorkerJsExportStructure:
  let js = generateWorkerJs(@[], @[], hasDO = true,
                             cronSchedules = @["0 */6 * * *"])
  # Both handlers should be inside export default { ... }
  let exportPos = js.find("export default")
  let fetchPos = js.find("async fetch(")
  let scheduledPos = js.find("async scheduled(")
  let closingPos = js.rfind("};")
  doAssert exportPos >= 0, "Should have export default"
  doAssert fetchPos > exportPos, "fetch should be inside export"
  doAssert scheduledPos > fetchPos, "scheduled should come after fetch"
  doAssert closingPos > scheduledPos, "Module closing should come after scheduled"

echo "test_cron_after: Task 16 passed."

# --- Task 17: wrangler.toml triggers with single cron ---
block testWranglerTomlSingleCron:
  let toml = generateWranglerToml("single-cron-app", @[],
                                   cronSchedules = @["*/5 * * * *"])
  doAssert "[triggers]" in toml
  doAssert "crons = [\"*/5 * * * *\"]" in toml,
    "Single cron should be formatted correctly"

echo "test_cron_after: Task 17 passed."

# --- Task 18: wrangler.toml triggers combined with DO bindings ---
block testWranglerTomlTriggersWithDO:
  let toml = generateWranglerToml("full-app", @["api-key"], hasDO = true,
                                   cronSchedules = @["0 */6 * * *"])
  doAssert "[durable_objects]" in toml, "Should have DO section"
  doAssert "[triggers]" in toml, "Should have triggers section"
  doAssert "API_KEY" in toml, "Should have secret reference"

echo "test_cron_after: Task 18 passed."

echo "All cron/after tests passed."
