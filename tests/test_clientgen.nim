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
