## unanim/secret - Compile-time secret detection and validation.
##
## The `secret()` primitive marks a value that must be injected by the proxy
## at request time. The name must be a compile-time constant string.
##
## See VISION.md Section 3: secret(name: string)

import std/macros

var secretRegistry* {.compileTime.}: seq[string] = @[]

proc registerSecret*(name: string) {.compileTime.} =
  ## Register a secret name in the global compile-time registry.
  ## Duplicates are ignored.
  if name notin secretRegistry:
    secretRegistry.add(name)

proc clearSecretRegistry*() {.compileTime.} =
  ## Clear the global secret registry. Useful for testing.
  secretRegistry = @[]

macro getRegisteredSecrets*(): seq[string] =
  ## Returns the current contents of the secret registry as a runtime value.
  ## Call this after all secret-containing code has been processed by macros.
  var bracket = newNimNode(nnkBracket)
  for s in secretRegistry:
    bracket.add(newStrLitNode(s))
  result = newCall(ident("@"), bracket)

template secret*(name: static[string]): string =
  ## Marks a secret reference. At compile time, the `static[string]` constraint
  ## ensures the argument is a compile-time constant. At runtime (before codegen
  ## replaces it), this returns a placeholder string.
  "<<SECRET:" & name & ">>"

proc collectSecrets*(n: NimNode, secrets: var seq[string]) =
  ## Recursively walks a NimNode AST and collects all `secret("name")` calls.
  ##
  ## For each `secret()` call found:
  ## - Validates the call has exactly one argument
  ## - Validates the argument is a string literal (nnkStrLit)
  ## - If validation fails, emits a structured compile-time error
  ## - If validation passes, appends the secret name to `secrets`
  ##
  ## This proc is called at compile time from macros that process user code.

  # Check for secret() call: nnkCall with first child being ident "secret"
  if n.kind in {nnkCall, nnkCommand} and n.len >= 1:
    if n[0].kind == nnkIdent and n[0].strVal == "secret":
      # Validate argument count
      if n.len != 2:
        error(
          "secret() requires exactly one argument.\n" &
          "  Got: " & $n.len.pred & " argument(s)\n" &
          "  Expected: secret(\"your-secret-name\")\n" &
          "  Fix: Provide a single string literal naming the secret.\n" &
          "  See: VISION.md Section 3 — secret(name: string)",
          n
        )

      let arg = n[1]

      # Validate the argument is a string literal
      if arg.kind != nnkStrLit:
        error(
          "secret() argument must be a compile-time string literal.\n" &
          "  Got: " & arg.repr & " (node kind: " & $arg.kind & ")\n" &
          "  Expected: secret(\"your-secret-name\")\n" &
          "  Why: Secret names must be known at compile time so the compiler\n" &
          "       can verify them against declared entitlements and generate\n" &
          "       the correct proxy configuration.\n" &
          "  Fix: Replace the dynamic expression with a string literal.\n" &
          "       If you need to choose between secrets dynamically, use\n" &
          "       an if/case expression where each branch calls secret()\n" &
          "       with a literal string.\n" &
          "  See: VISION.md Section 3 — secret(name: string)",
          arg
        )

      registerSecret(arg.strVal)
      secrets.add(arg.strVal)
      return  # Don't recurse into children of a valid secret() call

  # Default: recurse into all children
  for i in 0 ..< n.len:
    collectSecrets(n[i], secrets)

macro withSecrets*(varName: untyped, body: untyped): untyped =
  ## Wraps a block of code, walks the AST to collect all secret() references,
  ## and exposes the collected secret names as a `seq[string]` variable.
  ##
  ## Usage:
  ##   withSecrets(mySecrets):
  ##     let header = "Bearer " & secret("openai-key")
  ##     let other = secret("fal-key")
  ##   # mySecrets is now @["openai-key", "fal-key"]
  ##
  ## This macro:
  ## 1. Walks the body AST at compile time
  ## 2. Validates all secret() calls have string literal arguments
  ## 3. Collects the names into compile-time metadata
  ## 4. Emits the original body unchanged (secret template still produces placeholders)
  ## 5. Defines `varName` as a `seq[string]` containing the collected names

  var secrets: seq[string] = @[]
  collectSecrets(body, secrets)

  # Build the seq literal for the collected secret names
  var seqLit = newNimNode(nnkBracket)
  for s in secrets:
    seqLit.add(newStrLitNode(s))

  result = newStmtList()
  result.add(body)
  result.add(
    newLetStmt(
      varName,
      newCall(ident("@"), seqLit)
    )
  )
