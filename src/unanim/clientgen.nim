## unanim/clientgen - Compile-time client code generation.
##
## Rewrites proxyFetch calls for client execution, generates HTML shell,
## compiles Nim to JS, and verifies no secrets leak into generated output.
##
## SCAFFOLD(Phase 1, #5): The HTML shell and client bootstrap are temporary.
## They will be replaced by the islands DSL and full client runtime in later phases.
##
## See VISION.md Section 2, Principles 1 and 7; Appendix C.

import std/macros
import std/strutils

proc isSecretCall(n: NimNode): bool =
  ## Check if a node is a secret("name") call.
  if n.kind in {nnkCall, nnkCommand} and n.len >= 1:
    if n[0].kind == nnkIdent and n[0].strVal == "secret":
      return true
  return false

proc stripSecrets*(n: NimNode): NimNode =
  ## Recursively walk a NimNode tree and replace every secret("name") call
  ## with an empty string literal. Returns a new tree (does not mutate input).
  if isSecretCall(n):
    return newStrLitNode("")
  result = copyNimNode(n)
  for i in 0..<n.len:
    result.add(stripSecrets(n[i]))

proc collectSecretNamesFromNode*(n: NimNode, names: var seq[string]) =
  ## Recursively collect all secret names from secret("name") calls in a tree.
  if isSecretCall(n):
    if n.len > 1 and n[1].kind == nnkStrLit:
      names.add(n[1].strVal)
    return  # don't recurse into the secret call itself
  for i in 0..<n.len:
    collectSecretNamesFromNode(n[i], names)

proc isCallTo(n: NimNode, name: string): bool =
  ## Check if a node is a call to the given identifier.
  if n.kind in {nnkCall, nnkCommand} and n.len > 0:
    if n[0].kind == nnkIdent and n[0].strVal == name:
      return true
  return false

proc containsSecretCall(n: NimNode): bool =
  ## Recursively check whether a NimNode tree contains any secret() calls.
  if isSecretCall(n):
    return true
  for i in 0..<n.len:
    if containsSecretCall(n[i]):
      return true
  return false

proc extractProxyFetchFromStmt(n: NimNode): NimNode =
  ## If n is or wraps a proxyFetch call, return the call node. Otherwise nil.
  if isCallTo(n, "proxyFetch"):
    return n
  if n.kind in {nnkLetSection, nnkVarSection}:
    for identDef in n:
      if identDef.kind == nnkIdentDefs and identDef.len >= 3:
        let value = identDef[^1]
        if isCallTo(value, "proxyFetch"):
          return value
  if n.kind == nnkDiscardStmt and n.len > 0 and isCallTo(n[0], "proxyFetch"):
    return n[0]
  if n.kind == nnkAsgn and n.len >= 2 and isCallTo(n[1], "proxyFetch"):
    return n[1]
  return nil

proc buildFetchCall(pfCall: NimNode, workerUrl: string): NimNode =
  ## Rewrite a single proxyFetch call node into a fetch call.
  ## - ProxyRequired: target the worker URL, strip secrets, add secret metadata header
  ## - DirectFetch: target original URL directly with fetch()
  let hasSecrets = containsSecretCall(pfCall)

  if not hasSecrets:
    # DirectFetch: just rename proxyFetch -> fetch
    result = copyNimNode(pfCall)
    result.add(ident("fetch"))
    for i in 1..<pfCall.len:
      result.add(pfCall[i].copyNimTree())
    return

  # ProxyRequired: rewrite URL to target worker, strip secrets
  # Collect secret names for metadata header
  var secretNames: seq[string] = @[]
  collectSecretNamesFromNode(pfCall, secretNames)

  # Extract the URL argument (first positional arg after the function ident)
  var urlArg: NimNode = nil
  var headerArgs: seq[NimNode] = @[]
  var bodyArg: NimNode = nil

  for i in 1..<pfCall.len:
    let arg = pfCall[i]
    if arg.kind == nnkExprEqExpr:
      let argName = arg[0].strVal
      if argName == "headers":
        headerArgs.add(stripSecrets(arg[1]))
      elif argName == "body":
        bodyArg = stripSecrets(arg[1])
    else:
      if urlArg == nil:
        urlArg = arg

  # Build the worker URL: workerUrl & "?target=" & encodeURIComponent(originalUrl)
  let workerUrlExpr = newNimNode(nnkInfix).add(
    ident("&"),
    newNimNode(nnkInfix).add(
      ident("&"),
      newStrLitNode(workerUrl & "?target="),
      newCall(ident("encodeURIComponent"), urlArg.copyNimTree())
    ),
    newStrLitNode("")
  )

  # Build the secret names metadata: comma-separated secret names
  let secretNamesStr = secretNames.join(",")

  result = newCall(ident("fetch"))
  result.add(workerUrlExpr)

  # Build headers: original (stripped) + X-Unanim-Secrets metadata header
  # Use nnkBracket with nnkTupleConstr children for openArray[(string, string)]
  var allHeaders = newNimNode(nnkBracket)
  if headerArgs.len > 0:
    # Copy existing header pairs from the stripped table constructor
    let headerTable = headerArgs[0]
    if headerTable.kind == nnkTableConstr:
      for pair in headerTable:
        # Convert nnkExprColonExpr to nnkTupleConstr for (string, string) pairs
        if pair.kind == nnkExprColonExpr:
          allHeaders.add(newNimNode(nnkTupleConstr).add(
            pair[0].copyNimTree(),
            pair[1].copyNimTree()
          ))
        else:
          allHeaders.add(pair.copyNimTree())
    else:
      # If it's not a table constructor, add it as-is
      allHeaders.add(headerTable.copyNimTree())

  # Add the secret names metadata header
  allHeaders.add(
    newNimNode(nnkTupleConstr).add(
      newStrLitNode("X-Unanim-Secrets"),
      newStrLitNode(secretNamesStr)
    )
  )

  result.add(newNimNode(nnkExprEqExpr).add(
    ident("headers"),
    allHeaders
  ))

  if bodyArg != nil:
    result.add(newNimNode(nnkExprEqExpr).add(
      ident("body"),
      bodyArg
    ))

proc rewriteNode*(n: NimNode, workerUrl: string): NimNode =
  ## Recursively rewrite a single node, replacing proxyFetch calls with fetch calls.
  let pfCall = extractProxyFetchFromStmt(n)
  if pfCall != nil:
    # Replace the proxyFetch call with the rewritten fetch call
    let fetchCall = buildFetchCall(pfCall, workerUrl)
    if n.kind == nnkDiscardStmt:
      result = newNimNode(nnkDiscardStmt)
      result.add(fetchCall)
    elif n.kind in {nnkLetSection, nnkVarSection}:
      result = copyNimNode(n)
      for identDef in n:
        if identDef.kind == nnkIdentDefs and identDef.len >= 3:
          let value = identDef[^1]
          if isCallTo(value, "proxyFetch"):
            var newIdentDef = newNimNode(nnkIdentDefs)
            for j in 0..<identDef.len - 1:
              newIdentDef.add(identDef[j].copyNimTree())
            newIdentDef.add(fetchCall)
            result.add(newIdentDef)
          else:
            result.add(identDef.copyNimTree())
        else:
          result.add(identDef.copyNimTree())
    elif n.kind == nnkAsgn:
      result = newNimNode(nnkAsgn)
      result.add(n[0].copyNimTree())
      result.add(fetchCall)
    else:
      result = fetchCall
    return

  # Not a proxyFetch -- recurse into children
  result = copyNimNode(n)
  for i in 0..<n.len:
    result.add(rewriteNode(n[i], workerUrl))

macro rewriteProxyFetch*(workerUrl: static[string], body: untyped): untyped =
  ## Rewrite all proxyFetch calls in the body:
  ## - ProxyRequired calls (containing secrets) target the Worker URL
  ## - DirectFetch calls (no secrets) become plain fetch()
  ## - All secret() markers are stripped from rewritten calls
  ##
  ## Usage:
  ##   rewriteProxyFetch("https://my-worker.dev/proxy"):
  ##     let data = proxyFetch("https://api.com",
  ##       headers = {"Auth": "Bearer " & secret("key")},
  ##       body = "test")
  ##
  ## After rewriting, the proxyFetch becomes a fetch() to the worker URL
  ## with secrets stripped and secret names sent as metadata.
  result = rewriteNode(body, workerUrl)

proc scanForSecrets*(jsOutput: string, secretNames: seq[string]): seq[string] =
  ## Scan generated JS output for leaked secrets.
  ## Checks for:
  ## 1. <<SECRET:name>> placeholder patterns (should never appear in output)
  ##
  ## Returns a list of secret names found in the output.
  ## An empty list means the output is clean.
  result = @[]
  for name in secretNames:
    let placeholder = "<<SECRET:" & name & ">>"
    if placeholder in jsOutput:
      if name notin result:
        result.add(name)

macro compileClientJs*(nimSource: static[string]): string =
  ## Compile a Nim source string to JavaScript at compile time using `nim js`.
  ## Returns the compiled JS as a string.
  ##
  ## Uses gorgeEx to invoke the Nim compiler during macro expansion.
  ## This is the same pattern demonstrated in the PoC (VISION.md Appendix C).
  let tmpDir = "/tmp/unanim_clientgen"
  discard gorge("mkdir -p " & tmpDir)

  let srcFile = tmpDir & "/client_src.nim"
  let jsFile = tmpDir & "/client_src.js"

  # Write the source file at compile time
  # Dedent: find minimum indentation across non-empty lines and strip it
  var lines = nimSource.splitLines()
  var minIndent = high(int)
  for line in lines:
    if line.strip().len > 0:
      var indent = 0
      for ch in line:
        if ch == ' ':
          indent += 1
        else:
          break
      if indent < minIndent:
        minIndent = indent
  if minIndent == high(int):
    minIndent = 0
  var dedented = ""
  for i, line in lines:
    if i > 0:
      dedented.add("\n")
    if line.strip().len > 0 and line.len >= minIndent:
      dedented.add(line[minIndent..^1])
    else:
      dedented.add(line)
  # Trim leading/trailing blank lines
  dedented = dedented.strip(chars = {'\n', '\r'})
  writeFile(srcFile, dedented)

  # Find nim compiler
  let nimBin = gorge("which nim 2>/dev/null || echo $HOME/.nimble/bin/nim").strip()

  let cmd = nimBin & " js --opt:size -d:danger --hints:off -o:" & jsFile & " " & srcFile
  let (output, exitCode) = gorgeEx(cmd)

  if exitCode != 0:
    error("nim js compilation failed:\n" & output)

  let jsContent = staticRead(jsFile)
  result = newStrLitNode(jsContent)

proc generateHtmlShell*(scriptFile: string, title: string = "App"): string =
  ## Generate a minimal standalone HTML shell that loads the compiled JS.
  ## SCAFFOLD(Phase 1, #5): This is a minimal scaffold. Will be replaced
  ## by the islands DSL in later phases.
  result = "<!DOCTYPE html>\n" &
    "<html>\n" &
    "<head>\n" &
    "  <meta charset=\"utf-8\">\n" &
    "  <title>" & title & "</title>\n" &
    "</head>\n" &
    "<body>\n" &
    "  <script src=\"" & scriptFile & "\"></script>\n" &
    "</body>\n" &
    "</html>\n"
