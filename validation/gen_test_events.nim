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

echo "Event 1 sequence: ", log.events[0].sequence
echo "Event 2 sequence: ", log.events[1].sequence
echo ""
echo eventsToJson(log.events).pretty
