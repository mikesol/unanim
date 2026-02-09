import ../src/unanim

block testVersion:
  doAssert unanimVersion == "0.1.0", "Version should be 0.1.0"

echo "All tests passed."
