## unanim/cron - Compile-time cron schedule registration.
##
## The `cron()` primitive registers recurring scheduled handlers.
## The compiler generates Cloudflare Cron Trigger configurations.
##
## See VISION.md Section 3: cron(schedule, handler)

import std/macros
import std/macrocache

const cronRegistry* = CacheSeq"unanimCrons"

macro cron*(schedule: static[string], handler: untyped): untyped =
  ## Registers a cron schedule at compile time.
  ## schedule: cron expression (e.g., "0 */6 * * *")
  ## handler: proc to execute on each trigger
  var metaNode = newNimNode(nnkTupleConstr)
  metaNode.add(newLit(schedule))
  metaNode.add(newLit(handler.repr))
  cronRegistry.add(metaNode)
  result = newStmtList()

macro getCronSchedules*(): seq[string] =
  ## Returns the list of registered cron schedules.
  var bracket = newNimNode(nnkBracket)
  for item in cronRegistry:
    bracket.add(item[0])
  result = newCall(ident("@"), bracket)
