## unanim/eventlog - Event log data model with sequence-based continuity.
##
## Defines the Event type, append-only log construction, sequence continuity
## verification, and JSON serialization.
##
## See VISION.md Section 4.2 (The Event Log).

import std/json
import std/times

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
    "payload": e.payload
  }

proc eventFromJson*(j: JsonNode): Event =
  ## Deserialize a JsonNode into an Event.
  result = Event(
    sequence: j["sequence"].getInt().uint64,
    timestamp: j["timestamp"].getStr(),
    eventType: parseEventType(j["event_type"].getStr()),
    schemaVersion: j["schema_version"].getInt().uint32,
    payload: j["payload"].getStr()
  )

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
  ## Append event with automatic sequence and timestamp.
  let nextSeq = if log.events.len == 0: 1.uint64
                else: log.events[^1].sequence + 1

  let event = Event(
    sequence: nextSeq,
    timestamp: $now().utc,
    eventType: eventType,
    schemaVersion: schemaVersion,
    payload: payload
  )
  log.events.add(event)

type
  VerifyResult* = object
    valid*: bool
    failedAt*: int       ## 0-based index where verification failed. -1 if valid.
    error*: string

proc verifyChain*(events: seq[Event]): VerifyResult =
  ## Verify sequence continuity of an event list.
  ## Checks: sequences are monotonically increasing with no gaps,
  ## starting from 1 (or from whatever the first event's sequence is).
  if events.len == 0:
    return VerifyResult(valid: true, failedAt: -1, error: "")

  # Check each subsequent event has sequence = previous + 1
  for i in 1..<events.len:
    if events[i].sequence != events[i - 1].sequence + 1:
      return VerifyResult(valid: false, failedAt: i,
        error: "Event " & $i & " sequence gap: expected " &
               $(events[i - 1].sequence + 1) & ", got " & $events[i].sequence)

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
  ## Verify that a delta connects to an anchor event.
  ## The first delta event's sequence must equal anchor.sequence + 1.
  if delta.len == 0:
    return VerifyResult(valid: true, failedAt: -1, error: "")

  # Check connection to anchor
  if delta[0].sequence != anchor.sequence + 1:
    return VerifyResult(valid: false, failedAt: 0,
      error: "Delta does not connect to anchor: expected sequence " &
             $(anchor.sequence + 1) & ", got " & $delta[0].sequence)

  # Verify internal sequence continuity of remaining delta events
  for i in 1..<delta.len:
    if delta[i].sequence != delta[i - 1].sequence + 1:
      return VerifyResult(valid: false, failedAt: i,
        error: "Delta event " & $i & " sequence gap: expected " &
               $(delta[i - 1].sequence + 1) & ", got " & $delta[i].sequence)

  return VerifyResult(valid: true, failedAt: -1, error: "")
