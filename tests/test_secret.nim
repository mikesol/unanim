import ../src/unanim/secret

block testBasicSecret:
  let val = secret("my-api-key")
  doAssert val == "<<SECRET:my-api-key>>", "secret() should return a placeholder string"

block testDynamicStringRejected:
  var dynamicName = "my-key"
  doAssert not compiles(secret(dynamicName)),
    "secret() with a dynamic string should fail to compile"

echo "All secret tests passed."
