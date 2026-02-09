import ../src/unanim/secret

block testBasicSecret:
  let val = secret("my-api-key")
  doAssert val == "<<SECRET:my-api-key>>", "secret() should return a placeholder string"

block testDynamicStringRejected:
  var dynamicName = "my-key"
  doAssert not compiles(secret(dynamicName)),
    "secret() with a dynamic string should fail to compile"

import std/macros

block testCollectSecretsBasic:
  static:
    let ast = newCall(ident("secret"), newStrLitNode("openai-key"))
    var secrets: seq[string] = @[]
    collectSecrets(ast, secrets)
    doAssert secrets == @["openai-key"],
      "collectSecrets should find 'openai-key' but got: " & $secrets

block testCollectMultipleSecrets:
  static:
    let ast = newStmtList(
      newCall(ident("secret"), newStrLitNode("openai-key")),
      newCall(ident("secret"), newStrLitNode("fal-key")),
      newCall(ident("secret"), newStrLitNode("jwt-signing-key"))
    )
    var secrets: seq[string] = @[]
    collectSecrets(ast, secrets)
    doAssert secrets.len == 3,
      "Should find 3 secrets but found " & $secrets.len
    doAssert secrets[0] == "openai-key"
    doAssert secrets[1] == "fal-key"
    doAssert secrets[2] == "jwt-signing-key"

block testNestedSecretInConcat:
  static:
    let ast = newNimNode(nnkInfix).add(
      ident("&"),
      newStrLitNode("Bearer "),
      newCall(ident("secret"), newStrLitNode("openai-key"))
    )
    var secrets: seq[string] = @[]
    collectSecrets(ast, secrets)
    doAssert secrets == @["openai-key"],
      "Should find secret nested in & concat but got: " & $secrets

echo "All secret tests passed."
