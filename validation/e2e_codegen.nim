## validation/e2e_codegen.nim
## Compile-time codegen: generates worker.js and wrangler.toml for e2e validation.

import ../src/unanim/secret
import ../src/unanim/proxyfetch
import ../src/unanim/codegen

# Stub proxyFetch so the analyze macro can walk it
proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""

# Register the API call pattern with the analyze macro
analyze:
  discard proxyFetch("https://httpbin.org/anything",
    headers = {"Authorization": "Bearer " & secret("test-api-key")},
    body = "hello from unanim")

# Generate artifacts at compile time
const outputDir = "validation/deploy"
static:
  generateArtifacts("unanim-e2e-test", outputDir)

echo "Artifacts generated in " & outputDir
