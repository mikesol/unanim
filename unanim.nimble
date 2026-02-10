# Package
version       = "0.1.0"
author        = "mikesol"
description   = "Compile-time framework that eliminates the backend"
license       = "MIT"
srcDir        = "src"

# Dependencies
requires "nim >= 2.0.0"

# Tasks
task test, "Run tests":
  exec "nim c -r tests/test_unanim.nim"
  exec "nim c -r tests/test_secret.nim"
  exec "nim c -r tests/test_secret_errors.nim"
  exec "nim c -r tests/test_proxyfetch.nim"
  exec "nim c -r tests/test_codegen.nim"
  exec "nim c -r tests/test_clientgen.nim"
  exec "nim c -r tests/test_clientgen_jscompile.nim"
  exec "nim c -r tests/test_eventlog.nim"
  exec "nim c -r tests/test_guard.nim"
  exec "nim c -r tests/test_budget.nim"
  exec "nim c -r tests/test_webhook.nim"
