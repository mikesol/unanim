import ../src/unanim/secret

block testBasicSecret:
  let val = secret("my-api-key")
  doAssert val == "<<SECRET:my-api-key>>", "secret() should return a placeholder string"

echo "All secret tests passed."
