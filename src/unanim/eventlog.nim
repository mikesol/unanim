## unanim/eventlog - Event log data model and hash chain.
##
## Defines the Event type, hash chain construction/verification,
## and JSON serialization for the append-only event log.
##
## See VISION.md Section 4.2 (The Event Log).

import std/json
import std/strutils
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
