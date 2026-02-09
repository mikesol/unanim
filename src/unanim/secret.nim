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
