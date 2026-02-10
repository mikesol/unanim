## Tests for unanim/webhook module and webhook codegen integration.

import std/os
import std/strutils
import std/osproc
import ../src/unanim/webhook
import ../src/unanim/codegen
import ../src/unanim/secret
import ../src/unanim/proxyfetch

# --- Task 1: webhook() macro compiles without error ---
block testWebhookMacroCompiles:
  webhook("/stripe"):
    discard
  doAssert true, "webhook() macro should compile without error"

echo "test_webhook: Task 1 passed."

# --- Task 2: getWebhookPaths returns registered paths ---
block testGetWebhookPaths:
  let paths = getWebhookPaths()
  doAssert "/stripe" in paths,
    "getWebhookPaths should include /stripe"

echo "test_webhook: Task 2 passed."

# --- Task 3: Multiple webhooks register correctly ---
webhook("/clerk"):
  discard

webhook("/fal"):
  discard

block testMultipleWebhooks:
  let paths = getWebhookPaths()
  doAssert paths.len >= 3,
    "Should have at least 3 registered webhooks, got " & $paths.len
  doAssert "/stripe" in paths
  doAssert "/clerk" in paths
  doAssert "/fal" in paths

echo "test_webhook: Task 3 passed."

# --- Task 4: Path validation: must start with / ---
# This test is compile-time only. We verify the macro rejects bad paths
# by checking the error() call exists in the source. A direct test would
# fail compilation, so we validate via code inspection.
block testPathValidation:
  # Verify that webhook.nim contains the validation logic
  const webhookSrc = staticRead("../src/unanim/webhook.nim")
  doAssert "webhook() path must start with '/'" in webhookSrc,
    "webhook.nim should contain path validation error message"

echo "test_webhook: Task 4 passed."

# --- Task 5: Worker JS includes webhook routing when webhookPaths is non-empty ---
block testWorkerJsWithWebhooks:
  let js = generateWorkerJs(@[], @[], hasDO = true, webhookPaths = @["/stripe", "/clerk"])
  doAssert "/webhook/" in js,
    "Worker JS should contain /webhook/ routing"
  doAssert "__webhook__" in js,
    "Worker JS should route webhooks to __webhook__ DO"
  doAssert "USER_DO.idFromName" in js,
    "Worker JS should use idFromName for webhook DO"

echo "test_webhook: Task 5 passed."

# --- Task 6: Worker JS does NOT include webhook routing when no webhooks ---
block testWorkerJsWithoutWebhooks:
  let js = generateWorkerJs(@[], @[], hasDO = true, webhookPaths = @[])
  doAssert "__webhook__" notin js,
    "Worker JS should NOT contain __webhook__ when no webhooks"
  # /webhook/ should not appear as a route (it can appear in comments though)
  doAssert "startsWith(\"/webhook/\")" notin js,
    "Worker JS should NOT route /webhook/ when no webhooks"

echo "test_webhook: Task 6 passed."

# --- Task 7: DO JS includes handleWebhook method when webhookPaths is non-empty ---
block testDurableObjectJsWithWebhooks:
  let js = generateDurableObjectJs(webhookPaths = @["/stripe"])
  doAssert "handleWebhook" in js,
    "DO JS should contain handleWebhook method"
  doAssert "async handleWebhook(request, path, corsHeaders)" in js,
    "DO JS should have the full handleWebhook signature"
  doAssert "SCAFFOLD(phase4, #37)" in js,
    "DO JS should have SCAFFOLD marker for signature verification"

echo "test_webhook: Task 7 passed."

# --- Task 8: DO JS stores webhook_result events with correct event_type ---
block testDurableObjectJsWebhookEventType:
  let js = generateDurableObjectJs(webhookPaths = @["/stripe"])
  doAssert "webhook_result" in js,
    "DO JS should store events with event_type 'webhook_result'"
  doAssert "webhook_path" in js,
    "DO JS webhook event should include the webhook path for correlation"
  doAssert "INSERT INTO events" in js,
    "DO JS should insert webhook events into SQLite"

echo "test_webhook: Task 8 passed."

# --- Task 9: Generated JS passes node --check ---
block testGeneratedJsNodeCheckWithWebhooks:
  let (_, whichExitCode) = execCmdEx("which node")
  if whichExitCode != 0:
    echo "test_webhook: Task 9 skipped (node not found on PATH)."
  else:
    # Test Worker + DO combined JS with webhooks
    let workerJs = generateWorkerJs(@[], @[], hasDO = true, webhookPaths = @["/stripe", "/clerk"])
    let doJs = generateDurableObjectJs(webhookPaths = @["/stripe", "/clerk"])
    let combinedJs = workerJs & "\n" & doJs
    let tmpDir = "/tmp/unanim_webhook_test"
    createDir(tmpDir)
    let jsFile = tmpDir & "/webhook_test.js"
    writeFile(jsFile, combinedJs)
    let (output, exitCode) = execCmdEx("node --check " & jsFile)
    doAssert exitCode == 0,
      "Generated JS with webhooks should pass node --check. Errors: " & output
    echo "test_webhook: Task 9 passed (node --check verified)."

# --- Task 10: DO JS without webhooks does NOT include handleWebhook ---
block testDurableObjectJsWithoutWebhooks:
  let js = generateDurableObjectJs(webhookPaths = @[])
  doAssert "handleWebhook" notin js,
    "DO JS should NOT contain handleWebhook when no webhooks"

echo "test_webhook: Task 10 passed."

# --- Task 11: Backward compatibility - existing DO JS unchanged ---
block testDurableObjectJsBackwardCompat:
  let jsDefault = generateDurableObjectJs()
  let jsEmpty = generateDurableObjectJs(webhookPaths = @[])
  doAssert jsDefault == jsEmpty,
    "generateDurableObjectJs() with default args should match empty webhookPaths"
  doAssert "export class UserDO" in jsDefault,
    "Default DO JS should still export UserDO class"
  doAssert "handleProxy" in jsDefault,
    "Default DO JS should still have handleProxy"
  doAssert "handleSync" in jsDefault,
    "Default DO JS should still have handleSync"

echo "test_webhook: Task 11 passed."

# --- Task 12: Webhook routing in DO uses path.startsWith ---
block testDurableObjectJsWebhookRouting:
  let js = generateDurableObjectJs(webhookPaths = @["/stripe"])
  doAssert "path.startsWith(\"/webhook/\")" in js,
    "DO JS should route webhook requests using path.startsWith"

echo "test_webhook: Task 12 passed."

# --- Task 13: Worker JS with webhooks but no DO still works ---
block testWorkerJsWebhooksWithoutDO:
  let js = generateWorkerJs(@[], @[], hasDO = false, webhookPaths = @["/stripe"])
  doAssert "/webhook/" in js,
    "Worker JS should still route webhooks even without general DO"
  # Should still be valid JS
  let (_, whichExitCode) = execCmdEx("which node")
  if whichExitCode == 0:
    let tmpDir = "/tmp/unanim_webhook_test"
    createDir(tmpDir)
    let jsFile = tmpDir & "/webhook_no_do.js"
    writeFile(jsFile, js)
    let (output, exitCode) = execCmdEx("node --check " & jsFile)
    doAssert exitCode == 0,
      "Worker JS with webhooks but no DO should pass node --check: " & output

echo "test_webhook: Task 13 passed."

# --- Task 14: Ejectability - no framework imports in generated JS ---
block testEjectability:
  let workerJs = generateWorkerJs(@[], @[], hasDO = true, webhookPaths = @["/stripe"])
  let doJs = generateDurableObjectJs(webhookPaths = @["/stripe"])
  let combined = workerJs & "\n" & doJs
  doAssert "import unanim" notin combined,
    "Generated JS with webhooks must be standalone - no framework imports"
  doAssert "require(\"unanim" notin combined,
    "Generated JS with webhooks must be standalone - no framework requires"

echo "test_webhook: Task 14 passed."

# --- Task 15: Worker JS webhook block declares reqUrl before DO block ---
block testReqUrlDeclaration:
  # When both webhooks and DO are present, reqUrl should be declared once
  let js = generateWorkerJs(@[], @[], hasDO = true, webhookPaths = @["/stripe"])
  let firstReqUrl = js.find("const reqUrl")
  let secondReqUrl = js.find("const reqUrl", firstReqUrl + 1)
  doAssert firstReqUrl >= 0,
    "reqUrl should be declared at least once"
  doAssert secondReqUrl == -1,
    "reqUrl should NOT be declared twice when both webhooks and DO are present"

echo "test_webhook: Task 15 passed."

# --- Task 16: WebhookMeta type exists ---
block testWebhookMetaType:
  var meta: WebhookMeta
  meta.path = "/test"
  meta.handlerBody = "proc() = discard"
  doAssert meta.path == "/test"
  doAssert meta.handlerBody == "proc() = discard"

echo "test_webhook: Task 16 passed."

echo "All webhook tests passed."
