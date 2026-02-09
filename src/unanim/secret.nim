## unanim/secret - Compile-time secret detection and validation.
##
## The `secret()` primitive marks a value that must be injected by the proxy
## at request time. The name must be a compile-time constant string.
##
## See VISION.md Section 3: secret(name: string)

import std/macros

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

      secrets.add(arg.strVal)
      return  # Don't recurse into children of a valid secret() call

  # Default: recurse into all children
  for i in 0 ..< n.len:
    collectSecrets(n[i], secrets)
