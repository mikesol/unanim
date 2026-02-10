import ../src/unanim/eventlog
import std/json

var log = newEventLog()

log.append(
  eventType = UserAction,
  schemaVersion = 1,
  payload = "{\"action\":\"click\"}"
)

log.append(
  eventType = ApiResponse,
  schemaVersion = 1,
  payload = "{\"status\":200}"
)

echo "Event 1 stateHashAfter: ", log.events[0].stateHashAfter
echo "hashEvent(event 1):     ", hashEvent(log.events[0])
echo "Event 2 parentHash:     ", log.events[1].parentHash
echo "Equal? ", log.events[0].stateHashAfter == log.events[1].parentHash
echo ""
echo eventsToJson(log.events).pretty
