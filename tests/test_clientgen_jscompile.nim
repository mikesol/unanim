## Integration test: rewrite proxyFetch, compile to JS, verify output.
## This test exercises the full pipeline:
## 1. User writes Nim with proxyFetch + secret calls
## 2. rewriteProxyFetch macro rewrites the AST at compile time
## 3. The rewritten code is compiled to JS via nim js
## 4. The resulting JS has no secrets and calls the Worker for proxy-required fetches

{.hint[XDeclaredButNotUsed]: off.}
import std/strutils
import std/macros
import ../src/unanim/clientgen

const workerUrl = "https://my-app.workers.dev/proxy"

# Test 1: Generate the rewritten Nim source as a string and verify it
macro getRewrittenSource(workerUrl: static[string], body: untyped): string =
  let rewritten = rewriteNode(body, workerUrl)
  result = newStrLitNode(rewritten.repr)

# We need stubs to make proxyFetch and secret resolve in untyped context
proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""
proc secret(name: string): string = ""

block testRewrittenSourceNoSecretPlaceholders:
  let source = getRewrittenSource(workerUrl):
    let data = proxyFetch("https://api.openai.com/v1/chat",
      headers = {"Authorization": "Bearer " & secret("openai-key")},
      body = "{\"prompt\": \"hello\"}")

  # Verify: no <<SECRET:...>> placeholders
  doAssert "<<SECRET:" notin source,
    "Rewritten source should not contain secret placeholders, got: " & source
  # Verify: no secret() calls
  doAssert "secret(" notin source,
    "Rewritten source should not contain secret() calls, got: " & source
  # Verify: worker URL is present
  doAssert workerUrl in source,
    "Rewritten source should target worker URL, got: " & source
  # Verify: original API URL is NOT the fetch target (it's in the query param)
  doAssert "fetch(\"https://api.openai.com" notin source,
    "Rewritten source should not directly fetch the API URL, got: " & source

echo "test_clientgen_jscompile: Test 1 passed."

# Test 2: DirectFetch keeps original URL
block testRewrittenSourceDirectFetch:
  let source = getRewrittenSource(workerUrl):
    let data = proxyFetch("https://api.example.com/public", body = "test")

  doAssert "fetch" in source, "Should use fetch, got: " & source
  doAssert "proxyFetch" notin source,
    "Should not contain proxyFetch, got: " & source
  doAssert "api.example.com/public" in source,
    "DirectFetch should keep original URL, got: " & source
  doAssert workerUrl notin source,
    "DirectFetch should NOT target worker URL, got: " & source

echo "test_clientgen_jscompile: Test 2 passed."

# Test 3: HTML shell is well-formed
block testHtmlShellStandalone:
  let html = generateHtmlShell("app.js", title = "Test App")
  doAssert html.startsWith("<!DOCTYPE html>"),
    "HTML must start with DOCTYPE"
  doAssert "<script src=\"app.js\"></script>" in html,
    "HTML must reference the compiled JS"
  doAssert "<title>Test App</title>" in html
  doAssert "</html>" in html
  # Verify it's standalone -- no external dependencies
  doAssert "http://" notin html and "https://" notin html,
    "HTML shell should have no external dependencies"

echo "test_clientgen_jscompile: Test 3 passed."

# Test 4: scanForSecrets on clean rewritten source
block testScanRewrittenSource:
  let source = getRewrittenSource(workerUrl):
    let data = proxyFetch("https://api.openai.com/v1/chat",
      headers = {"Authorization": "Bearer " & secret("openai-key"),
                 "X-Custom": secret("custom-key")},
      body = "test")

  let leaked = scanForSecrets(source, @["openai-key", "custom-key"])
  doAssert leaked.len == 0,
    "Rewritten source should have no leaked secrets, but found: " & $leaked

echo "test_clientgen_jscompile: Test 4 passed."

# Test 5: Multiple proxyFetch calls in a block -- mixed rewriting
block testMixedRewriting:
  let source = getRewrittenSource(workerUrl):
    let proxied = proxyFetch("https://api.openai.com/v1/chat",
      headers = {"Auth": "Bearer " & secret("key1")},
      body = "test")
    let direct = proxyFetch("https://api.example.com/public", body = "test")

  # Both should use fetch, not proxyFetch
  doAssert "proxyFetch" notin source,
    "All proxyFetch calls should be rewritten, got: " & source
  # Worker URL should appear (for the proxied call)
  doAssert workerUrl in source,
    "Proxied call should target worker URL, got: " & source
  # Original public URL should appear (for the direct call)
  doAssert "api.example.com/public" in source,
    "Direct call should keep original URL, got: " & source

echo "test_clientgen_jscompile: Test 5 passed."

# Test 6: Compile rewritten Nim to JS and verify output
# This test uses compileClientJs to actually invoke nim js at compile time
block testNimJsCompilationNoSecrets:
  # A minimal Nim program that uses our rewritten fetch pattern
  # (We can't use the macro directly in the string -- we write pre-rewritten code)
  const js = compileClientJs("""
    proc fetch(url: string): string = ""
    proc encodeURIComponent(s: string): string = s

    proc main() =
      # Simulates what rewriteProxyFetch would produce for a ProxyRequired call
      let result = fetch("https://my-app.workers.dev/proxy?target=https://api.openai.com/v1/chat")
      # Simulates what rewriteProxyFetch would produce for a DirectFetch call
      let direct = fetch("https://api.example.com/public")

    main()
  """)

  doAssert js.len > 0, "Compiled JS should not be empty"

  # Verify no secret placeholders leaked into the JS
  let leaked = scanForSecrets(js, @["openai-key", "fal-key", "custom-key"])
  doAssert leaked.len == 0,
    "Compiled JS should contain no secret placeholders, but found: " & $leaked

  # Verify the JS does not contain the literal string "<<SECRET:"
  doAssert "<<SECRET:" notin js,
    "Compiled JS should not contain any secret placeholder pattern"

echo "test_clientgen_jscompile: Test 6 passed."

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

echo "All client codegen integration tests passed."
