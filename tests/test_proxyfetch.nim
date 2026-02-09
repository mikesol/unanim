import ../src/unanim/proxyfetch

block testTypesExist:
  let c: ProxyFetchClassification = ProxyRequired
  doAssert c == ProxyRequired
  let d: ProxyFetchClassification = DirectFetch
  doAssert d == DirectFetch

echo "test_proxyfetch: Task 1 passed."

# Stubs so proxyFetch/secret resolve after macro pass-through
proc proxyFetch(url: string, headers: openArray[(string, string)] = @[],
                body: string = ""): string = ""
proc secret(name: string): string = ""

# Block A: single proxyFetch WITH secret
analyze:
  discard proxyFetch("https://api.openai.com/v1/chat",
    headers = {"Authorization": "Bearer " & secret("openai-key")},
    body = "test")

block testSingleWithSecret:
  let meta = getProxyFetchMetadata()
  doAssert meta.len >= 1, "Expected at least 1 proxyFetch call, got " & $meta.len
  doAssert meta[0].classification == ProxyRequired,
    "Expected ProxyRequired, got " & $meta[0].classification
  doAssert "openai-key" in meta[0].secrets,
    "Expected 'openai-key' in secrets, got " & $meta[0].secrets

echo "test_proxyfetch: Task 2 passed."

# Block B: single proxyFetch WITHOUT secret
analyze:
  discard proxyFetch("https://api.example.com/public", body = "test")

block testSingleWithoutSecret:
  let meta = getProxyFetchMetadata()
  doAssert meta.len >= 2, "Expected at least 2, got " & $meta.len
  doAssert meta[1].classification == DirectFetch,
    "Expected DirectFetch, got " & $meta[1].classification
  doAssert meta[1].secrets.len == 0,
    "Expected 0 secrets, got " & $meta[1].secrets.len

echo "test_proxyfetch: Task 3 passed."

# Block C: deeply nested secrets in string concat and table constructor
analyze:
  discard proxyFetch("https://api.example.com",
    headers = {"X-Custom": "prefix" & secret("key1") & "-" & secret("key2"),
               "X-Other": "static-value"},
    body = "test")

block testDeepNestedSecrets:
  let meta = getProxyFetchMetadata()
  doAssert meta.len >= 3, "Expected at least 3, got " & $meta.len
  doAssert meta[2].classification == ProxyRequired
  doAssert meta[2].secrets.len == 2, "Expected 2 secrets, got " & $meta[2].secrets.len
  doAssert "key1" in meta[2].secrets
  doAssert "key2" in meta[2].secrets

echo "test_proxyfetch: Task 4 passed."

# Block D: secret in URL position
analyze:
  discard proxyFetch("https://api.example.com/" & secret("host-token"),
    headers = {"Auth": secret("full-token")},
    body = "test")

block testSecretInUrl:
  let meta = getProxyFetchMetadata()
  doAssert meta.len >= 4, "Expected at least 4, got " & $meta.len
  doAssert meta[3].classification == ProxyRequired
  doAssert meta[3].secrets.len == 2
  doAssert "host-token" in meta[3].secrets
  doAssert "full-token" in meta[3].secrets

echo "test_proxyfetch: Task 4b passed."

# Block E: 3 sequential proxyFetch calls (delegation group)
analyze:
  let data = proxyFetch("https://api1.com",
    headers = {"Auth": "Bearer " & secret("k1")})
  let analysis = proxyFetch("https://api2.com", body = data)
  let chart = proxyFetch("https://api3.com", body = analysis)

block testSequentialDelegation:
  let groups = getDelegationGroups()
  doAssert groups.len >= 1, "Expected at least 1 delegation group, got " & $groups.len
  doAssert groups[0].callCount == 3,
    "Expected 3 calls in group, got " & $groups[0].callCount
  doAssert groups[0].hasSecrets == true

echo "test_proxyfetch: Task 5 passed."

# Block F: 2 sequential proxyFetch calls (minimum delegation)
analyze:
  let r1 = proxyFetch("https://api1.com")
  let r2 = proxyFetch("https://api2.com", body = r1)

block testMinimumDelegation:
  let groups = getDelegationGroups()
  doAssert groups.len >= 2, "Expected at least 2 groups, got " & $groups.len
  doAssert groups[1].callCount == 2
  doAssert groups[1].hasSecrets == false

echo "test_proxyfetch: Task 5b passed."

# Block G: non-sequential proxyFetch (separated by other statement)
analyze:
  let g1 = proxyFetch("https://api1.com",
    headers = {"Auth": "Bearer " & secret("k1")})
  let processed = g1 & " processed"
  let g2 = proxyFetch("https://api2.com", body = processed)

block testNonSequentialNoDelegation:
  let groups = getDelegationGroups()
  doAssert groups.len == 2, "Expected exactly 2 groups (no new), got " & $groups.len

echo "test_proxyfetch: Task 6 passed."

# Block H: var-wrapped proxyFetch
analyze:
  var result1 = proxyFetch("https://api.com/var-test")

block testVarWrapped:
  let meta = getProxyFetchMetadata()
  doAssert meta[^1].classification == DirectFetch

block testTotalCallCount:
  let meta = getProxyFetchMetadata()
  # 1 + 1 + 1 + 1 + 3 + 2 + 2 + 1 = 12
  doAssert meta.len == 12, "Expected 12 total, got " & $meta.len

echo "test_proxyfetch: Task 7 passed."
echo "All proxyFetch tests passed."
