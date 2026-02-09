## unanim/eventlog - Event log data model and hash chain.
##
## Defines the Event type, hash chain construction/verification,
## and JSON serialization for the append-only event log.
##
## See VISION.md Section 4.2 (The Event Log).

import std/json
import std/strutils
import std/times
import nimcrypto/sha2
import nimcrypto/hash

type
  EventType* = enum
    UserAction = "user_action"
    ApiResponse = "api_response"
    WebhookResult = "webhook_result"
    CronResult = "cron_result"
    ProxyMinted = "proxy_minted"

  Event* = object
    sequence*: uint64
    timestamp*: string              ## ISO 8601 datetime string
    eventType*: EventType
    schemaVersion*: uint32
    payload*: string                ## JSON string
    stateHashAfter*: string         ## SHA-256 hex string
    parentHash*: string             ## SHA-256 hex string (hash of previous event)

proc parseEventType*(s: string): EventType =
  ## Parse a string into an EventType enum value.
  case s
  of "user_action": UserAction
  of "api_response": ApiResponse
  of "webhook_result": WebhookResult
  of "cron_result": CronResult
  of "proxy_minted": ProxyMinted
  else: raise newException(ValueError, "Unknown EventType: " & s)

proc toJson*(e: Event): JsonNode =
  ## Serialize an Event to a JsonNode with snake_case field names.
  result = %*{
    "sequence": e.sequence.int,
    "timestamp": e.timestamp,
    "event_type": $e.eventType,
    "schema_version": e.schemaVersion.int,
    "payload": e.payload,
    "state_hash_after": e.stateHashAfter,
    "parent_hash": e.parentHash
  }

proc eventFromJson*(j: JsonNode): Event =
  ## Deserialize a JsonNode into an Event.
  result = Event(
    sequence: j["sequence"].getInt().uint64,
    timestamp: j["timestamp"].getStr(),
    eventType: parseEventType(j["event_type"].getStr()),
    schemaVersion: j["schema_version"].getInt().uint32,
    payload: j["payload"].getStr(),
    stateHashAfter: j["state_hash_after"].getStr(),
    parentHash: j["parent_hash"].getStr()
  )

proc sha256Hex*(data: string): string =
  ## Compute SHA-256 hash, return lowercase hex string.
  let digest = sha256.digest(data)
  result = ($digest).toLowerAscii()

proc canonicalForm*(e: Event): string =
  ## Deterministic string representation for hashing.
  result = $e.sequence & "|" &
           e.timestamp & "|" &
           $e.eventType & "|" &
           $e.schemaVersion & "|" &
           e.payload & "|" &
           e.stateHashAfter & "|" &
           e.parentHash

proc hashEvent*(e: Event): string =
  ## SHA-256 of an event's canonical form.
  sha256Hex(canonicalForm(e))

type
  EventLog* = object
    events*: seq[Event]

proc newEventLog*(): EventLog =
  EventLog(events: @[])

proc len*(log: EventLog): int =
  log.events.len

proc `[]`*(log: EventLog, idx: int): Event =
  log.events[idx]

proc append*(log: var EventLog, eventType: EventType, schemaVersion: uint32,
             payload: string) =
  ## Append event with automatic sequence, timestamp, parentHash, stateHashAfter.
  let nextSeq = if log.events.len == 0: 1.uint64
                else: log.events[^1].sequence + 1

  let parentHash = if log.events.len == 0: "0".repeat(64)
                   else: hashEvent(log.events[^1])

  var event = Event(
    sequence: nextSeq,
    timestamp: $now().utc,
    eventType: eventType,
    schemaVersion: schemaVersion,
    payload: payload,
    stateHashAfter: "",
    parentHash: parentHash
  )
  # stateHashAfter = hash of event with stateHashAfter=""
  event.stateHashAfter = hashEvent(event)
  log.events.add(event)

type
  VerifyResult* = object
    valid*: bool
    failedAt*: int       ## 0-based index where verification failed. -1 if valid.
    error*: string

proc verifyChain*(events: seq[Event]): VerifyResult =
  ## Verify hash chain integrity.
  ## Checks: first event parentHash is zeros, each subsequent event's parentHash
  ## matches hash of previous event, each stateHashAfter is consistent.
  if events.len == 0:
    return VerifyResult(valid: true, failedAt: -1, error: "")

  # Check first event
  if events[0].parentHash != "0".repeat(64):
    return VerifyResult(valid: false, failedAt: 0,
      error: "First event parentHash is not zeros")

  # Verify stateHashAfter for first event
  var checkEvent = events[0]
  checkEvent.stateHashAfter = ""
  if events[0].stateHashAfter != hashEvent(checkEvent):
    return VerifyResult(valid: false, failedAt: 0,
      error: "First event stateHashAfter mismatch")

  # Check chain
  for i in 1..<events.len:
    let expectedParent = hashEvent(events[i - 1])
    if events[i].parentHash != expectedParent:
      return VerifyResult(valid: false, failedAt: i,
        error: "Event " & $i & " parentHash mismatch")

    var check = events[i]
    check.stateHashAfter = ""
    if events[i].stateHashAfter != hashEvent(check):
      return VerifyResult(valid: false, failedAt: i,
        error: "Event " & $i & " stateHashAfter mismatch")

  return VerifyResult(valid: true, failedAt: -1, error: "")

proc eventsToJson*(events: seq[Event]): JsonNode =
  ## Serialize a sequence of events to a JSON array.
  result = newJArray()
  for e in events:
    result.add(e.toJson())

proc eventsFromJson*(j: JsonNode): seq[Event] =
  ## Deserialize a JSON array to a sequence of events.
  result = @[]
  for item in j:
    result.add(eventFromJson(item))

proc eventsSince*(log: EventLog, sinceSequence: uint64): seq[Event] =
  ## Return all events with sequence > sinceSequence.
  result = @[]
  for e in log.events:
    if e.sequence > sinceSequence:
      result.add(e)

proc verifyContinuity*(anchor: Event, delta: seq[Event]): VerifyResult =
  ## Verify that a delta connects to an anchor event and is internally consistent.
  ## The first delta event's parentHash must equal hashEvent(anchor).
  if delta.len == 0:
    return VerifyResult(valid: true, failedAt: -1, error: "")

  # Check connection to anchor
  let expectedParent = hashEvent(anchor)
  if delta[0].parentHash != expectedParent:
    return VerifyResult(valid: false, failedAt: 0,
      error: "Delta does not connect to anchor")

  # Verify stateHashAfter of first delta event
  var check = delta[0]
  check.stateHashAfter = ""
  if delta[0].stateHashAfter != hashEvent(check):
    return VerifyResult(valid: false, failedAt: 0,
      error: "First delta event stateHashAfter mismatch")

  # Verify internal chain of remaining delta events
  for i in 1..<delta.len:
    let expParent = hashEvent(delta[i - 1])
    if delta[i].parentHash != expParent:
      return VerifyResult(valid: false, failedAt: i,
        error: "Delta event " & $i & " parentHash mismatch")
    var chk = delta[i]
    chk.stateHashAfter = ""
    if delta[i].stateHashAfter != hashEvent(chk):
      return VerifyResult(valid: false, failedAt: i,
        error: "Delta event " & $i & " stateHashAfter mismatch")

  return VerifyResult(valid: true, failedAt: -1, error: "")
