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
