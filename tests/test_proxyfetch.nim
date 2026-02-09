import ../src/unanim/proxyfetch

block testTypesExist:
  let c: ProxyFetchClassification = ProxyRequired
  doAssert c == ProxyRequired
  let d: ProxyFetchClassification = DirectFetch
  doAssert d == DirectFetch

echo "test_proxyfetch: Task 1 passed."
