## unanim/webhook - Compile-time webhook endpoint registration.
##
## The `webhook()` primitive registers stable incoming HTTP endpoints
## with signature verification. External services POST to these URLs,
## the DO executes the handler and stores resulting events.
##
## See VISION.md Section 3: webhook(path, handler)

import std/macros
import std/macrocache

type
  WebhookMeta* = object
    path*: string        ## URL path (e.g., "/stripe")
    handlerBody*: string ## String representation of handler for codegen

const webhookRegistry* = CacheSeq"unanimWebhooks"

macro webhook*(path: static[string], handler: untyped): untyped =
  ## Registers a webhook endpoint at compile time.
  ## The path must start with "/" and be a compile-time constant.
  ## The handler is a proc that receives the webhook payload.

  # Validate path starts with /
  if path.len == 0 or path[0] != '/':
    error("webhook() path must start with '/'. Got: " & path, handler)

  # Store metadata as a tuple in the cache
  var metaNode = newNimNode(nnkTupleConstr)
  metaNode.add(newLit(path))
  metaNode.add(newLit(handler.repr))  # Store handler repr for codegen reference
  webhookRegistry.add(metaNode)

  result = newStmtList()  # webhook() is a top-level declaration

macro getWebhookPaths*(): seq[string] =
  ## Returns the list of registered webhook paths.
  var bracket = newNimNode(nnkBracket)
  for item in webhookRegistry:
    bracket.add(item[0])
  result = newCall(ident("@"), bracket)
