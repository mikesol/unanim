## Tests for unanim/eventlog module.

import ../src/unanim/eventlog
import std/json

# ---- Task 2: Type definitions ----

# Test: EventType enum has all 5 variants
block:
  let variants = [UserAction, ApiResponse, WebhookResult, CronResult, ProxyMinted]
  assert variants.len == 5, "EventType should have 5 variants"
  echo "test_eventlog: Task 2a passed (EventType has 5 variants)."

# Test: Event can be constructed with all fields
block:
  let e = Event(
    sequence: 1'u64,
    timestamp: "2026-02-09T12:00:00Z",
    eventType: UserAction,
    schemaVersion: 1'u32,
    payload: """{"key": "value"}"""
  )
  assert e.sequence == 1'u64
  assert e.timestamp == "2026-02-09T12:00:00Z"
  assert e.eventType == UserAction
  assert e.schemaVersion == 1'u32
  assert e.payload == """{"key": "value"}"""
  echo "test_eventlog: Task 2b passed (Event construction)."

# ---- Task 3: JSON serialization ----

# Test: toJson produces correct field names and values
block:
  let e = Event(
    sequence: 42'u64,
    timestamp: "2026-02-09T12:00:00Z",
    eventType: ApiResponse,
    schemaVersion: 2'u32,
    payload: """{"data": "test"}"""
  )
  let j = e.toJson()
  assert j["sequence"].getInt() == 42
  assert j["timestamp"].getStr() == "2026-02-09T12:00:00Z"
  assert j["event_type"].getStr() == "api_response"
  assert j["schema_version"].getInt() == 2
  assert j["payload"].getStr() == """{"data": "test"}"""
  echo "test_eventlog: Task 3a passed (toJson field names and values)."

# Test: eventFromJson parses correctly
block:
  let j = %*{
    "sequence": 10,
    "timestamp": "2026-01-01T00:00:00Z",
    "event_type": "webhook_result",
    "schema_version": 1,
    "payload": "{}"
  }
  let e = eventFromJson(j)
  assert e.sequence == 10'u64
  assert e.timestamp == "2026-01-01T00:00:00Z"
  assert e.eventType == WebhookResult
  assert e.schemaVersion == 1'u32
  assert e.payload == "{}"
  echo "test_eventlog: Task 3b passed (eventFromJson parsing)."

# Test: Round-trip serialize -> deserialize -> identical
block:
  let original = Event(
    sequence: 99'u64,
    timestamp: "2026-06-15T08:30:00Z",
    eventType: CronResult,
    schemaVersion: 3'u32,
    payload: """{"cron": true}"""
  )
  let roundTripped = eventFromJson(original.toJson())
  assert roundTripped.sequence == original.sequence
  assert roundTripped.timestamp == original.timestamp
  assert roundTripped.eventType == original.eventType
  assert roundTripped.schemaVersion == original.schemaVersion
  assert roundTripped.payload == original.payload
  echo "test_eventlog: Task 3c passed (round-trip serialization)."

# --- Task 6: Event log construction ---
block testEventLogAppend:
  var log = newEventLog()
  doAssert log.len == 0
  log.append(EventType.UserAction, 1, """{"action":"create"}""")
  doAssert log.len == 1
  doAssert log[0].sequence == 1

echo "test_eventlog: Task 6a passed."

block testEventLogChain:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"action":"create"}""")
  log.append(EventType.ApiResponse, 1, """{"status":200}""")
  log.append(EventType.UserAction, 1, """{"action":"update"}""")
  doAssert log.len == 3
  doAssert log[0].sequence == 1
  doAssert log[1].sequence == 2
  doAssert log[2].sequence == 3

echo "test_eventlog: Task 6b passed."

# --- Task 7: Sequence continuity verification ---
block testVerifyValidChain:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  log.append(EventType.ApiResponse, 1, """{"b":2}""")
  log.append(EventType.UserAction, 1, """{"c":3}""")
  let result = verifyChain(log.events)
  doAssert result.valid, "Valid chain should verify: " & result.error

echo "test_eventlog: Task 7a passed."

block testVerifySequenceGap:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  log.append(EventType.ApiResponse, 1, """{"b":2}""")
  log.append(EventType.UserAction, 1, """{"c":3}""")
  log.events[1].sequence = 5  # Create gap: 1, 5, 3
  let result = verifyChain(log.events)
  doAssert not result.valid, "Sequence gap should fail"
  doAssert result.failedAt == 1, "Should identify event 1 as broken"

echo "test_eventlog: Task 7b passed."

block testVerifyTamperedSequence:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  log.append(EventType.UserAction, 1, """{"b":2}""")
  log.events[0].sequence = 99
  let result = verifyChain(log.events)
  doAssert not result.valid, "Tampered sequence should fail"

echo "test_eventlog: Task 7c passed."

block testVerifyEmptyChain:
  let result = verifyChain(@[])
  doAssert result.valid, "Empty chain should be valid"

echo "test_eventlog: Task 7d passed."

block testVerifySingleEvent:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  let result = verifyChain(log.events)
  doAssert result.valid, "Single event chain should be valid"

echo "test_eventlog: Task 7e passed."

# --- Task 8: Events array serialization ---
block testEventsToJson:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  log.append(EventType.ApiResponse, 1, """{"b":2}""")
  let j = eventsToJson(log.events)
  doAssert j.kind == JArray
  doAssert j.len == 2
  doAssert j[0]["sequence"].getInt() == 1
  doAssert j[1]["sequence"].getInt() == 2

echo "test_eventlog: Task 8a passed."

block testEventsFromJson:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  log.append(EventType.ApiResponse, 1, """{"b":2}""")
  let j = eventsToJson(log.events)
  let restored = eventsFromJson(j)
  doAssert restored.len == 2
  doAssert restored[0].sequence == log[0].sequence
  doAssert restored[1].eventType == log[1].eventType
  let result = verifyChain(restored)
  doAssert result.valid, "Chain should still verify after JSON round-trip: " & result.error

echo "test_eventlog: Task 8b passed."

# --- Task 9: Delta extraction ---
block testEventsSince:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  log.append(EventType.ApiResponse, 1, """{"b":2}""")
  log.append(EventType.UserAction, 1, """{"c":3}""")
  log.append(EventType.ProxyMinted, 1, """{"d":4}""")
  let delta = log.eventsSince(2)
  doAssert delta.len == 2, "Should return events after sequence 2, got " & $delta.len
  doAssert delta[0].sequence == 3
  doAssert delta[1].sequence == 4

echo "test_eventlog: Task 9a passed."

block testEventsSinceZero:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  log.append(EventType.UserAction, 1, """{"b":2}""")
  let delta = log.eventsSince(0)
  doAssert delta.len == 2, "eventsSince(0) should return all events"

echo "test_eventlog: Task 9b passed."

block testEventsSinceAll:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  let delta = log.eventsSince(1)
  doAssert delta.len == 0, "eventsSince(lastSeq) should return empty"

echo "test_eventlog: Task 9c passed."

# --- Task 10: Chain continuity ---
block testVerifyContinuity:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  log.append(EventType.UserAction, 1, """{"b":2}""")
  let delta = log.eventsSince(1)
  doAssert delta.len == 1
  let result = verifyContinuity(log[0], delta)
  doAssert result.valid, "Delta should connect to anchor: " & result.error

echo "test_eventlog: Task 10a passed."

block testVerifyContinuityBroken:
  var log1 = newEventLog()
  log1.append(EventType.UserAction, 1, """{"a":1}""")
  # Create a delta that doesn't connect — sequence 1 can't follow anchor sequence 1
  var log2 = newEventLog()
  log2.append(EventType.UserAction, 1, """{"x":99}""")
  let result = verifyContinuity(log1[0], log2.events)
  doAssert not result.valid, "Delta from different chain should fail continuity"

echo "test_eventlog: Task 10b passed."

block testVerifyContinuityEmpty:
  var log = newEventLog()
  log.append(EventType.UserAction, 1, """{"a":1}""")
  let result = verifyContinuity(log[0], @[])
  doAssert result.valid, "Empty delta should be valid"

echo "test_eventlog: Task 10c passed."

echo "All eventlog tests passed."
