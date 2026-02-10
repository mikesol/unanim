## End-to-end validation: proxyFetch with event verification
## Generates Worker+DO artifacts for deployment to Cloudflare.
import ../src/unanim
import ../src/unanim/codegen

proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""

analyze:
  discard proxyFetch("https://httpbin.org/post",
    headers = {"Authorization": "Bearer " & secret("test-api-key")},
    body = "test")

const outputDir = "/home/mikesol/Documents/GitHub/unanim/unanim-15/validation/proxy_verify_artifacts"
static:
  generateArtifacts("unanim-e2e-proxy", outputDir)

echo "Proxy verification artifacts generated at: " & outputDir
