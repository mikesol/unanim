{.hint[XDeclaredButNotUsed]: off.}
import std/strutils
import ../src/unanim/clientgen

block testHtmlShellBasic:
  let html = generateHtmlShell("app.js")
  doAssert "<!DOCTYPE html>" in html, "HTML shell must start with DOCTYPE"
  doAssert "<script src=\"app.js\"></script>" in html,
    "HTML shell must include script tag for app.js"
  doAssert "<meta charset=\"utf-8\">" in html,
    "HTML shell must include charset meta tag"
  doAssert "</html>" in html, "HTML shell must be well-formed with closing html tag"

block testHtmlShellCustomScript:
  let html = generateHtmlShell("custom-bundle.js")
  doAssert "<script src=\"custom-bundle.js\"></script>" in html,
    "HTML shell must use the provided script filename"

block testHtmlShellCustomTitle:
  let html = generateHtmlShell("app.js", title = "My App")
  doAssert "<title>My App</title>" in html,
    "HTML shell must use the provided title"

echo "test_clientgen: Task 1 passed."

import std/macros

block testStripSecretsFromAst:
  # Build an AST that represents: "Bearer " & secret("openai-key")
  # After stripping, secret("openai-key") should become ""
  static:
    let ast = newNimNode(nnkInfix).add(
      ident("&"),
      newStrLitNode("Bearer "),
      newCall(ident("secret"), newStrLitNode("openai-key"))
    )
    let stripped = stripSecrets(ast)
    # The secret call should be replaced with empty string
    doAssert stripped[2].kind == nnkStrLit,
      "secret() call should be replaced with StrLit, got " & $stripped[2].kind
    doAssert stripped[2].strVal == "",
      "secret() call should be replaced with empty string, got " & stripped[2].strVal

block testStripSecretsPreservesNonSecrets:
  static:
    let ast = newNimNode(nnkInfix).add(
      ident("&"),
      newStrLitNode("Hello "),
      newStrLitNode("World")
    )
    let stripped = stripSecrets(ast)
    doAssert stripped[1].strVal == "Hello ",
      "Non-secret strings should be preserved"
    doAssert stripped[2].strVal == "World",
      "Non-secret strings should be preserved"

block testStripSecretsDeepNested:
  # secret("k1") nested inside multiple concat levels
  static:
    let inner = newNimNode(nnkInfix).add(
      ident("&"),
      newStrLitNode("prefix"),
      newCall(ident("secret"), newStrLitNode("k1"))
    )
    let outer = newNimNode(nnkInfix).add(
      ident("&"),
      inner,
      newCall(ident("secret"), newStrLitNode("k2"))
    )
    let stripped = stripSecrets(outer)
    # Both secret calls should be replaced with ""
    # outer[1] is stripped inner; outer[1][2] was secret("k1") -> ""
    doAssert stripped[1][2].kind == nnkStrLit
    doAssert stripped[1][2].strVal == ""
    # outer[2] was secret("k2") -> ""
    doAssert stripped[2].kind == nnkStrLit
    doAssert stripped[2].strVal == ""

echo "test_clientgen: Task 2 passed."

block testCollectSecretNamesFromArgs:
  static:
    let ast = newNimNode(nnkInfix).add(
      ident("&"),
      newStrLitNode("Bearer "),
      newCall(ident("secret"), newStrLitNode("openai-key"))
    )
    var names: seq[string] = @[]
    collectSecretNamesFromNode(ast, names)
    doAssert names == @["openai-key"],
      "Should collect 'openai-key', got " & $names

block testCollectMultipleSecretNames:
  static:
    let ast = newStmtList(
      newCall(ident("secret"), newStrLitNode("k1")),
      newCall(ident("secret"), newStrLitNode("k2")),
      newStrLitNode("no-secret-here")
    )
    var names: seq[string] = @[]
    collectSecretNamesFromNode(ast, names)
    doAssert names.len == 2
    doAssert "k1" in names
    doAssert "k2" in names

block testCollectNoSecrets:
  static:
    let ast = newNimNode(nnkInfix).add(
      ident("&"),
      newStrLitNode("Hello"),
      newStrLitNode("World")
    )
    var names: seq[string] = @[]
    collectSecretNamesFromNode(ast, names)
    doAssert names.len == 0, "No secret names expected, got " & $names

echo "test_clientgen: Task 3 passed."

# Stubs for proxyFetch and secret so rewritten code can compile
proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""
proc secret(name: string): string = ""

# We need stubs for the rewritten output -- fetch and encodeURIComponent
proc fetch(url: string, headers: openArray[(string, string)] = @[],
           body: string = ""): string = "fetch_result"
proc encodeURIComponent(s: string): string = s

block testRewriteDirectFetch:
  # A proxyFetch with no secrets should be rewritten to fetch()
  rewriteProxyFetch("https://worker.example.com/proxy"):
    discard proxyFetch("https://api.example.com/public", body = "test")
  # The block should compile and run -- the proxyFetch becomes fetch
  doAssert true, "DirectFetch rewrite should compile and execute"

echo "test_clientgen: Task 4a passed."

block testRewriteProxyRequired:
  # A proxyFetch with secrets should be rewritten to target the worker URL
  rewriteProxyFetch("https://worker.example.com/proxy"):
    discard proxyFetch("https://api.openai.com/v1/chat",
      headers = {"Authorization": "Bearer " & secret("openai-key")},
      body = "test")
  # The block should compile and run -- secrets are stripped
  doAssert true, "ProxyRequired rewrite should compile and execute"

echo "test_clientgen: Task 4b passed."

# Use a compile-time macro to inspect the rewritten AST as a string
macro getRewrittenRepr(workerUrl: static[string], body: untyped): string =
  let rewritten = rewriteNode(body, workerUrl)
  result = newStrLitNode(rewritten.repr)

block testDirectFetchReprContainsOriginalUrl:
  let code = getRewrittenRepr("https://worker.example.com/proxy"):
    discard proxyFetch("https://api.example.com/public", body = "test")
  doAssert "fetch" in code, "Rewritten code should call fetch, got: " & code
  doAssert "proxyFetch" notin code,
    "Rewritten code should NOT contain proxyFetch, got: " & code
  doAssert "api.example.com/public" in code,
    "DirectFetch should keep original URL, got: " & code

block testProxyRequiredReprContainsWorkerUrl:
  let code = getRewrittenRepr("https://worker.example.com/proxy"):
    discard proxyFetch("https://api.openai.com/v1/chat",
      headers = {"Authorization": "Bearer " & secret("openai-key")},
      body = "test")
  doAssert "fetch" in code, "Rewritten code should call fetch, got: " & code
  doAssert "proxyFetch" notin code,
    "Rewritten code should NOT contain proxyFetch, got: " & code
  doAssert "worker.example.com/proxy" in code,
    "ProxyRequired should target worker URL, got: " & code
  doAssert "X-Unanim-Secrets" in code,
    "ProxyRequired should include secret metadata header, got: " & code
  doAssert "openai-key" in code,
    "Secret metadata header should include secret name, got: " & code

block testProxyRequiredReprDoesNotContainSecretMarker:
  let code = getRewrittenRepr("https://worker.example.com/proxy"):
    discard proxyFetch("https://api.openai.com/v1/chat",
      headers = {"Authorization": "Bearer " & secret("openai-key")},
      body = "test")
  doAssert "<<SECRET:" notin code,
    "Rewritten code should NOT contain secret placeholder markers, got: " & code
  doAssert "secret(" notin code,
    "Rewritten code should NOT contain secret() calls, got: " & code

echo "test_clientgen: Task 5 passed."

block testScanForSecretsFindsPlaceholders:
  let jsCode = """
    var x = "<<SECRET:openai-key>>";
    fetch("https://api.com", {"Authorization": "Bearer <<SECRET:fal-key>>"});
  """
  let found = scanForSecrets(jsCode, @["openai-key", "fal-key"])
  doAssert found.len == 2, "Should find 2 leaked secrets, got " & $found.len
  doAssert "openai-key" in found
  doAssert "fal-key" in found

block testScanForSecretsCleanOutput:
  let jsCode = """
    var x = fetch("https://worker.com/proxy?target=api.com",
      {"X-Unanim-Secrets": "openai-key"});
  """
  # The secret NAME in metadata header is ok -- it's not the VALUE
  # scanForSecrets checks for <<SECRET:...>> placeholder pattern
  let found = scanForSecrets(jsCode, @["openai-key"])
  doAssert found.len == 0,
    "Clean output should have no leaked secrets, got " & $found

block testScanForSecretsPartialMatch:
  let jsCode = """
    var apiKey = "sk-proj-abc123";
    var token = "<<SECRET:my-token>>";
  """
  let found = scanForSecrets(jsCode, @["my-token", "other-token"])
  doAssert found.len == 1, "Should find 1 leaked secret, got " & $found.len
  doAssert "my-token" in found

echo "test_clientgen: Task 6 passed."

block testCompileClientJsBasic:
  # Compile a minimal Nim program to JS at compile time
  const js = compileClientJs("""
    proc main() =
      echo "hello from client"
    main()
  """)
  doAssert js.len > 0, "Compiled JS should not be empty"
  # Nim's JS backend always produces some output
  doAssert "function" in js or "var" in js,
    "Compiled JS should contain JS constructs, got: " & js[0..min(200, js.len-1)]

echo "test_clientgen: Task 7 passed."
