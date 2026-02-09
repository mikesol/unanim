## End-to-end validation: Durable Object with SQLite storage
## Generates Worker + DO artifacts, deploy with wrangler, test via curl.

import ../src/unanim
import ../src/unanim/codegen

# Register a secret and proxyFetch call to exercise codegen
proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""

analyze:
  discard proxyFetch("https://httpbin.org/post",
    headers = {"Authorization": "Bearer " & secret("test-api-key")},
    body = "test")

const outputDir = "/home/mikesol/Documents/GitHub/unanim/unanim-14/validation/do_artifacts"
static:
  generateArtifacts("unanim-e2e-do", outputDir)

echo "DO artifacts generated at: " & outputDir
