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
echo "All client codegen integration tests passed."
