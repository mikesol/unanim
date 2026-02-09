## Tests that verify compile-time error detection for invalid secret() usage.
##
## These tests use `compiles()` to check that invalid code correctly
## fails to compile, without actually triggering the error.

import ../src/unanim/secret
import std/macros

block testDynamicArgInWithSecrets:
  # Build an AST that simulates: withSecrets block containing secret(myVar)
  # where myVar is an ident (not a string literal).
  # collectSecrets should reject this.
  #
  # We test this by checking that a macro which calls collectSecrets
  # with an ident argument does not compile.
  doAssert not compiles(
    block:
      macro testBadSecret(): untyped =
        let badAst = newCall(ident("secret"), ident("someVariable"))
        var secrets: seq[string] = @[]
        collectSecrets(badAst, secrets)
        result = newStmtList()
      testBadSecret()
  ), "secret() with a non-literal argument should fail at compile time"

block testZeroArgsSecret:
  doAssert not compiles(
    block:
      macro testNoArgSecret(): untyped =
        let badAst = newCall(ident("secret"))
        var secrets: seq[string] = @[]
        collectSecrets(badAst, secrets)
        result = newStmtList()
      testNoArgSecret()
  ), "secret() with zero arguments should fail at compile time"

block testTwoArgsSecret:
  doAssert not compiles(
    block:
      macro testTwoArgSecret(): untyped =
        let badAst = newCall(ident("secret"),
          newStrLitNode("key1"), newStrLitNode("key2"))
        var secrets: seq[string] = @[]
        collectSecrets(badAst, secrets)
        result = newStmtList()
      testTwoArgSecret()
  ), "secret() with two arguments should fail at compile time"

echo "All secret error tests passed."
