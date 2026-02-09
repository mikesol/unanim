## unanim/proxyfetch - Compile-time proxyFetch detection and classification.
##
## Walks an untyped AST to find proxyFetch(...) calls, detects secret()
## markers in their arguments, and classifies each call as proxy-required
## (contains secrets) or direct-fetch (no secrets, can be optimized away).
## Also detects sequential proxyFetch calls (2+) for server-side delegation.

import std/macros
import std/macrocache

type
  ProxyFetchClassification* = enum
    ProxyRequired   ## Contains secret() markers -- must route through proxy
    DirectFetch     ## No secrets -- can be optimized to direct client fetch

  ProxyFetchMeta* = object
    classification*: ProxyFetchClassification
    secrets*: seq[string]       ## Names of secrets found in this call
    line*: int                  ## Source line number
    col*: int                   ## Source column number

  DelegationGroup* = object
    callCount*: int             ## Number of sequential proxyFetch calls
    startLine*: int             ## Line of first call in group
    hasSecrets*: bool           ## Whether any call in group contains secrets

# Compile-time metadata storage
const pfClassifications* = CacheSeq"unanimProxyFetchClassifications"
const pfDelegationGroups* = CacheSeq"unanimDelegationGroups"
const pfCallCount* = CacheCounter"unanimProxyFetchCount"
