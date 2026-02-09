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
