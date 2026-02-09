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
    payload: """{"key": "value"}""",
    stateHashAfter: "abc123",
    parentHash: "def456"
  )
  assert e.sequence == 1'u64
  assert e.timestamp == "2026-02-09T12:00:00Z"
  assert e.eventType == UserAction
  assert e.schemaVersion == 1'u32
  assert e.payload == """{"key": "value"}"""
  assert e.stateHashAfter == "abc123"
  assert e.parentHash == "def456"
  echo "test_eventlog: Task 2b passed (Event construction)."

# ---- Task 3: JSON serialization ----

# Test: toJson produces correct field names and values
block:
  let e = Event(
    sequence: 42'u64,
    timestamp: "2026-02-09T12:00:00Z",
    eventType: ApiResponse,
    schemaVersion: 2'u32,
    payload: """{"data": "test"}""",
    stateHashAfter: "aabbcc",
    parentHash: "ddeeff"
  )
  let j = e.toJson()
  assert j["sequence"].getInt() == 42
  assert j["timestamp"].getStr() == "2026-02-09T12:00:00Z"
  assert j["event_type"].getStr() == "api_response"
  assert j["schema_version"].getInt() == 2
  assert j["payload"].getStr() == """{"data": "test"}"""
  assert j["state_hash_after"].getStr() == "aabbcc"
  assert j["parent_hash"].getStr() == "ddeeff"
  echo "test_eventlog: Task 3a passed (toJson field names and values)."

# Test: eventFromJson parses correctly
block:
  let j = %*{
    "sequence": 10,
    "timestamp": "2026-01-01T00:00:00Z",
    "event_type": "webhook_result",
    "schema_version": 1,
    "payload": "{}",
    "state_hash_after": "hash1",
    "parent_hash": "hash0"
  }
  let e = eventFromJson(j)
  assert e.sequence == 10'u64
  assert e.timestamp == "2026-01-01T00:00:00Z"
  assert e.eventType == WebhookResult
  assert e.schemaVersion == 1'u32
  assert e.payload == "{}"
  assert e.stateHashAfter == "hash1"
  assert e.parentHash == "hash0"
  echo "test_eventlog: Task 3b passed (eventFromJson parsing)."

# Test: Round-trip serialize -> deserialize -> identical
block:
  let original = Event(
    sequence: 99'u64,
    timestamp: "2026-06-15T08:30:00Z",
    eventType: CronResult,
    schemaVersion: 3'u32,
    payload: """{"cron": true}""",
    stateHashAfter: "abc",
    parentHash: "xyz"
  )
  let roundTripped = eventFromJson(original.toJson())
  assert roundTripped.sequence == original.sequence
  assert roundTripped.timestamp == original.timestamp
  assert roundTripped.eventType == original.eventType
  assert roundTripped.schemaVersion == original.schemaVersion
  assert roundTripped.payload == original.payload
  assert roundTripped.stateHashAfter == original.stateHashAfter
  assert roundTripped.parentHash == original.parentHash
  echo "test_eventlog: Task 3c passed (round-trip serialization)."

# ---- Task 4: SHA-256 hashing ----

# Test: sha256Hex("test") matches known vector
block:
  let h = sha256Hex("test")
  assert h == "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
    "sha256Hex(\"test\") = " & h
  echo "test_eventlog: Task 4a passed (sha256 known vector for 'test')."

# Test: sha256Hex("") matches known vector for empty string
block:
  let h = sha256Hex("")
  assert h == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "sha256Hex(\"\") = " & h
  echo "test_eventlog: Task 4b passed (sha256 known vector for empty string)."

# Test: Deterministic - same input -> same output
block:
  let h1 = sha256Hex("deterministic test")
  let h2 = sha256Hex("deterministic test")
  assert h1 == h2, "SHA-256 should be deterministic"
  echo "test_eventlog: Task 4c passed (sha256 determinism)."

# ---- Task 5: Event hashing (canonical form) ----

# Test: hashEvent returns 64 hex chars
block:
  let e = Event(
    sequence: 1'u64,
    timestamp: "2026-02-09T12:00:00Z",
    eventType: UserAction,
    schemaVersion: 1'u32,
    payload: """{"action": "click"}""",
    stateHashAfter: "aaa",
    parentHash: "bbb"
  )
  let h = hashEvent(e)
  assert h.len == 64, "hashEvent should return 64 hex chars, got " & $h.len
  # Verify all characters are valid lowercase hex
  for c in h:
    assert c in {'0'..'9', 'a'..'f'}, "Invalid hex char: " & $c
  echo "test_eventlog: Task 5a passed (hashEvent returns 64 hex chars)."

# Test: Same event -> same hash (deterministic)
block:
  let e = Event(
    sequence: 5'u64,
    timestamp: "2026-03-01T00:00:00Z",
    eventType: ProxyMinted,
    schemaVersion: 1'u32,
    payload: "{}",
    stateHashAfter: "xxx",
    parentHash: "yyy"
  )
  let h1 = hashEvent(e)
  let h2 = hashEvent(e)
  assert h1 == h2, "hashEvent should be deterministic"
  echo "test_eventlog: Task 5b passed (hashEvent determinism)."

# Test: Different events -> different hashes
block:
  let e1 = Event(
    sequence: 1'u64,
    timestamp: "2026-02-09T12:00:00Z",
    eventType: UserAction,
    schemaVersion: 1'u32,
    payload: """{"a": 1}""",
    stateHashAfter: "hash1",
    parentHash: "parent1"
  )
  let e2 = Event(
    sequence: 2'u64,
    timestamp: "2026-02-09T12:00:01Z",
    eventType: ApiResponse,
    schemaVersion: 1'u32,
    payload: """{"b": 2}""",
    stateHashAfter: "hash2",
    parentHash: "parent2"
  )
  let h1 = hashEvent(e1)
  let h2 = hashEvent(e2)
  assert h1 != h2, "Different events should produce different hashes"
  echo "test_eventlog: Task 5c passed (different events -> different hashes)."

# Test: canonicalForm produces expected pipe-delimited format
block:
  let e = Event(
    sequence: 7'u64,
    timestamp: "2026-04-01T10:00:00Z",
    eventType: CronResult,
    schemaVersion: 2'u32,
    payload: """{"job": "daily"}""",
    stateHashAfter: "stateabc",
    parentHash: "parentdef"
  )
  let cf = canonicalForm(e)
  assert cf == "7|2026-04-01T10:00:00Z|cron_result|2|{\"job\": \"daily\"}|stateabc|parentdef",
    "Canonical form mismatch: " & cf
  echo "test_eventlog: Task 5d passed (canonicalForm format)."

echo "All eventlog tests passed."
