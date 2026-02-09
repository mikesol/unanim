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

echo "All secret tests passed."
