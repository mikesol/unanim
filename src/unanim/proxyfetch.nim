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

proc isCallTo(n: NimNode, name: string): bool =
  if n.kind in {nnkCall, nnkCommand} and n.len > 0:
    if n[0].kind == nnkIdent and n[0].strVal == name:
      return true
  return false

proc containsSecret*(n: NimNode): bool =
  if isCallTo(n, "secret"):
    return true
  for i in 0..<n.len:
    if containsSecret(n[i]):
      return true
  return false

proc collectSecretNames*(n: NimNode, secrets: var seq[string]) =
  if isCallTo(n, "secret"):
    if n.len > 1 and n[1].kind == nnkStrLit:
      secrets.add(n[1].strVal)
  for i in 0..<n.len:
    collectSecretNames(n[i], secrets)

proc extractProxyFetchCall(n: NimNode): NimNode =
  if isCallTo(n, "proxyFetch"):
    return n
  if n.kind in {nnkLetSection, nnkVarSection}:
    for identDef in n:
      if identDef.kind == nnkIdentDefs and identDef.len >= 3:
        let value = identDef[^1]
        if isCallTo(value, "proxyFetch"):
          return value
  if n.kind == nnkDiscardStmt and n.len > 0 and isCallTo(n[0], "proxyFetch"):
    return n[0]
  if n.kind == nnkAsgn and n.len >= 2 and isCallTo(n[1], "proxyFetch"):
    return n[1]
  return nil

proc classifyProxyFetch(pfNode: NimNode): (ProxyFetchClassification, seq[string]) =
  var secrets: seq[string] = @[]
  collectSecretNames(pfNode, secrets)
  let classification = if secrets.len > 0: ProxyRequired else: DirectFetch
  return (classification, secrets)

macro analyze*(body: untyped): untyped =
  proc walkBlock(stmts: NimNode) =
    var consecutiveCount = 0
    var groupStartLine = 0
    var groupHasSecrets = false

    proc flushGroup() =
      if consecutiveCount >= 2:
        var groupNode = newNimNode(nnkTupleConstr)
        groupNode.add(newLit(consecutiveCount))
        groupNode.add(newLit(groupStartLine))
        groupNode.add(newLit(groupHasSecrets))
        pfDelegationGroups.add(groupNode)
      consecutiveCount = 0
      groupHasSecrets = false

    for i in 0..<stmts.len:
      let pfNode = extractProxyFetchCall(stmts[i])
      if pfNode != nil:
        let (classification, secrets) = classifyProxyFetch(pfNode)
        var metaNode = newNimNode(nnkTupleConstr)
        metaNode.add(newLit(ord(classification)))
        var secretsList = newNimNode(nnkBracket)
        for s in secrets:
          secretsList.add(newLit(s))
        metaNode.add(secretsList)
        metaNode.add(newLit(pfNode.lineInfoObj.line))
        metaNode.add(newLit(pfNode.lineInfoObj.column))
        pfClassifications.add(metaNode)
        pfCallCount.inc()
        if consecutiveCount == 0:
          groupStartLine = pfNode.lineInfoObj.line
        consecutiveCount += 1
        if classification == ProxyRequired:
          groupHasSecrets = true
      else:
        flushGroup()
    flushGroup()

  if body.kind == nnkStmtList:
    walkBlock(body)
  else:
    let pfNode = extractProxyFetchCall(body)
    if pfNode != nil:
      let (classification, secrets) = classifyProxyFetch(pfNode)
      var metaNode = newNimNode(nnkTupleConstr)
      metaNode.add(newLit(ord(classification)))
      var secretsList = newNimNode(nnkBracket)
      for s in secrets:
        secretsList.add(newLit(s))
      metaNode.add(secretsList)
      metaNode.add(newLit(pfNode.lineInfoObj.line))
      metaNode.add(newLit(pfNode.lineInfoObj.column))
      pfClassifications.add(metaNode)
      pfCallCount.inc()
  result = body

macro getProxyFetchMetadata*(): untyped =
  var stmts = newStmtList()
  let seqIdent = genSym(nskVar, "pfMetaSeq")
  stmts.add(
    newNimNode(nnkVarSection).add(
      newIdentDefs(seqIdent,
        newNimNode(nnkBracketExpr).add(ident("seq"), ident("ProxyFetchMeta")),
        newNimNode(nnkPrefix).add(ident("@"), newNimNode(nnkBracket))
      )
    )
  )
  for item in pfClassifications:
    let classOrd = item[0]
    let secretsArr = item[1]
    let lineVal = item[2]
    let colVal = item[3]
    var secretsSeq = newNimNode(nnkPrefix)
    secretsSeq.add(ident("@"))
    var secretsBracket = newNimNode(nnkBracket)
    for j in 0..<secretsArr.len:
      secretsBracket.add(secretsArr[j])
    secretsSeq.add(secretsBracket)
    let objConstr = newNimNode(nnkObjConstr).add(
      ident("ProxyFetchMeta"),
      newNimNode(nnkExprColonExpr).add(ident("classification"),
        newCall(ident("ProxyFetchClassification"), classOrd)),
      newNimNode(nnkExprColonExpr).add(ident("secrets"), secretsSeq),
      newNimNode(nnkExprColonExpr).add(ident("line"), lineVal),
      newNimNode(nnkExprColonExpr).add(ident("col"), colVal)
    )
    stmts.add(newCall(newDotExpr(seqIdent, ident("add")), objConstr))
  stmts.add(seqIdent)
  result = stmts

macro getDelegationGroups*(): untyped =
  var stmts = newStmtList()
  let seqIdent = genSym(nskVar, "dgSeq")
  stmts.add(
    newNimNode(nnkVarSection).add(
      newIdentDefs(seqIdent,
        newNimNode(nnkBracketExpr).add(ident("seq"), ident("DelegationGroup")),
        newNimNode(nnkPrefix).add(ident("@"), newNimNode(nnkBracket))
      )
    )
  )
  for item in pfDelegationGroups:
    let countVal = item[0]
    let startLineVal = item[1]
    let hasSecretsVal = item[2]
    let objConstr = newNimNode(nnkObjConstr).add(
      ident("DelegationGroup"),
      newNimNode(nnkExprColonExpr).add(ident("callCount"), countVal),
      newNimNode(nnkExprColonExpr).add(ident("startLine"), startLineVal),
      newNimNode(nnkExprColonExpr).add(ident("hasSecrets"), hasSecretsVal)
    )
    stmts.add(newCall(newDotExpr(seqIdent, ident("add")), objConstr))
  stmts.add(seqIdent)
  result = stmts
