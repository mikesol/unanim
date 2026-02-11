## unanim/after - Compile-time after (delayed execution) support.
##
## The `after()` primitive schedules one-shot delayed execution
## using Cloudflare DO Alarms.
##
## See VISION.md Section 3: after(duration, handler)

import std/macros
import std/macrocache

const afterRegistry* = CacheSeq"unanimAfters"

type
  DurationUnit* = enum
    Seconds, Minutes, Hours, Days

macro after*(duration: untyped, handler: untyped): untyped =
  ## Registers a delayed execution handler at compile time.
  ## duration: e.g., 7.days, 30.minutes, 10.seconds
  ## handler: proc to execute after the delay
  ##
  ## At runtime, this generates a call to schedule a DO Alarm.

  # Store metadata for codegen
  var metaNode = newNimNode(nnkTupleConstr)
  metaNode.add(newLit(duration.repr))
  metaNode.add(newLit(handler.repr))
  afterRegistry.add(metaNode)
  result = newStmtList()

macro hasAfterHandlers*(): bool =
  ## Returns true if any after() handlers have been registered.
  result = newLit(afterRegistry.len > 0)
