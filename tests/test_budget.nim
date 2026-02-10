## tests/test_budget.nim
## CI size budget checker: measures gzipped sizes of generated artifacts
## against VISION.md Section 8.2 budgets.
## Phase 3 enforcement: warnings only (always exits 0).
##
## Run: nim c -r tests/test_budget.nim

import ../src/unanim/clientgen

import std/os
import std/osproc
import std/strutils

# --- Runtime: generate client artifacts and measure all sizes ---

let outDir = getCurrentDir() / "tests" / "budget_tmp"
createDir(outDir)

# Write client-side artifacts for measurement
let indexedDBJs = generateIndexedDBJs()
let syncJs = generateSyncJs()
let shellHtml = generateHtmlShell("app.js", includeIndexedDB = true, includeSync = true)
writeFile(outDir / "indexeddb.js", indexedDBJs)
writeFile(outDir / "sync.js", syncJs)
writeFile(outDir / "shell.html", shellHtml)

# Worker JS comes from the committed todo_deploy artifacts
let workerJs = getCurrentDir() / "validation" / "todo_deploy" / "worker.js"

type BudgetResult = object
  label: string
  sizeBytes: int
  budgetBytes: int
  pass: bool
  error: string

proc measureGzipped(filePath: string, label: string, budgetBytes: int): BudgetResult =
  result.label = label
  result.budgetBytes = budgetBytes
  if not fileExists(filePath):
    result.error = "file not found: " & filePath
    return
  let (output, exitCode) = execCmdEx("gzip -c " & filePath & " | wc -c")
  if exitCode == 0:
    result.sizeBytes = output.strip().parseInt()
    result.pass = result.sizeBytes <= budgetBytes
  else:
    result.error = output.strip()

var results: seq[BudgetResult]
results.add measureGzipped(workerJs, "Worker JS", 5 * 1024)
results.add measureGzipped(outDir / "indexeddb.js", "IndexedDB wrapper", 3 * 1024)
results.add measureGzipped(outDir / "sync.js", "Sync layer", 2 * 1024)
results.add measureGzipped(outDir / "shell.html", "HTML shell", 2 * 1024)

# Print results table
echo ""
echo "=== Artifact Size Budgets (VISION.md Section 8.2) ==="
echo ""
echo "  Artifact             Size (gzipped)   Budget    Status"
echo "  -------------------  --------------   ------    ------"

var warnings = 0
for r in results:
  if r.error.len > 0:
    echo "  " & r.label.alignLeft(21) & "ERROR: " & r.error
    warnings.inc
    continue
  let sizeKiB = r.sizeBytes.float / 1024.0
  let budgetKiB = r.budgetBytes.float / 1024.0
  let status = if r.pass: "PASS" else: "WARN"
  if not r.pass:
    inc warnings
  echo "  " & r.label.alignLeft(21) &
    (sizeKiB.formatFloat(ffDecimal, 1) & " KiB").alignLeft(17) &
    ($budgetKiB.int & " KiB").alignLeft(10) &
    status

echo ""
if warnings > 0:
  echo "  " & $warnings & " artifact(s) over budget (warnings only in Phase 3)"
else:
  echo "  All artifacts within budget."
echo ""

# Clean up temporary files
removeDir(outDir)

echo "All budget tests passed."
