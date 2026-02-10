## unanim/guard - Compile-time guard declaration and metadata.
##
## The `guard()` primitive marks state domains where only the proxy/DO
## can mint events that increase the value. The compiler ensures that
## proxy_minted events can only originate from server code paths.
##
## See VISION.md Section 3: guard(stateName: string)

import std/macros
import std/macrocache

const guardRegistry* = CacheSeq"unanimGuardedStates"

macro guard*(stateName: static[string]): untyped =
  ## Registers a state domain as guarded at compile time.
  ## The DO will enforce that only proxy-minted events can increase this state.
  guardRegistry.add(newLit(stateName))
  result = newStmtList()  # guard() is a declaration, produces no runtime code

macro getGuardedStates*(): seq[string] =
  ## Returns the list of guarded state names at runtime.
  var bracket = newNimNode(nnkBracket)
  for item in guardRegistry:
    bracket.add(item)
  result = newCall(ident("@"), bracket)
