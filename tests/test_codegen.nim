import std/os
import std/strutils
import ../src/unanim/codegen
import ../src/unanim/secret
import ../src/unanim/proxyfetch

# --- Task 1: Module imports ---
block testModuleImports:
  doAssert true, "codegen module should import successfully"

echo "test_codegen: Task 1 passed."

# --- Task 2: generateWorkerJs minimal ---
block testGenerateWorkerJsMinimal:
  let js = generateWorkerJs(@[], @[])
  # Should contain an ES module default export with a fetch handler
  doAssert "export default" in js,
    "Generated JS should contain 'export default'"
  doAssert "async fetch(request, env, ctx)" in js,
    "Generated JS should contain a fetch handler"
  # Should contain the SCAFFOLD marker
  doAssert "SCAFFOLD(phase1, #4)" in js,
    "Generated JS should contain SCAFFOLD marker"

echo "test_codegen: Task 2 passed."

# --- Task 3: Secret injection logic in generated JS ---
block testGenerateWorkerJsSecretInjection:
  let js = generateWorkerJs(@["openai-key", "fal-key"], @[])
  # The injectSecrets function should be present
  doAssert "injectSecrets" in js,
    "Generated JS should contain injectSecrets function"
  # The replacement regex pattern should match our placeholder format
  doAssert "<<SECRET:" in js,
    "Generated JS should contain the SECRET placeholder pattern"
  # The env lookup should use uppercase conversion
  doAssert "toUpperCase" in js,
    "Generated JS should convert secret names to uppercase for env lookup"

echo "test_codegen: Task 3 passed."

# --- Task 4: generateWranglerToml ---
block testGenerateWranglerTomlBasic:
  let toml = generateWranglerToml("test-app", @[])
  doAssert "name = \"test-app\"" in toml,
    "wrangler.toml should contain app name"
  doAssert "main = \"worker.js\"" in toml,
    "wrangler.toml should reference worker.js"
  doAssert "compatibility_date" in toml,
    "wrangler.toml should contain compatibility_date"
  # Should contain the SCAFFOLD marker
  doAssert "SCAFFOLD(phase1, #4)" in toml,
    "wrangler.toml should contain SCAFFOLD marker"

echo "test_codegen: Task 4a passed."

block testGenerateWranglerTomlWithSecrets:
  let toml = generateWranglerToml("my-app", @["openai-key", "fal-key"])
  doAssert "name = \"my-app\"" in toml
  # Should NOT contain the actual secret values, just the binding declarations
  # Wrangler uses `wrangler secret put` for actual values
  doAssert "OPENAI_KEY" in toml,
    "wrangler.toml should list OPENAI_KEY env var"
  doAssert "FAL_KEY" in toml,
    "wrangler.toml should list FAL_KEY env var"

echo "test_codegen: Task 4b passed."

# --- Task 5: sanitizeEnvVar edge cases ---
block testSanitizeEnvVar:
  doAssert sanitizeEnvVar("openai-key") == "OPENAI_KEY"
  doAssert sanitizeEnvVar("fal-key") == "FAL_KEY"
  doAssert sanitizeEnvVar("jwt-signing-key") == "JWT_SIGNING_KEY"
  doAssert sanitizeEnvVar("my.dotted.name") == "MY_DOTTED_NAME"
  doAssert sanitizeEnvVar("ALREADY_UPPER") == "ALREADY_UPPER"
  doAssert sanitizeEnvVar("mixedCase-with.dots") == "MIXEDCASE_WITH_DOTS"

echo "test_codegen: Task 5 passed."

# --- Task 6: generateArtifacts end-to-end ---
# Set up stubs so proxyFetch/secret resolve
proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""

block testGenerateArtifactsEndToEnd:
  # Use the analyze macro to register metadata, then generate artifacts
  analyze:
    discard proxyFetch("https://api.openai.com/v1/chat",
      headers = {"Authorization": "Bearer " & secret("openai-key")},
      body = "test")
    discard proxyFetch("https://api.fal.ai/generate",
      headers = {"X-Key": secret("fal-key")})

  # Now generate the artifacts
  const outputDir = "/tmp/unanim_test_codegen"
  static:
    generateArtifacts("test-app", outputDir)

  # Verify the files were written at compile time
  doAssert fileExists(outputDir / "worker.js"),
    "worker.js should exist in output directory"
  doAssert fileExists(outputDir / "wrangler.toml"),
    "wrangler.toml should exist in output directory"

  # Read and verify contents
  let workerJs = readFile(outputDir / "worker.js")
  doAssert "export default" in workerJs,
    "worker.js should contain export default"
  doAssert "async fetch(request, env, ctx)" in workerJs,
    "worker.js should contain fetch handler"

  let wranglerToml = readFile(outputDir / "wrangler.toml")
  doAssert "name = \"test-app\"" in wranglerToml,
    "wrangler.toml should contain app name"
  doAssert "OPENAI_KEY" in wranglerToml,
    "wrangler.toml should reference OPENAI_KEY"
  doAssert "FAL_KEY" in wranglerToml,
    "wrangler.toml should reference FAL_KEY"

echo "test_codegen: Task 6 passed."

# --- Task 7: Validate generated JS syntax with node --check ---
block testGeneratedJsSyntax:
  const outputDir = "/tmp/unanim_test_codegen"
  const nodeCheck = gorgeEx("which node")
  when nodeCheck[1] == 0:
    const checkResult = gorgeEx("node --check " & outputDir & "/worker.js")
    doAssert checkResult[1] == 0,
      "Generated worker.js should be syntactically valid JS. node --check output: " & checkResult[0]
    echo "test_codegen: Task 7 passed (node --check verified)."
  else:
    echo "test_codegen: Task 7 skipped (node not available)."

# --- Task 8: Test wrangler.toml structure ---
block testWranglerTomlStructure:
  const outputDir = "/tmp/unanim_test_codegen"
  let toml = readFile(outputDir / "wrangler.toml")

  # Verify required fields are present as proper TOML key-value pairs
  doAssert toml.contains("name = \"test-app\""),
    "wrangler.toml must have name field"
  doAssert toml.contains("main = \"worker.js\""),
    "wrangler.toml must have main field pointing to worker.js"
  doAssert toml.contains("compatibility_date = \""),
    "wrangler.toml must have compatibility_date"
  doAssert toml.contains("[vars]"),
    "wrangler.toml must have [vars] section"

  # Verify no secret VALUES leak into the TOML (only names/instructions)
  doAssert not toml.contains("<<SECRET:"),
    "wrangler.toml must not contain secret placeholders"

echo "test_codegen: Task 8 passed."

# --- Task 9: Ejectability test ---
block testEjectability:
  const outputDir = "/tmp/unanim_test_codegen"
  let workerJs = readFile(outputDir / "worker.js")

  # The Worker must NOT import from any unanim module or framework
  doAssert not workerJs.contains("import unanim"),
    "Generated Worker must be standalone -- no framework imports"
  doAssert not workerJs.contains("require(\"unanim"),
    "Generated Worker must be standalone -- no framework requires"
  doAssert not workerJs.contains("from 'unanim"),
    "Generated Worker must be standalone -- no framework from-imports"

  # The Worker must be a valid ES module (has export default)
  doAssert workerJs.contains("export default"),
    "Generated Worker must be a valid ES module"

  # The Worker must have the full fetch handler (not a stub)
  doAssert workerJs.contains("await fetch("),
    "Generated Worker must contain the actual fetch forwarding logic"
  doAssert workerJs.contains("injectSecrets"),
    "Generated Worker must contain the secret injection function"

echo "test_codegen: Task 9 passed."

# --- Task 10: No secrets edge case ---
block testNoSecrets:
  # Generate artifacts with no secrets
  let js = generateWorkerJs(@[], @[])
  let toml = generateWranglerToml("no-secrets-app", @[])

  # Worker should still be valid
  doAssert "export default" in js
  doAssert "async fetch(request, env, ctx)" in js

  # TOML should have no secret references
  doAssert "name = \"no-secrets-app\"" in toml
  doAssert "wrangler secret put" notin toml,
    "wrangler.toml should not mention secret put when there are no secrets"

echo "test_codegen: Task 10 passed."

# --- Task 11: CORS headers ---
block testCorsHeaders:
  let js = generateWorkerJs(@[], @[])
  doAssert "Access-Control-Allow-Origin" in js,
    "Generated JS should contain CORS header"
  doAssert "OPTIONS" in js,
    "Generated JS should handle OPTIONS preflight"

echo "test_codegen: Task 11 passed."

# --- Task 12: generateDurableObjectJs basic structure ---
block testGenerateDurableObjectJsBasic:
  let js = generateDurableObjectJs()
  doAssert "export class UserDO" in js,
    "DO JS should export UserDO class"
  doAssert "constructor(state, env)" in js,
    "DO should have constructor with state and env"
  doAssert "async fetch(request)" in js,
    "DO should have async fetch method"
  doAssert "state.storage.sql" in js,
    "DO should access SQLite via state.storage.sql"

echo "test_codegen: Task 12 passed."

# --- Task 13: DO SQLite table creation ---
block testDurableObjectSqliteTable:
  let js = generateDurableObjectJs()
  doAssert "CREATE TABLE IF NOT EXISTS events" in js,
    "DO should create events table"
  doAssert "sequence INTEGER PRIMARY KEY" in js,
    "Events table should have sequence as primary key"
  doAssert "timestamp TEXT" in js,
    "Events table should have timestamp column"
  doAssert "event_type TEXT" in js,
    "Events table should have event_type column"
  doAssert "schema_version INTEGER" in js,
    "Events table should have schema_version column"
  doAssert "payload TEXT" in js,
    "Events table should have payload column"
  doAssert "state_hash_after TEXT" in js,
    "Events table should have state_hash_after column"
  doAssert "parent_hash TEXT" in js,
    "Events table should have parent_hash column"

echo "test_codegen: Task 13 passed."

# --- Task 14: DO event endpoints ---
block testDurableObjectEndpoints:
  let js = generateDurableObjectJs()
  doAssert "storeEvents" in js,
    "DO should have storeEvents method"
  doAssert "INSERT INTO events" in js,
    "DO should insert events into SQLite"
  doAssert "getEvents" in js,
    "DO should have getEvents method"
  doAssert "WHERE sequence > ?" in js,
    "DO should filter events by sequence"
  doAssert "ORDER BY sequence ASC" in js,
    "DO should return events ordered by sequence"
  doAssert "getStatus" in js,
    "DO should have getStatus method"
  doAssert "COUNT(*)" in js,
    "DO status should return event count"

echo "test_codegen: Task 14 passed."

# --- Task 15: DO CORS support ---
block testDurableObjectCors:
  let js = generateDurableObjectJs()
  doAssert "Access-Control-Allow-Origin" in js,
    "DO should have CORS headers"
  doAssert "OPTIONS" in js,
    "DO should handle OPTIONS preflight"

echo "test_codegen: Task 15 passed."

# --- Task 16: generateWranglerToml with DO bindings ---
block testWranglerTomlWithDO:
  let toml = generateWranglerToml("do-app", @["openai-key"], hasDO = true)
  doAssert "name = \"do-app\"" in toml
  doAssert "[durable_objects]" in toml
  doAssert "USER_DO" in toml
  doAssert "UserDO" in toml
  doAssert "[[migrations]]" in toml
  doAssert "tag = \"v1\"" in toml
  doAssert "new_sqlite_classes" in toml
  doAssert "OPENAI_KEY" in toml

echo "test_codegen: Task 16 passed."

# --- Task 17: generateWranglerToml without DO (backwards compat) ---
block testWranglerTomlWithoutDO:
  let toml = generateWranglerToml("no-do-app", @[])
  doAssert "[durable_objects]" notin toml
  doAssert "[[migrations]]" notin toml

echo "test_codegen: Task 17 passed."

# --- Task 18: generateWorkerJs with DO routing ---
block testWorkerJsWithDORouting:
  let js = generateWorkerJs(@[], @[], hasDO = true)
  doAssert "USER_DO" in js
  doAssert "idFromName" in js
  doAssert "X-User-Id" in js
  doAssert "user_id" in js
  doAssert "/do/" in js
  doAssert "injectSecrets" in js

echo "test_codegen: Task 18 passed."

# --- Task 19: generateWorkerJs without DO (backwards compat) ---
block testWorkerJsWithoutDO:
  let js = generateWorkerJs(@[], @[])
  doAssert "USER_DO" notin js
  doAssert "idFromName" notin js
  doAssert "export default" in js

echo "test_codegen: Task 19 passed."

# --- Task 20: Worker CORS updated for DO ---
block testWorkerCorsWithDO:
  let js = generateWorkerJs(@[], @[], hasDO = true)
  doAssert "GET, POST, OPTIONS" in js
  doAssert "X-User-Id" in js

echo "test_codegen: Task 20 passed."

# --- Task 21: End-to-end artifacts include DO ---
block testGenerateArtifactsWithDO:
  const outputDir = "/tmp/unanim_test_codegen"
  let workerJs = readFile(outputDir / "worker.js")
  doAssert "export class UserDO" in workerJs,
    "worker.js should include UserDO class"
  doAssert "CREATE TABLE IF NOT EXISTS events" in workerJs,
    "worker.js should include SQLite table creation"
  doAssert "export default" in workerJs,
    "worker.js should still have default Worker export"
  let wranglerToml = readFile(outputDir / "wrangler.toml")
  doAssert "[durable_objects]" in wranglerToml,
    "wrangler.toml should have DO section"
  doAssert "UserDO" in wranglerToml,
    "wrangler.toml should reference UserDO"
  doAssert "[[migrations]]" in wranglerToml,
    "wrangler.toml should have migrations"

echo "test_codegen: Task 21 passed."

# --- Task 22: Node syntax validation for combined Worker+DO ---
block testCombinedJsSyntax:
  const outputDir = "/tmp/unanim_test_codegen"
  const nodeCheck = gorgeEx("which node")
  when nodeCheck[1] == 0:
    const checkResult = gorgeEx("node --check " & outputDir & "/worker.js")
    doAssert checkResult[1] == 0,
      "Combined worker.js (Worker+DO) should be syntactically valid JS. Error: " & checkResult[0]
    echo "test_codegen: Task 22 passed (node --check verified)."
  else:
    echo "test_codegen: Task 22 skipped (node not available)."

# --- Task 23: Ejectability for combined output ---
block testCombinedEjectability:
  const outputDir = "/tmp/unanim_test_codegen"
  let workerJs = readFile(outputDir / "worker.js")
  doAssert not workerJs.contains("import unanim"),
    "Combined worker.js must be standalone -- no framework imports"
  doAssert not workerJs.contains("require(\"unanim"),
    "Combined worker.js must be standalone -- no framework requires"
  doAssert "export default" in workerJs,
    "Combined worker.js must have default Worker export"
  doAssert "export class UserDO" in workerJs,
    "Combined worker.js must have named DO export"

echo "test_codegen: Task 23 passed."

# --- Task 24: DO has SHA-256 hashing via Web Crypto API ---
block testDurableObjectHashing:
  let js = generateDurableObjectJs()
  doAssert "crypto.subtle.digest" in js,
    "DO should use Web Crypto API for SHA-256"
  doAssert "canonicalForm" in js,
    "DO should have canonicalForm function"
  doAssert "hashEvent" in js,
    "DO should have hashEvent function"

echo "test_codegen: Task 24 passed."

# --- Task 25: DO has hash chain verification ---
block testDurableObjectVerification:
  let js = generateDurableObjectJs()
  doAssert "verifyChain" in js,
    "DO should have verifyChain method"
  doAssert "parent_hash" in js,
    "DO verification should check parent_hash linkage"

echo "test_codegen: Task 25 passed."

echo "All codegen tests passed."
