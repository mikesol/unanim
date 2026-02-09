# Unanim — Vision 0.1.0

*A Nim-based compile-time framework that eliminates the backend by generating client applications, server-side proxy configurations, and state sync protocols from a single source.*

*Latin unanimus: "of one mind." One source of truth. The compiler decides the rest.*

> **Changelog from 0.0.0:**
> - Resolved all Hard Problems from Section 4 with specific architectural decisions
> - Added compile-time delegation (Nim metaprogramming determines client vs. server execution)
> - Added guarded state model (Ethereum-light verification at proxy)
> - Chose IndexedDB (client) + Cloudflare Durable Objects with SQLite (server)
> - Eliminated CRDTs -- distributed single-player with lease-based handoff
> - Resolved auth strategy (Oslo + Arctic, compiler-generated)
> - Added hybrid sync strategy (proxyFetch + heartbeat + sendBeacon)
> - Added WebSocket channel to DO (lease detection + immediate event push)
> - Added migration/ejection architecture (framework as compiler, not runtime)
> - Added `shared()` primitive for multi-user organizations (org-level DO as sequencer, no CRDTs)
> - Added OrgShoots worked example and stress test suite for shared state
> - Added wire protocol sketch (Section 4.11)
> - Added complete app example (Appendix D) and PoC code excerpts (Appendix C)
> - Marked three implementation-time design decisions: operation classification, rollback mechanism, IndexedDB abstraction
> - Added project ethos (OSS quality bar, developer empathy, honest constraints)
> - Added build philosophy (validate against real Cloudflare + browser, phased build order)
> - Named the framework: **Unanim** (Latin *unanimus*, "of one mind")

---

## 1. The World This Creates

Today, building a web application means building two things: a frontend that the user sees, and a backend that the frontend talks to. The backend exists for three reasons: holding secrets (API keys), providing a stable address (webhook endpoints, cron), and persisting state (database). For many applications -- especially AI-powered tools, personal productivity apps, and LLM-generated apps -- 90% of the backend is boilerplate plumbing between the frontend and a handful of external APIs.

This project eliminates the backend as a thing you write. You write client code. All of it. Business logic, state management, UI, workflows -- everything is authored as if it runs in the browser. The compiler then examines your code and extracts the parts that *physically cannot* run on the client: secret references, stable-address handlers, and state sync logic. It generates the minimal server-side infrastructure to support those parts. You don't write server code. You don't deploy a backend. You don't think about the client/server boundary. The compiler thinks about it for you.

**Speed is a first-class goal.** When everything runs on the client, reads are local and instantaneous -- no round-trip to a database server. Assets (generic and user-scoped) live close to the user via edge infrastructure. The system is edge-aware: it understands that data has geography, and it keeps state and assets near the client that owns them.

**The primary author is an LLM.** The system is designed from the ground up so that a language model can generate a complete, working application from a natural language description. The DSL, the compiler errors, the documentation -- all optimized for LLM comprehension, not human ergonomics. A human can read and inspect everything, but the authoring workflow assumes the writer is a machine.

The result is a single-file (or small-set-of-files) Nim program that compiles to: a client application (HTML + JS), a server-side proxy configuration, webhook/cron handlers that can run on either side, and a state sync protocol. One source of truth, multiple deployment artifacts.

---

## 2. Core Principles

**1. Client-default, server-necessary.** Code runs on the client unless it physically can't. There are exactly two reasons code must run on the server: it needs a secret the client can't hold, or it needs to be reachable when the client is offline. Everything else -- including business logic, validation, and state management -- runs in the browser.

**2. The compiler is the architect.** The Nim macro system examines the developer's (LLM's) code at compile time and determines what goes where. It identifies secret references, extracts webhook/cron handlers, checks whether handlers are portable (can execute server-side), analyzes API call patterns to determine delegation boundaries, and generates both client and server artifacts from a single source. The client/server boundary is a compiler output, not a developer input.

**3. Boring primitives.** The developer-facing API is deliberately unclever. `proxyFetch` is fetch. `webhook` returns a URL. `secret("key-name")` is a string placeholder. `cron(schedule, handler)` is a timer. `guard("credits")` marks state as proxy-observable. There are no state machines, no reactive frameworks, no special syntax beyond what's needed to mark the things the server handles. An LLM trained on standard HTTP and JavaScript patterns can generate correct code with minimal framework-specific knowledge.

**4. LLM-first authorship.** The system is designed for machine generation, not human typing. This affects every decision: compiler errors are structured, actionable, and reference specific documentation sections. Nim macros detect common LLM mistakes (passing unserialized closures across boundaries, using non-deterministic operations in portable code, calling `proxyFetch` without `secret()`) and produce errors that help the LLM self-correct. The guardrails are diagnostic -- they tell you *why* something failed and *how* to fix it, with enough context for an LLM to auto-correct on the next attempt.

**5. Portability is a liveness property.** When the compiler checks whether code is "portable" (compiles to both JS and a server-side target), it's not enforcing correctness -- it's determining an operational fact about your code. Portable code *will run* regardless of whether the client is online: if the client is available, it runs there; if the client goes to sleep, the server takes over seamlessly. Non-portable code (anything that touches the DOM or browser APIs) can only run when the client is present. The compiler tells you which category each handler falls into, and the runtime handles the handoff transparently.

**6. The proxy is powerful but domain-ignorant.** The server-side component manages credential injection, webhook routing, event log verification, state sync, portable handler execution, and auth. This is substantial machinery. But the proxy achieves all of this without domain knowledge. It doesn't know your data model, your business logic, or your schema. It processes event logs, verifies hash chains, swaps secrets, stores bytes, mints guarded-state events, and runs portable code. The complexity lives in the *protocol*, not in application-specific logic. If the proxy ever needs to understand *what* your application does (beyond the mechanical categories defined by the primitives), the architecture has failed.

**7. The framework is a compiler, not a runtime.** Generated artifacts run without the framework. Client JS runs in any browser without a Nim runtime. Server handlers run as standard Cloudflare Workers. SQL migrations run on any SQLite/Postgres instance. Cron configs work with any cron system. The framework is a development accelerator, not an operational dependency. Users can extract individual pieces (a cron job, an API handler, a database schema) and run them standalone.

### Project Ethos

This is not an app. This is not a research project. This is an open-source framework for people building real things on Cloudflare. It should feel like it.

**OSS quality bar.** The README should make someone want to try it in the first 30 seconds. The getting-started experience should go from `npm create unanim` to a deployed app in under 5 minutes. Error messages should be so good that people screenshot them. The docs should be the kind you actually read, not the kind you endure. If it's not at the level where a Cloudflare developer would recommend it to a colleague, it's not done.

**Developer empathy over technical cleverness.** The internal architecture can be as clever as it needs to be — compile-time AST rewriting, dual-target compilation, lease protocols. But the developer-facing surface should be boring, obvious, and unsurprising. If a developer has to understand the sync protocol to use the framework, the framework has failed. If an LLM needs special training to generate correct code, the primitives are too exotic.

**Honest constraints.** Don't hide limitations. Don't paper over tradeoffs with abstractions. If offline multiplayer doesn't work, say so clearly in the docs, explain why, and explain what does work. Developers trust frameworks that tell them what they can't do. They abandon frameworks that let them discover it in production.

**Ship small, ship often.** The first release should do one thing well (maybe just `proxyFetch` + `secret()` + deploy to Cloudflare). Each subsequent release adds a primitive. No big bang. The framework earns trust incrementally, not by promising everything on day one.

---

## 3. The Primitives

The system provides a small set of compile-time primitives. These are markers that the compiler uses to determine what crosses the client/server boundary.

### `secret(name: string)`

A compile-time marker indicating that a value must be injected by the proxy at request time. The `name` argument must be a compile-time constant (the macro rejects dynamic strings). The compiler verifies at compile time that `name` matches a declared entitlement in the project configuration. At deploy time, the system verifies that every referenced secret actually exists in the secret store -- deployment fails if any secret is missing. At runtime, the proxy replaces the marker with the actual credential. The client never sees the secret.

```nim
let response = proxyFetch("https://api.openai.com/v1/chat/completions",
  headers = {"Authorization": "Bearer " & secret("openai-key")},
  body = requestBody
)
```

### `proxyFetch(url, headers, body)`

A fetch call that routes through the proxy. If the request contains `secret()` markers, the proxy performs credential injection. If it doesn't contain any secrets, the compiler optimizes it to a direct client-side fetch.

`proxyFetch` is the *primary* sync boundary. Every `proxyFetch` call carries the event log delta since the last successful sync. The proxy uses this log to: verify the hash chain is intact and events are unmodified, update the server-side state mirror, meter API usage, mint guarded-state events (e.g., credit deductions), and deliver any server-side results (webhook payloads, cron outputs) back to the client.

**Secondary sync channels:** Because proxyFetch-only sync leaves purely-local sessions vulnerable (especially Safari's 7-day eviction), a lightweight hybrid sync strategy supplements the primary path:

1. **Heartbeat** -- if state is dirty and no sync has occurred in N seconds, flush to server
2. **Page lifecycle** -- `visibilitychange` + `navigator.sendBeacon` syncs on tab close/switch
3. **Service worker** -- intercepts any fetch, opportunistically flushes pending state
4. **Background Sync** -- retries failed syncs when connectivity returns (Chrome)
5. **`navigator.storage.persist()`** -- requested on first load to protect against eviction

The primary path (proxyFetch) does full verification. The secondary channels do state persistence only (no verification, just storage). This maintains the principle that verification happens at cost-inducing boundaries while ensuring state durability.

### `webhook(handler)`

Mints a stable URL backed by a handler function. When an external service calls this URL, the handler executes. If the client is online, it executes on the client. If the client is offline, the proxy queues the payload; if the handler is portable (compiles to the server target), the proxy can execute it immediately and generate events in the log.

Webhooks support GET requests and redirect responses (extending the base to cover OAuth callbacks). The compiler determines portability and annotates each webhook accordingly.

```nim
let wh = webhook(proc(data: JsonNode) =
  let imageUrl = data["image_url"].getStr()
  addToGallery(imageUrl)
)
let response = proxyFetch(FAL_URL,
  headers = {"Authorization": "Bearer " & secret("fal-key")},
  body = %*{"prompt": prompt, "webhook_url": wh.url}
)
```

Webhooks and crons are top-level declarations in the Nim source. The compiler processes the entire program holistically and extracts them into proxy routes. There is no separate manifest file -- the source code is the manifest.

### `cron(schedule, handler)`

A scheduled handler. Same portability rules as `webhook`: if the handler compiles to the server target, it runs on schedule regardless of client state. If not, it queues until the client is available.

The compiler generates Cloudflare Cron Trigger configurations and standalone crontab entries (for extraction/portability).

```nim
cron("0 */6 * * *", proc() =
  # Runs every 6 hours -- refreshes data from an external API
  let data = proxyFetch(DATA_API_URL,
    headers = {"Authorization": "Bearer " & secret("data-key")}
  )
  updateLocalState(data)
)
```

### `guard(stateName: string)`

Declares a piece of state as *guarded* -- meaning it has constraints that the proxy must enforce. Guarded state can be decreased by client events (spending credits) but can only be increased by proxy-generated events (minting credits after a successful API call, receiving a payment webhook).

This is the Ethereum-light verification model: the proxy doesn't understand your business logic, but it knows that certain state transitions can only be authorized by specific event types. The compiler analyzes which operations touch guarded state and ensures they're bundled with proxy calls.

```nim
guard("credits")  # Only proxy-generated events can increase credits

proc handleUserAction() =
  if state.credits > 0:
    let result = proxyFetch(AI_API,
      headers = {"Authorization": "Bearer " & secret("ai-key")},
      body = requestBody
    )
    # The proxy automatically:
    # 1. Verifies the event log
    # 2. Forwards the API call
    # 3. Mints a "credits_deducted" event (only the proxy can do this)
    # 4. Returns the result + server events
    processResult(result)
```

### `shared(stateName: string)`

Declares a piece of state as *shared* -- meaning multiple users in an organization can read and write it. Shared state lives in an org-level Durable Object (one DO per org, not per user). Multiple clients connect to the same org DO via WebSocket. The DO is single-threaded, providing natural total ordering of all events without distributed consensus.

`shared()` is the multi-user counterpart to `guard()`. Where `guard()` says "only the proxy can increase this," `shared()` says "multiple users write to this, and the org DO sequences their events." The compiler analyzes operations on shared state and infers which ones need special handling (see Section 4.10).

```nim
shared("shoots")
guard("credits")

proc createShoot(name: string) =
  db.insert(Shoot(id: newId(), name: name, status: Active))

proc deleteShoot(id: string) =
  db.update("shoots", id, status = Deleted)

proc addPhoto(shootId: string, url: string) =
  db.insert(Photo(shootId: shootId, url: url))

proc editPhoto(shootId: string, photoId: string, prompt: string) =
  let result = proxyFetch(AI_API,
    headers = {"Authorization": "Bearer " & secret("ai-key")},
    body = %*{"image": photos[photoId].url, "prompt": prompt}
  )
  db.update("photos", photoId, editedUrl = result["url"].getStr)
```

The developer writes no coordination code. The compiler determines:
- `createShoot`, `addPhoto`: optimistic (apply locally, confirm later)
- `deleteShoot`: barrier (eagerly pushed, DO broadcasts immediately)
- `editPhoto`: already goes through DO via proxyFetch (DO verifies context before forwarding)

See Section 4.10 for the full model and worked examples.

### `auth(providers, credentials)`

A declarative auth primitive. The compiler generates proxy routes (signup, signin, OAuth initiate, OAuth callback, token refresh), D1 tables (user, account), client-side auth management (JWT storage, refresh timer, header injection), and JWT validation middleware.

Auth is infrastructure, not application logic. The developer never writes auth code. The proxy issues and validates JWTs -- a contained exception to domain-ignorance, same as how a web server understands TLS without understanding your API.

```nim
auth(
  providers = ["google", "github"],
  credentials = true,
  jwtSecret = secret("jwt-signing-key")
)
```

**Implementation:** Oslo (cryptographic primitives) + Arctic (OAuth 2.0 clients), both edge-compatible pure-function libraries. Total generated proxy code: ~200-300 lines. JWT with 1-hour expiry, client-side refresh. Auth data stored in D1 (shared across users, not per-user DOs).

**Secondary option:** For rapid prototyping, support Clerk as a zero-config hosted alternative (~15 lines of proxy code, no auth tables).

### `safe { ... }` blocks

Pure computation blocks that compile to both JS (client) and C (server). The compiler proves that code inside a `safe` block is deterministic by attempting compilation to both targets -- any reference to browser APIs, non-deterministic operations, or side effects causes a compile-time error.

Safe blocks are the foundation of the verification model: they guarantee that client and server produce identical results for pure computations. This is strictly superior to game netcode's approach of hoping the same binary produces the same results -- here, determinism is enforced by the language.

### Portability check

Not a primitive the developer invokes, but a compiler pass that runs on every `webhook` and `cron` handler. The compiler attempts to compile the handler body to the server target. If it succeeds, the handler is marked portable and will run on the server during client offline. If it fails, the handler is marked client-only with different liveness characteristics. The result is reported as a compiler hint.

---

## 4. The Sync Protocol

### 4.1 Architecture

The sync protocol is custom-built (not LiveStore, Zero, PowerSync, or any existing engine). No existing sync engine provides the specific combination our architecture requires: event-level sync piggybacked on API calls, lease-based single-writer with server event generation, and compile-time verified determinism.

**Client:** IndexedDB stores the event log and materialized state. Zero bundle overhead, instant availability. The framework abstracts IndexedDB entirely -- developers write SQL-like queries, and the compiler validates them against migrations at compile time, rejecting illegal operations before runtime. The metaprogramming layer treats IndexedDB as if it were a SQL database (similar in spirit to [absurd-sql](https://github.com/jlongster/absurd-sql)). No WASM SQLite on the client -- the 1.5MB bundle + 500ms init is too steep for first page load, and anything we need from SQL semantics we can enforce at compile time.

**Implementation-time design required:** The mechanism for the IndexedDB-as-SQL abstraction needs to be worked out during the build. The compile-time side is clear: Nim macros parse SQL strings from `db.query()` and `migration()` calls, validate column names / types / table references against the declared schema, and reject invalid queries. The runtime side has multiple viable approaches: (a) compile SQL to IndexedDB operations (object store reads with index lookups, translating WHERE clauses to IDBKeyRange); (b) a lightweight in-memory query engine that loads from IndexedDB and evaluates SQL; (c) use absurd-sql or a similarly thin SQLite-over-IndexedDB layer if the bundle cost is acceptable as a lazy-loaded chunk rather than a blocking initial load. The choice depends on query complexity needed — if apps mostly do key lookups and simple filters, (a) suffices; if they need JOINs and aggregations, (b) or (c) may be necessary.

**Server:** One Cloudflare Durable Object per user, with SQLite storage (GA, 10GB per object, ACID, single-threaded). The DO holds: event log mirror, materialized state, secrets (encrypted), webhook routing, lease state. D1 handles shared metadata (user lookup, webhook routing tables, auth).

**Why DOs, not D1, for per-user state:** DOs provide single-instance guarantee (natural lease model), serialized access (no concurrent write conflicts), co-located compute + storage (zero-latency queries), and Alarms (scheduled callbacks for offline processing). D1 has a single writer per database -- for per-user isolation, DOs are better.

### 4.2 The Event Log

Every state change is recorded as an immutable event in an append-only log. Format (adapted from game netcode):

```
Event {
    sequence: u64,                    # Monotonically increasing
    timestamp: DateTime,              # Wall clock (for debugging, not determinism)
    event_type: EventType,            # User action, API response, webhook, cron, proxy-minted
    schema_version: u32,              # Compiler-assigned version
    payload: bytes,                   # Serialized event data
    state_hash_after: [u8; 32],       # SHA-256 of state after this event
    parent_hash: [u8; 32],            # Hash of previous event (chain integrity)
}
```

The hash chain (`state_hash_after` + `parent_hash`) makes the log tamper-evident. The proxy can verify the chain without understanding the events -- it just checks that each event's `parent_hash` matches the previous event's hash.

**Event classification (from game netcode's "external event log" pattern):**
- **Pure computations** (safe blocks): deterministic by construction. Re-executed during replay.
- **External events** (API responses, webhook payloads): non-deterministic. Logged with results, substituted during replay.
- **User inputs**: the action itself is the input. Applied from log during replay.
- **Proxy-minted events**: only generated by the proxy. Cannot be forged by the client.

### 4.3 Writer Model: Distributed Single-Player

This is NOT multiplayer. There is exactly one writer at any time -- either the client or the server, never both. This eliminates the need for CRDTs, multi-writer conflict resolution, or consensus protocols.

**Lease model (adapted from LiteFS):**
- The client holds the write lease while online
- Lease is maintained via proxyFetch calls (each call renews the lease)
- If the lease expires (client offline, no proxyFetch for N seconds), the server takes over
- Server processes webhook payloads and cron handlers during offline, generating events in the log
- When the client reconnects, it receives the server-generated events and applies them locally
- The client resumes the lease

**Fencing tokens (from LiteFS):** Each lease transfer increments a monotonic fencing token. Events include the fencing token of the lease holder that generated them. If a stale client (with an old fencing token) tries to push events after lease transfer, the proxy rejects them. This prevents split-brain: the client's reconnection sync always starts by acknowledging the server's events before pushing its own.

**Reconnection merge:** Since only one writer exists at any time, the merge is sequential, not concurrent. The server's events (generated during offline) come first; the client's events (generated during the lease gap, if any) come after. If the client made local changes during the brief window between lease expiry and reconnection, those are appended after the server's events. The client rebases its materialized state.

### 4.4 Verification at Cost-Inducing Boundaries

Verification happens at proxyFetch boundaries -- the moment before the proxy spends money on an external API call. The proxy:

1. Receives the event log delta from the client
2. Verifies the hash chain (each `parent_hash` matches the previous event)
3. Optionally replays events through portable reducers (safe blocks) to verify `state_hash_after`
4. If verification passes: injects secrets, forwards the API call, mints any guarded-state events
5. Returns: API response + proxy-generated events + any pending server events (webhooks/crons)

This is the GGPO SyncTestSession pattern running in production: the client is the "normal" execution path, the server is the "replay" execution path. If their states agree via hash comparison, the client is verified.

**Graduated divergence response (from game netcode):**
1. **Single hash mismatch:** Log with full context. Use Merkle tree to identify which state domain diverged. Likely a determinism bug.
2. **Repeated divergence:** Trigger full state comparison, identify the non-deterministic operation.
3. **Unrecoverable divergence:** Server state is authoritative. Client accepts server state. Nuclear option -- equivalent to reconnecting after a game desync.

### 4.5 Guarded State and Proxy-Minted Events

Some state has constraints that the client alone can't enforce. Credits, quotas, billing counters -- state where increases must be authorized by the proxy.

The proxy doesn't understand *what* credits are. It knows: "for state marked as `guard('credits')`, only events of type `proxy_minted` can increase the value." This is a mechanical rule, not domain logic.

**How it works:**
- Developer declares `guard("credits")`
- The compiler identifies which operations touch guarded state
- Operations that could increase guarded state are bundled with proxy calls (compile-time delegation)
- The proxy generates `proxy_minted` events after successful API calls (e.g., "deducted 1 credit for OpenAI call")
- The client applies proxy-minted events to its local state
- Verification is binary: "did I (the proxy) generate this event?" -- very low false-positive risk

**Three tiers of state:**
1. **Per-user, client-sovereign:** Normal state. Client is authoritative. No proxy involvement in writes.
2. **Per-user, proxy-observable (guarded):** State with constraints. Proxy enforces invariants via minted events. Declared with `guard()`.
3. **Shared, multi-user:** Org-level state. Lives in an org-level DO. Multiple users connect via WebSocket, DO sequences all events. Declared with `shared()`. See Section 4.10.

### 4.6 Compile-Time Delegation

The Nim compiler analyzes code at compile time to determine what should run on the client vs. the server:

- **Single proxyFetch:** Runs on the client. Event log piggybacked on the call.
- **Multiple sequential proxyFetch calls:** The compiler detects this pattern and delegates the entire block to the server. Instead of 3 round-trips (client -> proxy -> API, client -> proxy -> API, client -> proxy -> API), the server executes all 3 API calls locally, then returns the combined result.
- **Guarded state mutations accompanying API calls:** The compiler bundles these with delegation automatically.

The first proxyFetch call bootstraps the delegation. The server has the compiled program (portable Nim code compiled to JS running in the DO). The compiler makes this decision based on static analysis of the call graph -- no developer annotation required.

```nim
# The compiler sees 3 sequential proxyFetch calls
# and automatically delegates this block to the server
proc generateReport() =
  let data = proxyFetch(DATA_API, headers = {"Auth": "Bearer " & secret("key")})
  let analysis = proxyFetch(AI_API, body = %*{"data": data, ...})
  let chart = proxyFetch(CHART_API, body = %*{"analysis": analysis, ...})
  saveReport(data, analysis, chart)
```

This eliminates the performance cliff where sequential proxy calls would be slower than a traditional backend. The compiler turns `proxyFetch` into a transparent boundary: single calls stay client-side, multi-call workflows move server-side, and the developer writes the same code either way.

### 4.7 Snapshots and Log Compaction

The event log grows indefinitely. To keep replay fast and storage bounded:

- **Periodic snapshots** (every N events or every M minutes): Full materialized state snapshot stored alongside the log. Replaying only requires events since the last snapshot.
- **Ring buffer of snapshots:** Old snapshots are garbage-collected after verification. Only the most recent K snapshots are kept.
- **Log truncation after snapshot:** Events before the oldest retained snapshot can be archived (R2) or deleted.
- **Snapshot + Reset for major migrations:** Materialize current state, take a final snapshot, start a new log with a new schema version.

### 4.8 State Hashing

Hierarchical Merkle tree over state domains:

```
Root Hash = hash(
    hash(domain_1_state),
    hash(domain_2_state),
    hash(domain_3_state),
    ...
)
```

When root hashes differ between client and server, drill down to find which domain diverged. This is O(log N) instead of O(N) for divergence localization. Each event's `state_hash_after` is the root of this tree.

### 4.9 The WebSocket Channel

The client maintains a hibernated WebSocket connection to its Durable Object (introduced for lease detection in Section 8.6). This connection exists regardless -- it's needed for presence. Since it's already there, it becomes a general-purpose channel between the user's DO and their client.

**What the WebSocket gains us:**

1. **Immediate delivery of server-generated events.** When a webhook fires while the client is online, the DO processes it and pushes the resulting events over the WebSocket immediately. The client doesn't wait until the next proxyFetch to learn that an image was generated or a payment was received. This transforms the UX from "poll on next action" to "instant notification."

2. **proxyFetch as a WebSocket message.** `proxyFetch(...)` is developer-facing syntax. Under the hood, it can ride the existing WebSocket (with request/response correlation via message IDs) or fall back to HTTP if the WebSocket is down. The developer never knows or cares. The event log delta piggybacks on the same message either way.

3. **Cron results pushed immediately.** A cron handler that runs server-side every 6 hours can push its results to the client the moment it finishes, if the client happens to be online. No waiting.

4. **Richer sync UX.** The client can show "synced" / "pending" / "receiving update..." states accurately, because the DO pushes events as they happen rather than batching them on the next proxyFetch.

5. **No separate heartbeat infrastructure.** The WebSocket auto-response mechanism (`setWebSocketAutoResponse`) handles lease detection without additional plumbing.

**What the WebSocket does NOT change:**

The WebSocket serves two distinct topologies depending on whether state is personal or shared:

```
Personal state:   Alice's Client <--ws--> Alice's DO (single-writer, lease model)
                  Bob's Client   <--ws--> Bob's DO   (single-writer, lease model)

Shared state:     Alice's Client --ws--\
                  Bob's Client ---ws----> Org DO (sequences all events)
                  Carol's Client -ws--/
```

Per-user events (webhooks, crons, API results) are pushed to the user's personal DO immediately. Shared state events go through the org DO, which broadcasts to all connected clients. See Section 4.10 for the full model.

**The boundary (resolved):**

The WebSocket enables multi-user shared state WITHOUT cross-DO fan-out and WITHOUT CRDTs. The solution: for `shared()` state, multiple users connect to the **same org-level DO** rather than each having their own. The DO is single-threaded, providing natural total ordering. No distributed consensus needed, no CRDT slope. See Section 4.10 for the full model.

### 4.10 Shared State and Multi-User Organizations

The single-player model (Sections 4.3-4.6) handles personal apps. For organizations -- multiple users contributing to a shared pool of state -- the `shared()` primitive introduces a different writer model that avoids CRDTs by leveraging the Durable Object as a natural sequencer.

**Key insight: Cloudflare DOs support up to 32,768 concurrent WebSocket connections per object.** This is a primary use case (Cloudflare's canonical example is a chat room). A single DO is single-threaded with input gates that automatically serialize all storage operations. No explicit locking needed.

**Topology:**

```
Alice's Client --ws--\
                      \
Bob's Client ---ws-----> Org DO (single-threaded, sequences all events)
                      /     |
Carol's Client -ws--/      SQLite (shared state)
                            |
                           D1 (cross-org metadata)
```

All three clients connect WebSockets to the same org DO. The DO assigns monotonically increasing sequence numbers to all events, regardless of which user generated them. Each client maintains a local copy of shared state and applies events in sequence order.

**What the compiler infers from `shared()` -- no developer annotation per operation:**

The compiler statically analyzes each operation that touches shared state and classifies it:

| Pattern detected | Classification | Behavior |
|---|---|---|
| Mutates shared state, no proxyFetch, not destructive | **Optimistic** | Apply locally, send to DO for sequencing, confirm/rollback |
| Mutates shared state, sets a tombstone/deleted status | **Barrier** | Send to DO immediately, DO broadcasts to all connected clients |
| Contains proxyFetch + references shared state | **Verified** | DO checks that referenced entities are valid before forwarding API call |
| Reads shared state only | **Local** | Read from local materialized view, no coordination |

The compiler detects barriers via static analysis: any operation that transitions shared state to a terminal status (a field set to `Deleted`, `Archived`, `Cancelled`, etc.) is a barrier. The specific sentinel values are inferred from enum definitions in the schema.

**Implementation-time design required:** The exact AST patterns that trigger barrier classification need to be worked out during the build. Candidate heuristics: matching enum field assignments where the target variant name contains "Delete"/"Archive"/"Cancel"/etc., or an explicit `barrier` annotation as a fallback if the heuristic isn't reliable enough. The PoC (Appendix C) demonstrates the AST walking pattern (`nnkCall`, `nnkIdent` matching) that this would build on.

**What happens mechanically:**

1. **Optimistic operations** (creates, appends, renames): applied locally for instant UX. Event sent to org DO. DO assigns sequence number, persists, broadcasts to all connected clients. If the DO rejects (e.g., entity was deleted between local apply and DO confirmation), client rolls back.

   **Implementation-time design required:** The rollback mechanism needs to be worked out during the build. Three candidate approaches: (a) pre-operation snapshot of affected state, restored on rejection; (b) compiler-generated inverse operations (e.g., `insert` → `delete`, `update` → reverse update with saved prior values); (c) simply replaying the confirmed event stream from the DO and recomputing materialized state. Option (c) is the simplest and most robust but may be slow for large state. The right choice depends on typical state sizes encountered during implementation.

2. **Barrier operations** (deletes, cancellations): sent to the DO eagerly. DO applies, broadcasts immediately to all connected clients. The WebSocket push ensures online users learn about barriers within ~100ms. Offline users learn on reconnection.

3. **Verified operations** (anything with proxyFetch): already routed through the DO because proxyFetch requires the proxy. The DO verifies that referenced shared entities are in a valid state before forwarding the API call. If the shoot was deleted 50ms ago and the broadcast hasn't reached the client yet, the DO catches it and rejects the request. No money spent.

**Critical safety property: costly operations cannot happen offline.** proxyFetch requires network connectivity. A user who is offline cannot trigger API calls that cost money. Therefore, the "incurred costs on a deleted resource" scenario can only occur in the brief window between a barrier event and its WebSocket broadcast -- and the DO catches this because all proxyFetch calls go through it.

#### Worked Example: OrgShoots

Three users manage photoshoots. Alice does most of the work. Bob and Carol contribute occasionally. The org has shared credits for AI photo editing.

```nim
shared("shoots")
guard("credits")

type ShootStatus = enum Active, Deleted

type Shoot = object
  id, name: string
  status: ShootStatus
  photos: seq[Photo]

proc createShoot(name: string) =
  db.insert(Shoot(id: newId(), name: name, status: Active))

proc deleteShoot(id: string) =
  db.update("shoots", id, status = Deleted)

proc addPhoto(shootId: string, url: string) =
  db.insert(Photo(shootId: shootId, url: url))

proc editPhoto(shootId: string, photoId: string, prompt: string) =
  let result = proxyFetch(AI_API,
    headers = {"Authorization": "Bearer " & secret("ai-key")},
    body = %*{"image": photos[photoId].url, "prompt": prompt}
  )
  db.update("photos", photoId, editedUrl = result["url"].getStr)
```

**Compiler classification:**

| Operation | proxyFetch? | Destructive? | Ruling |
|---|---|---|---|
| `createShoot` | No | No | Optimistic |
| `deleteShoot` | No | Yes (→ Deleted) | Barrier |
| `addPhoto` | No | No | Optimistic |
| `editPhoto` | Yes ($$$) | No | Verified |

4 operations, 1 barrier, 1 verified (already covered by proxyFetch), 2 fire-and-forget. The vast majority of daily operations are optimistic and conflict-free.

**Scenario 1: Normal day, everyone online**

```
10:00  Alice: createShoot("Beach Shoot")
       → local: instant
       → event → org DO (seq #1) → broadcast to Bob, Carol
       → Bob/Carol see it ~100ms later

10:05  Bob: addPhoto(shoot1, beachPhoto)
       → local: instant
       → event → org DO (seq #2) → broadcast
       → Alice, Carol see the photo

10:10  Alice: editPhoto(shoot1, photo1, "enhance lighting")
       → proxyFetch → org DO
       → DO checks: shoot exists? ✓  credits > 0? ✓
       → forwards to AI API, mints credit deduction
       → broadcasts result + credit event to all
```

No conflicts. Events flow through the DO as sequencer.

**Scenario 2: Delete + cost collision (the dangerous case)**

```
10:00      Alice: deleteShoot(shoot5)
           → barrier: sent to org DO immediately
           → DO assigns seq #50, broadcasts to all

10:00.050  Bob hits "AI Edit" on a photo in shoot5
           (50ms before broadcast reaches him)
           → proxyFetch → org DO
           → DO checks: shoot5 exists? NO (deleted at seq #50)
           → rejects: {error: "shoot_deleted", by: "alice", at: #50}
           → Bob's client: "This shoot was deleted by Alice"
           → $0.00 spent
```

The proxyFetch catches it even in the race window.

**Scenario 3: Offline user adds to deleted shoot**

```
10:00       Alice: deleteShoot(shoot5) → DO broadcasts

10:00-12:00 Bob is on the subway:
            - browses local state (reads are free)
            - queues 5 addPhoto events locally
            - CANNOT hit "AI Edit" (proxyFetch grayed out -- no network)

12:00       Bob reconnects:
            → receives events since last sync (including Alice's delete)
            → Bob's 5 queued events reference deleted shoot5
            → DO rejects: {error: "shoot_deleted", rejected: [B1..B5]}
            → Bob's client rolls back, shows: "Beach Shoot was deleted
              while you were offline. 5 photos were not uploaded."
```

No money spent. Bob's offline work is lost, but he was offline in a multiplayer context -- the tradeoff is explicit.

**Scenario 4: Concurrent creates (the non-issue)**

```
10:00  Alice: createShoot("Beach Shoot") → seq #1
10:01  Bob: createShoot("Beach Shoot") → seq #2

Result: Two shoots with the same name. Both valid.
Append-only creates with unique IDs never conflict.
Someone notices the duplicate and cleans up. This is a UX concern, not a protocol concern.
```

**Scenario 5: Delete + re-create race**

```
10:00  Alice: deleteShoot(id=5, "Beach Shoot") → seq #10
10:01  Bob (stale by 200ms): createShoot("Beach Shoot") → seq #11

Result: Shoot #5 is deleted. New shoot #6 "Beach Shoot" exists.
Bob didn't "re-create" #5 -- he created #6 with a new ID.
No identity confusion. No accidental resurrection.
```

**The boundary this draws:**

| Works without CRDTs | Would require CRDTs |
|---|---|
| Multiple users creating independent resources | Multiple users editing the same document simultaneously |
| One user deletes, others notified and blocked | Offline editing of shared resources with auto-merge |
| Costly operations verified at the DO before execution | Conflict-free concurrent field-level edits |
| Append-only operations (add photo, create shoot) | Reordering, moving, or restructuring shared collections |

This model handles "multiple people contribute to a shared pool" (the org use case) without CRDTs. It does NOT handle "multiple people edit the same thing at the same time" (the Google Docs use case). That boundary is deliberate and declared out of scope.

### 4.11 Wire Protocol Sketch

What proxyFetch and WebSocket messages actually look like on the wire. JSON for readability; binary optimization is a v2 concern.

**proxyFetch request** (client → DO, either HTTP POST or WebSocket message):

```json
{
  "type": "proxyFetch",
  "id": "msg_a1b2c3",
  "fencing_token": 47,
  "events_since": 1023,
  "events": [
    {
      "sequence": 1024,
      "timestamp": "2026-02-08T14:30:00Z",
      "event_type": "user_action",
      "schema_version": 3,
      "payload": {"action": "add_photo", "shoot_id": "s5", "url": "..."},
      "state_hash_after": "a3f8...",
      "parent_hash": "b7c1..."
    }
  ],
  "request": {
    "url": "https://api.openai.com/v1/images/edits",
    "headers": {"Authorization": "Bearer {{secret:ai-key}}"},
    "body": {"image": "...", "prompt": "enhance lighting"}
  }
}
```

**proxyFetch response** (DO → client):

```json
{
  "type": "proxyFetch_response",
  "id": "msg_a1b2c3",
  "events_accepted": true,
  "server_events": [
    {
      "sequence": 1025,
      "event_type": "proxy_minted",
      "payload": {"action": "credit_deducted", "amount": 1, "remaining": 42},
      "state_hash_after": "d4e5...",
      "parent_hash": "a3f8..."
    },
    {
      "sequence": 1026,
      "event_type": "webhook_result",
      "payload": {"webhook_id": "wh_7", "data": {"image_url": "..."}},
      "state_hash_after": "f6a7...",
      "parent_hash": "d4e5..."
    }
  ],
  "response": {
    "status": 200,
    "body": {"url": "https://...edited-image.png"}
  }
}
```

**proxyFetch rejection** (DO → client, when context is stale):

```json
{
  "type": "proxyFetch_response",
  "id": "msg_a1b2c3",
  "events_accepted": false,
  "rejection": {
    "reason": "entity_deleted",
    "entity": "shoot",
    "id": "s5",
    "deleted_at_sequence": 1020,
    "deleted_by": "user_alice"
  },
  "server_events": [
    {"sequence": 1020, "event_type": "user_action",
     "payload": {"action": "delete_shoot", "shoot_id": "s5"}}
  ]
}
```

**WebSocket event push** (DO → client, unsolicited):

```json
{
  "type": "event_push",
  "events": [
    {
      "sequence": 1030,
      "event_type": "user_action",
      "origin_user": "user_bob",
      "payload": {"action": "create_shoot", "name": "Sunset Shoot"},
      "state_hash_after": "c8d9...",
      "parent_hash": "b7c1..."
    }
  ]
}
```

**WebSocket barrier push** (DO → all connected clients, immediate):

```json
{
  "type": "barrier",
  "events": [
    {
      "sequence": 1031,
      "event_type": "user_action",
      "origin_user": "user_alice",
      "payload": {"action": "delete_shoot", "shoot_id": "s5"},
      "state_hash_after": "e0f1...",
      "parent_hash": "c8d9..."
    }
  ]
}
```

The `id` field on proxyFetch messages provides request/response correlation when riding the WebSocket. Over HTTP, correlation is implicit (one request, one response).

---

## 5. Schema Evolution

Event types are defined in Nim code. The compiler is the schema registry.

### Three-Tier Strategy

**Tier 1 -- Automatic (Tolerant Reader):**
- New optional fields with defaults
- Property renames via serializer annotations
- No migration code needed
- Compiler detects these via schema diffing

**Tier 2 -- Upcasting (Pure Function Transformers):**
- Structural event changes: `oldEvent -> newEvent`
- Applied on read, not on stored data
- Must be `safe` blocks (compiler-verified pure)
- Can be chained: v1 -> v2 -> v3
- Auto-generated by compiler for simple transformations, LLM-authored for complex ones

**Tier 3 -- Snapshot + Reset:**
- Major schema redesigns
- Materialize current state as snapshot, truncate log, start fresh
- Requires client-server coordination during a sync boundary

### Version Mismatch Handling

Each event includes a `schema_version` field. When the proxy encounters events from a different schema version, it applies the appropriate upcaster chain. The compiler generates all upcasters and includes them in the proxy artifact.

**Principle from event sourcing:** "Compensate, don't mutate." Append correction events rather than changing history. The log is immutable.

---

## 6. Infrastructure Mapping

### Reference Implementation: Cloudflare

| Framework Concept | Cloudflare Primitive | Role |
|---|---|---|
| Router | Worker | Stateless request routing |
| Per-user state | Durable Object (SQLite) | Event log, materialized state, lease, secrets |
| Shared metadata | D1 | User lookup, auth tables, webhook routing |
| Auth data | D1 | User/account tables (Oslo + Arctic generated) |
| Assets | R2 | Blob storage (images, files), zero egress |
| Config | KV | Feature flags, public keys |
| Async work | Queues | Webhook payload buffering |
| Scheduled work | Cron Triggers | `cron()` primitive |
| Offline processing | DO Alarms | Server-side handler execution when client is offline |
| Auth secrets | Worker Secrets | JWT signing key, OAuth client secrets |

### Request Flow

```
Client (Browser)
  |
  | proxyFetch (with event log delta, JWT)
  v
Router Worker (stateless)
  |
  | 1. Validate JWT (Oslo)
  | 2. Route by user ID
  v
User Durable Object
  |
  | 3. Verify event log hash chain
  | 4. Optionally replay for state verification
  | 5. Inject secrets
  | 6. Forward API call (or delegate multi-call block)
  | 7. Mint guarded-state events
  | 8. Return: API response + server events
  v
Client applies server events, updates local state
```

### Pricing Considerations

- DO write pricing ($1.00/million SQLite rows) is the primary cost driver
- Batch writes to minimize row operations
- Event log compaction reduces long-term storage
- Most apps stay within free tier (50M writes/month included)
- R2 has zero egress fees -- asset-heavy apps are well-served

### Key Limitations

- DO location is permanent after creation (no migration)
- 128 MB memory per isolate (large state must live in SQLite)
- Single-threaded DOs (~1K req/s per user max)
- No cross-DO transactions (each user is isolated)

---

## 7. Migration and Ejection

The framework follows the "regenerable artifacts" pattern (inspired by Expo Prebuild, not CRA Eject). Every build produces standalone artifacts that run without the framework.

### Generated Artifacts

```
_generated/
  migrations/            # SQL migration files (standard SQLite/Postgres DDL)
  functions/             # Standalone HTTP handlers (Web Fetch API compatible)
    api/
    webhooks/
    cron/
  client/                # Standalone JS/HTML/CSS
  openapi.yaml           # API specification
  crontab                # Standard crontab entries
  cloudflare/            # Cloudflare-specific configs (wrangler.toml, etc.)
  .env.example           # Environment variables template
```

### Extraction Lifecycle

```
Stage 0: Fully Managed -- `unanim deploy` handles everything
Stage 1: Inspect      -- `unanim inspect` shows all generated artifacts
Stage 2: Export       -- `unanim export --component cron` produces standalone scripts
Stage 3: Override     -- `unanim detach cron` marks cron as externally managed
Stage 4: Hybrid       -- Some components managed, some external
Stage 5: Extracted    -- All artifacts standalone, framework not needed
```

### Anti-Lock-In Checklist

For every feature: (1) What standard format does it map to? (2) Can the generated artifact run without the framework? (3) Can this feature be extracted without extracting everything? (4) Can users drop down to the standard layer at any point? (5) Is the extraction path documented and tested?

---

## 8. Hard Problems (Resolved)

### 8.1 -- The Sync Engine *(was Section 4.1)*

**Resolution:** Custom event-log-based sync protocol. No existing sync engine provides our specific combination of requirements. The protocol is described in Section 4.

**Key decisions:**
- Event-sourced append-only log (inspired by LiveStore)
- Lease-based single-writer (inspired by LiteFS)
- Verification at cost-inducing boundaries (inspired by GGPO SyncTestSession)
- Merkle tree for divergence localization (from game netcode)
- Graduated divergence response (from game netcode)
- No CRDTs (distributed single-player, not multiplayer)

### 8.2 -- Asset Storage *(was Section 4.2)*

**Resolution:** R2 for blob storage. Assets referenced by URL in events, not inline. The proxy stores webhook-delivered assets (images, files) in R2, keyed by event ID. Client fetches assets by URL. Garbage collection: when events referencing an asset are compacted away, the asset is eligible for cleanup.

Asset streaming for large files (video, datasets) is a v2 concern.

### 8.3 -- Schema Evolution *(was Section 4.3)*

**Resolution:** Three-tier strategy described in Section 5. The compiler as schema registry. Upcasters are safe blocks (compile-time verified pure). LLMs author complex upcasters; simple ones are auto-generated.

### 8.4 -- Shared / Multi-tenant State *(was Section 4.4)*

**Resolution:** The `shared()` primitive and org-level Durable Objects (Section 4.10). Multiple users connect to the same org DO via WebSocket. The DO is single-threaded, providing natural total ordering of events without CRDTs or distributed consensus.

**Three tiers of state** (unchanged from Section 4.5), but now with concrete mechanisms:
1. **Per-user, client-sovereign:** Personal DO per user. Single-writer, lease model.
2. **Per-user, proxy-observable (guarded):** Personal DO, proxy mints events. `guard()` primitive.
3. **Shared, multi-user:** Org DO, sequenced multi-writer. `shared()` primitive. Optimistic local + server confirmation. Barriers for destructive operations. DO verifies context before costly operations.

**For the "organization with credits" use case:** Credits are `guard()`ed in the org DO. Each user's proxyFetch goes through the org DO, which mediates atomically (DO is single-threaded). The client never directly writes to guarded state -- it requests actions, and the DO mints the appropriate events.

**Key safety property:** Costly operations (proxyFetch) cannot happen offline, so the "spent money on stale context" scenario is limited to the brief WebSocket broadcast latency window -- and the DO catches it because all proxyFetch calls are verified against current state.

See the OrgShoots worked example and stress tests in Sections 4.10 and 10.

### 8.5 -- Large State / ETL *(was Section 4.5)*

**Resolution:** The lease model handles this naturally. During a long-running cron job (ETL), the server holds the write lease. It generates events incrementally, stored in the DO's SQLite. When the client reconnects, it receives the events as a batch. The client applies them to its local state incrementally (not all at once -- events stream in via the sync response).

**Capacity:** DO SQLite supports up to 10GB. For ETL workloads exceeding this, extraction to standalone infrastructure is recommended (Section 7).

**Known footgun -- the ETL pull-down problem:** If a cron generates a large amount of data server-side (thousands of events, megabytes of state), the next client login must pull all of it down before the client has a usable local DB. This is a "know your framework" concern -- developers running heavy ETL via crons should be aware that the client's first sync after an ETL run will be proportional to the data generated. The framework should be smart about this: if the client connects and has no local DB (or a stale one), stream the current snapshot rather than replaying the entire event log. The snapshot-based approach (Section 4.7) means the client downloads the latest snapshot + events since, not the full history.

### 8.6 -- Offline Detection *(was Section 4.6)*

**Resolution:** Three-layer lease mechanism using Cloudflare DO's built-in infrastructure. No custom heartbeat protocol.

**Layer 1: proxyFetch (primary renewal).** Every proxyFetch call renews the lease. The DO records `lastProxyFetch = Date.now()` and reschedules its alarm. This is opportunistic lease renewal -- a pattern formalized in the literature (IEEE ICDCS 2001, "An Analytical Study of Opportunistic Lease Renewal"), which shows it reduces dedicated keepalive traffic by a factor of 50.

**Layer 2: Hibernated WebSocket with auto-response (passive monitoring).** On page load, the client opens a WebSocket to the DO. The DO calls `acceptWebSocket(ws)` and `setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"))`. The client sends `"ping"` every 30 seconds. The Cloudflare edge auto-responds without waking the DO -- zero cost, zero billable duration. `getWebSocketAutoResponseTimestamp(ws)` gives a "last seen" timestamp for free. The DO hibernates (~10s after last activity) and is not billed while asleep.

**Layer 3: DO Alarm (lease timeout trigger).** The DO sets an alarm for `lastProxyFetch + LEASE_TIMEOUT`. When the alarm fires:
1. `getWebSockets()` -- if empty, client disconnected. Server takeover immediately.
2. If WebSocket exists, check `getWebSocketAutoResponseTimestamp(ws)` -- if older than timeout, client stopped pinging. Server takeover.
3. If pings are recent but no proxyFetch, client is idle but online. Leave lease active.

**Default timeout: 120 seconds.** Based on the Gray-Cheriton analysis (10-30s optimal for datacenter), adjusted for browser-to-edge variance. Long enough to tolerate a brief mobile network hiccup, short enough that webhooks process within 2 minutes of genuine offline. Configurable per-application.

**Clean disconnect:** `beforeunload` closes the WebSocket explicitly (`ws.close(1000, "page_unload")`), triggering immediate detection. Unreliable on mobile, so the alarm is the fallback.

**Academic backing:** Gray & Cheriton 1989 ("Leases: An Efficient Fault-Tolerant Mechanism for Distributed File Cache Consistency") -- the foundational leases paper. Short leases (10-30s) capture most of the benefit. Our 120s timeout accounts for browser-to-edge latency variance. Fencing tokens (already in our design from LiteFS) prevent the stale-writer problem Kleppmann warns about.

### 8.7 -- Progressive Migration *(was Section 4.7)*

**Resolution:** Framework as compiler, not runtime (Section 7). Regenerable artifacts, incremental extraction, standard formats underneath. Inspired by Expo Prebuild (reversible, repeatable) and Supabase ("just Postgres").

---

## 9. What's Explicitly Out of Scope

**Custom server-side logic.** The proxy does not execute arbitrary application code beyond portable handlers. If a developer needs a custom server endpoint that doesn't fit one of the primitives, that's a different tool.

**Real-time collaborative editing.** The `shared()` primitive supports multi-user organizations where people contribute to a shared pool (creating resources, adding items, managing state). It does NOT support multiple people editing the same document or field simultaneously. CRDTs and operational transforms are out of scope. The boundary: "multiple people contribute to a shared pool" is in; "multiple people edit the same thing at the same time" is out.

**Domain-aware proxy logic.** The proxy never interprets the business meaning of API requests, events, or state. It processes logs, verifies hashes, swaps secrets, mints guarded events, and runs portable code. The guard mechanism is mechanical ("only proxy-minted events can increase this counter"), not semantic ("don't let credits go below zero" -- that's client-side business logic).

**Frontend framework.** The system is not a UI framework in the React/Vue/Svelte sense. It generates static HTML at compile time and JIT-loads minimal JS islands where interactivity is needed. You can build UI frameworks on top of this system.

**Multi-region replication.** The system uses Cloudflare's global network, but does not build custom replication across regions. DO location is permanent. Users who relocate permanently would need manual migration (create new DO, copy state).

---

## 10. Testing Strategy

### Dual-Execution Test Mode (from GGRS SyncTestSession)

Run in CI for every action type:

1. Client processes action A, producing state S_client with hash H_client
2. Load state from before action A
3. Replay action A using server-side replay logic (portable code)
4. Compute hash H_server
5. Assert H_client == H_server
6. If not: dump both states, diff them, identify the non-deterministic operation

This catches determinism bugs before they reach production. From GGPO experience: this is the single most valuable tool for catching verification failures.

### Integration Tests

- **Hash chain verification:** Generate a sequence of events, verify the chain is valid
- **Lease transfer:** Simulate client going offline, server taking over, client reconnecting
- **Guarded state:** Verify that forged proxy-minted events are rejected
- **Schema evolution:** Apply upcasters to old events, verify resulting state
- **Extraction:** Run generated standalone artifacts, verify they produce the same results

### Shared State Stress Tests (the "OrgShoots" suite)

Derived from the photoshoot worked example (Section 4.10). These simulate a 3-user org under adversarial timing conditions. The test harness controls network delivery timing to force every race window.

**Test 1: Delete + proxyFetch race.**
Alice sends a barrier delete for shoot #5. Bob sends a proxyFetch (editPhoto on shoot #5) that arrives at the DO within 0-200ms of the delete. Assert: the DO rejects Bob's proxyFetch if it arrives after the delete is sequenced. Assert: $0.00 in API calls forwarded. Vary the timing across the full 0-200ms window. This is the most critical safety property.

**Test 2: Offline accumulation + reconnect rejection.**
Bob goes offline. Alice deletes shoot #5. Bob queues N optimistic events referencing shoot #5 (N = 1, 10, 100, 1000). Bob reconnects. Assert: all N events are rejected. Assert: Bob's local state rolls back cleanly to match the DO's state. Assert: no partial application (either all rejected or none).

**Test 3: Barrier broadcast latency.**
Alice deletes shoot #5 (barrier). Measure time until Bob and Carol's clients receive the broadcast. Assert: < 200ms for connected clients. Simulate WebSocket reconnection (client briefly disconnected during broadcast) and assert the barrier is delivered on reconnection.

**Test 4: Concurrent optimistic operations.**
All three users simultaneously create shoots and add photos (high-frequency optimistic operations). Run for 60 seconds. Assert: all three clients converge to identical materialized state. Assert: no events lost, no duplicates, sequence numbers are gap-free.

**Test 5: Optimistic rollback correctness.**
Bob creates shoot #7 (optimistic, applied locally). Before the DO confirms, the DO rejects it (e.g., org has hit a shoot limit enforced by the DO). Assert: Bob's local state rolls back, shoot #7 disappears from his UI. Assert: no stale references to shoot #7 remain in Bob's local DB.

**Test 6: Stale client with costly operation.**
Bob's client has not synced in 2 hours. During that time, Alice deleted shoot #5 and Carol created shoots #6-#10. Bob attempts editPhoto on shoot #5. Assert: DO rejects before forwarding to AI API. Bob then syncs. Assert: Bob's state catches up to current (shoots #6-#10 appear, #5 gone).

**Test 7: Mixed personal + shared state.**
Bob has personal state (user preferences in his per-user DO) and shared state (shoots in the org DO). Both are modified concurrently. Assert: personal state sync and shared state sync do not interfere. Assert: offline personal state is preserved even when shared state events are rejected.

---

## 11. Resolved Design Decisions

Decisions made during the 0.0.0 -> 0.1.0 research session:

1. **Client storage: IndexedDB with compile-time SQL abstraction.** The framework abstracts IndexedDB entirely. Developers write SQL-like queries; the compiler validates them against migrations and rejects illegal operations. No WASM SQLite (1.5MB bundle is too steep). If we can do it with IndexedDB, we should.

2. **Event log serialization: JSON.** Readable, debuggable, LLM-friendly. Verbose, but event logs are not the bandwidth bottleneck -- API call payloads are. Optimization to binary formats is a v2 concern if it ever matters.

3. **Delegation threshold: 2+ I/O-bound operations.** If the compiler sees 2 or more sequential proxyFetch calls, it delegates the block to the server. There is no point doing a round-trip if you're going to beam back up again. Developers can also hint delegation explicitly.

4. **Lease timeout: 120 seconds default.** Three-layer mechanism: proxyFetch renewal (primary), hibernated WebSocket auto-response (passive), DO Alarm (timeout trigger). Based on Gray-Cheriton 1989 analysis, adjusted for browser-to-edge variance. See Section 8.6.

5. **Shared state conflicts are an application concern.** When two users simultaneously spend the last credit, the proxy mediates atomically via D1 transactions. The losing client gets a rejection. Handling that rejection is the developer's responsibility -- errors can happen anywhere, anytime, in any system.

6. **Multi-user orgs via org-level DO, not CRDTs.** Multiple users connect to the same org DO. The DO is single-threaded, providing natural total ordering. The compiler classifies operations on `shared()` state as optimistic, barrier, or verified -- no developer annotation needed. Online multiplayer works; offline multiplayer doesn't (offline users' shared-state events are rejected on reconnect). This is an acceptable tradeoff because the apps this framework targets require network connectivity for their core value (AI APIs, asset storage). See Section 4.10 and the OrgShoots stress tests in Section 10.

7. **Client storage eviction is the user's problem.** If Safari purges their data or they switch browsers, they re-download the DB from the server. The framework should be smart about this: detect stale/missing local state and stream the latest snapshot rather than replaying the full event log. But we don't design around Safari's 7-day eviction with special workarounds -- we design robust server-side persistence and fast re-sync.

## 12. Known Footguns

Things developers should be aware of when building on this framework:

1. **ETL pull-down.** If a cron generates a large amount of data server-side, the next client login must pull all of it. Mitigated by snapshot-based sync (download latest snapshot, not full event replay), but heavy ETL workloads will still produce a noticeable first-sync delay.

2. **DO location is permanent.** The Durable Object is created near the first request. If a user moves continents permanently, their DO stays where it was. This adds latency. Manual migration (create new DO, copy state) is possible but not automated.

3. **Write pricing at scale.** DO SQLite writes cost $1.00/million rows. Heavy-write workloads (many small events) should batch writes. Event log compaction helps long-term.

4. **Delegation is not free.** When the compiler delegates a multi-call block to the server, the server runs the compiled portable code. This means the server must have the compiled program. Version mismatches between client and server code must be handled (the compiler includes version identifiers in artifacts).

5. **Guarded state is mechanical, not semantic.** The proxy enforces "only proxy-minted events can increase this counter." It does NOT enforce "credits cannot go below zero" -- that's client-side business logic. If the client's business logic has a bug that spends credits it doesn't have, the proxy won't catch it (unless you also validate materialized state during replay).

---

## 13. Build Philosophy

This section is for the LLM (or human) executing the build. It describes how the implementation should proceed, not what it should produce.

### Learn by building

We have a detailed architectural vision. We also have zero lines of framework code. Many of our assumptions are educated guesses. The build process should be structured to validate assumptions early and revise them without shame. If the IndexedDB-as-SQL abstraction turns out to be impractical, we pivot. If the operation classification heuristic doesn't work via AST analysis alone, we add an explicit annotation. The vision doc is a compass, not a contract.

### Always build against the real thing

Every implementation step must be validated against real Cloudflare infrastructure (via `wrangler`) and a real browser (via Chrome DevTools MCP or equivalent). Not mocks. Not simulations. The real thing.

The reason: this framework makes claims about performance, behavior, and developer experience that can only be verified in the actual runtime environment. "proxyFetch piggybacks the event log" is a nice sentence — does it add 5ms or 500ms of latency? "The DO sequences events from multiple users" — at what throughput before it becomes a bottleneck? "IndexedDB abstracts to SQL-like queries" — how bad is the impedance mismatch in practice?

**Validation cadence:** For each primitive or protocol piece implemented:
1. Write a minimal test that exercises it against real Cloudflare (deployed via `wrangler dev` or `wrangler deploy`)
2. Write a minimal client that exercises it in a real browser
3. Measure: is it correct? Is it fast? Is the developer experience good?
4. If any answer is "no," revise the assumption before building more on top of it

This is not "build the whole framework, then test." This is "build one thing, validate it end-to-end, build the next thing."

### Test-driven, but more than tests

TDD for correctness: write the test, write the implementation, verify. Standard practice.

But also: **performance validation from day one.** If proxyFetch adds meaningful latency, we need to know before we build 10 more primitives on top of it. If IndexedDB queries are too slow for reactive UI, we need to know before we build the entire client abstraction layer.

And also: **real-world plausibility checks.** Deploy a tiny test app to Cloudflare. Open it in a browser. Use Chrome DevTools to inspect the network, the IndexedDB state, the WebSocket messages. Does it feel right? Would a developer trust this? Does the sync actually work when you put the browser in airplane mode and come back?

### Build order (suggested, not rigid)

```
Phase 1: Foundation
  - Nim macro that detects proxyFetch + secret() and generates a Cloudflare Worker
  - Deploy to real Cloudflare, verify credential injection works
  - Client JS that calls proxyFetch, verify round-trip

Phase 2: State
  - Event log: append events, hash chain, verify at proxyFetch boundary
  - IndexedDB storage on client, SQLite storage in DO
  - Validate: events survive browser refresh, DO restart

Phase 3: Sync
  - Event log piggybacked on proxyFetch (bidirectional)
  - Lease mechanism (three-layer)
  - Offline → reconnect → merge
  - Validate: airplane mode test, lease timeout test

Phase 4: Primitives
  - guard() + proxy-minted events
  - webhook() + cron()
  - shared() + org DO + barrier broadcast
  - auth()
  - Validate: OrgShoots stress tests

Phase 5: Polish
  - Compiler errors (LLM-friendly)
  - Migration/ejection artifacts
  - Documentation, README, getting-started
  - Performance benchmarks
```

Each phase produces a working, deployable artifact. No phase depends on "we'll integrate it later." If Phase 2 reveals that our IndexedDB approach doesn't work, we find out before Phase 3 builds on it.

### Revise this document

This vision doc should be updated as the build progresses. When an assumption is validated, note it. When an assumption is wrong, cross it out and write what we learned. The doc is a living artifact, not a historical record.

---

## Appendix A: Prior Art Mapping

| Our Need | Best Prior Art | What We Borrowed | What We Built New |
|---|---|---|---|
| Event-sourced sync | LiveStore | Event -> materialized state pattern, push/pull model | On-demand sync timing (not continuous), proxyFetch piggybacking |
| Single-writer lease | LiteFS | Lease acquisition/release, fencing tokens, rolling checksums | Browser-to-edge lease transfer, DO-based implementation |
| State verification | GGPO SyncTestSession | Dual-execution verification, hash comparison | Verification at cost-inducing boundaries, Merkle tree |
| Schema evolution | Marten (event sourcing) | Upcasting, tolerant reader, snapshot+reset | Compiler as schema registry, safe-block-verified upcasters |
| Auth | Oslo + Arctic | OAuth 2.0 flows, JWT, password hashing | Compiler-generated auth routes, declarative config |
| Offline resilience | PouchDB, Firebase, WatermelonDB | Hybrid sync strategies | Lease-based offline handoff, server event generation |
| Migration | Expo Prebuild, Supabase | Regenerable artifacts, standard underneath | Framework as compiler, incremental extraction |
| Compile-time delegation | (none) | -- | Novel: Nim metaprogramming analyzes API call patterns |
| Proxy-minted events | Ethereum | Mechanical state rules, protocol-level authorization | Applied to SaaS billing, not cryptocurrency |
| Proxyetch piggyback sync | (none) | -- | Novel: sync piggybacked on application API calls |
| Lease detection | Gray-Cheriton 1989, etcd, Consul | Time-bounded leases, opportunistic renewal, fencing tokens | DO WebSocket hibernation + `setWebSocketAutoResponse` as zero-cost presence |
| Server event push | Firebase, PouchDB | Real-time push over persistent connection | Scoped to single-user DO, not cross-DO fan-out |
| Multi-user shared state | Replicache/Zero (server reconciliation), game netcode (dumb relay) | DO as sequencer, optimistic local + confirm/rollback, total ordering via single-threaded DO | Compiler-inferred operation classification (optimistic/barrier/verified), no developer annotation |

## Appendix B: Research Conducted

All research documents are in `research/`:
- `sync-engines/notes.md` -- Landscape survey + deep dives on LiveStore, Zero, PowerSync, LiteFS, cr-sqlite
- `game-netcode/notes.md` -- Deterministic replay, GGPO, rollback netcode, divergence detection
- `event-sourcing/notes.md` -- Schema evolution patterns, upcasting, Marten API
- `offline-first/notes.md` -- Browser APIs, sync patterns, Safari eviction, hybrid strategy
- `auth/notes.md` -- Auth landscape, Oslo+Arctic recommendation, JWT flows, D1 schema
- `migration-patterns/notes.md` -- Ejection patterns, anti-lock-in principles, Expo/Supabase/CRA analysis
- `cloudflare/notes.md` -- DO, D1, R2, KV, Queues, Cron Triggers, pricing, limits
- `client-storage/notes.md` -- wa-sqlite, IndexedDB, OPFS, benchmarks, Safari eviction

## Appendix C: Proof of Concept

A working POC exists demonstrating the compile-time macro approach:

- **`islands.nim`** -- Nim macro framework (~460 lines) that walks a DSL AST, generates static HTML, extracts event handlers as "islands" compiled to JS via `nim js` at compile time, performs macro-level tree shaking, and supports `safe()` blocks compiled to C for portability verification.
- **`example.nim`** -- Usage demonstration with two islands and two safe blocks.

The POC proves:
1. Nim's compile-time VM can invoke external compilers during macro expansion
2. AST rewriting at the macro level can eliminate runtime overhead (96.5% JS size reduction)
3. The same source code can compile to both JS and C, with platform-specific APIs automatically rejected
4. The portability check is not a convention -- it's a compilation proof

### Key Nim APIs demonstrated

The following patterns from the PoC are foundational to the framework's compiler:

**1. Invoking external compilers at macro time (`gorge`/`gorgeEx`):**

```nim
macro page*(body: untyped): string =
  let nimBin = gorge("which nim").strip()
  let tmpDir = "/tmp/nim_islands"
  discard gorge("mkdir -p " & tmpDir)
  # ...
  let srcFile = tmpDir & "/island_" & $island.id & ".nim"
  let jsFile = tmpDir & "/island_" & $island.id & ".js"
  let cmd = nimBin & " js --opt:size -d:danger -o:" & jsFile & " " & srcFile

  writeFile(srcFile, lightSrc)                        # write at compile time
  let (lightOut, lightExit) = gorgeEx(cmd)             # compile at compile time
  let jsCode = readFile(jsFile)                        # read result at compile time
```

This is how the framework compiles event handlers to JS, verifies `safe` blocks via C compilation, and generates server-side artifacts -- all during macro expansion. `gorge` runs shell commands at compile time and returns stdout. `gorgeEx` returns (stdout, exit code). `writeFile`/`readFile` operate on the filesystem during compilation.

**2. AST walking and rewriting:**

```nim
proc rewriteAst(n: NimNode, usedShims: var seq[string],
                safeBlocks: var seq[SafeBlock]): NimNode =
  # Detect safe() blocks and extract for dual-target compilation
  if n.kind == nnkCall and n[0].kind == nnkIdent and n[0].strVal == "safe":
    var captures: seq[(string, string)]
    var body: NimNode
    for i in 1..<n.len:
      case n[i].kind
      of nnkExprEqExpr: captures.add (n[i][0].strVal, n[i][1].strVal)
      of nnkStmtList: body = n[i]
      else: discard
    safeBlocks.add SafeBlock(captures: captures, bodyRepr: body.repr)
    # For JS: return the body with shim rewrites applied
    return rewriteAst(body[0], usedShims, safeBlocks)

  # Rewrite stdlib calls to lightweight JS shims
  if n.kind == nnkCall and n[0].kind == nnkIdent:
    let idx = findShim(n[0].strVal)
    if idx >= 0:
      let shim = shimDefs[idx]
      if shim.nimName notin usedShims: usedShims.add shim.nimName
      result = newCall(ident(shim.jsName))
      for i in 1..<n.len: result.add rewriteAst(n[i], usedShims, safeBlocks)
      return

  # Default: recurse into children
  result = copyNimNode(n)
  for i in 0..<n.len: result.add rewriteAst(n[i], usedShims, safeBlocks)
```

This is the pattern for detecting `proxyFetch`, `guard()`, `shared()`, `secret()` and other primitives at compile time. The macro walks the AST, matches on node kinds (`nnkCall`, `nnkIdent`, `nnkDotExpr`, etc.), extracts metadata, and rewrites code for the target platform.

**3. Shim table (stdlib → JS native mapping):**

```nim
type ShimDef = object
  nimName, jsName, importjs, params, retType: string

const shimDefs: seq[ShimDef] = @[
  ShimDef(nimName: "parseInt", jsName: "jsParseInt",
          importjs: "parseInt(#)", params: "s: cstring", retType: "int"),
  # ...
]

proc shimDecl(s: ShimDef): string =
  "proc " & s.jsName & "(" & s.params & "): " & s.retType &
  " {.importjs: \"" & s.importjs & "\".}"
```

The `{.importjs.}` pragma maps Nim procs to JS natives. The shim table is an extensible compile-time lookup that the macro uses for tree shaking — only shims actually referenced in the handler body are emitted. This same pattern applies to the framework's generated client code: only the sync primitives, event handlers, and state management code actually used by the app are included.

**4. Safe block → dual-target compilation:**

```nim
proc generateCSrc(sb: SafeBlock): string =
  var paramList: string
  for i, (name, typ) in sb.captures:
    if i > 0: paramList &= ", "
    paramList &= name & ": " & typ
  result = "proc computation(" & paramList & "): auto =\n"
  result &= "  " & sb.bodyRepr & "\n\n"
  result &= "when isMainModule:\n"
  result &= "  import std/[os, strutils]\n"
  # ... CLI harness for testing ...

# In the main macro:
let (compOut, compExit) = gorgeEx(nimBin & " c -d:danger -o:" & binFile & " " & srcFile)
if compExit != 0:
  error("safe block " & $i & " failed C compilation " &
        "(DOM type leaked into pure context?):\n" & compOut)
```

Free variables are hoisted to function parameters. The block is compiled to C. If it references DOM types, browser APIs, or anything non-portable, C compilation fails → compile-time error. This is the mechanism behind the portability check for `webhook` and `cron` handlers.

### What the POC does NOT cover (to be built)

The POC demonstrates the macro mechanics (AST rewriting, dual-target compilation, tree shaking). It does NOT implement:
- The `proxyFetch`/`guard()`/`shared()` primitives (detection and code generation)
- Event log generation, hash chain construction, or sync protocol
- The IndexedDB abstraction layer
- The Cloudflare Worker/DO code generation
- The operation classification algorithm (optimistic/barrier/verified)

These are the build tasks. The POC establishes that Nim's macro system is powerful enough to support them.

## Appendix D: Complete App Example

What a developer (or LLM) writes — a complete OrgShoots app using every primitive. This is the target developer experience. The framework compiles this single source into client JS, a Cloudflare Worker, DO code, D1 migrations, and R2 configuration.

```nim
import unanim

# --- Auth ---
auth(
  providers = ["google"],
  credentials = true,
  jwtSecret = secret("jwt-signing-key")
)

# --- State declarations ---
shared("shoots")
guard("credits")

type
  ShootStatus = enum Active, Deleted
  Shoot = object
    id, name, createdBy: string
    status: ShootStatus
  Photo = object
    id, shootId, url: string
    editedUrl: string  # empty until AI-edited

# --- Migrations (compiler validates all queries against these) ---
migration(1, "initial"):
  sql"""
    CREATE TABLE shoots (id TEXT PRIMARY KEY, name TEXT, created_by TEXT,
                         status TEXT DEFAULT 'Active');
    CREATE TABLE photos (id TEXT PRIMARY KEY, shoot_id TEXT REFERENCES shoots(id),
                         url TEXT, edited_url TEXT DEFAULT '');
  """

# --- Operations on shared state ---
proc createShoot(name: string) =
  let s = Shoot(id: newId(), name: name, createdBy: currentUser(),
                status: Active)
  db.insert("shoots", s)

proc deleteShoot(id: string) =
  db.update("shoots", id, status = Deleted)

proc addPhoto(shootId: string, url: string) =
  let p = Photo(id: newId(), shootId: shootId, url: url)
  db.insert("photos", p)

proc editPhoto(shootId: string, photoId: string, prompt: string) =
  let photo = db.get("photos", photoId)
  let result = proxyFetch("https://api.openai.com/v1/images/edits",
    headers = {"Authorization": "Bearer " & secret("openai-key")},
    body = %*{"image": photo.url, "prompt": prompt}
  )
  db.update("photos", photoId, editedUrl = result["url"].getStr)

# --- Webhook: receive processed images from async pipeline ---
let onImageReady = webhook(proc(data: JsonNode) =
  let photoId = data["photo_id"].getStr
  let resultUrl = data["result_url"].getStr
  db.update("photos", photoId, editedUrl = resultUrl)
)

# --- Cron: refresh pricing data daily ---
cron("0 0 * * *", proc() =
  let pricing = proxyFetch("https://api.openai.com/v1/pricing",
    headers = {"Authorization": "Bearer " & secret("openai-key")}
  )
  db.upsert("config", "pricing", value = pricing)
)

# --- UI (islands-style DSL) ---
page:
  h1: "OrgShoots"

  `div`(id="shoots-list"):
    # Reactive query — compiler validates against migration schema
    for shoot in db.query("SELECT * FROM shoots WHERE status = 'Active'"):
      `div`(class="shoot"):
        h3: shoot.name
        for photo in db.query("SELECT * FROM photos WHERE shoot_id = ?", shoot.id):
          img(src=photo.editedUrl or photo.url)
          button:
            text "AI Edit"
            onClick:
              editPhoto(shoot.id, photo.id, "enhance lighting and color")

    button:
      text "New Shoot"
      onClick:
        createShoot("Untitled Shoot")
```

**What the compiler generates from this:**

| Artifact | Contents |
|---|---|
| `_generated/client/app.js` | Islands JS, IndexedDB abstraction, sync client, reactive queries |
| `_generated/client/index.html` | Static HTML shell + script tags |
| `_generated/cloudflare/worker.js` | Router Worker (JWT validation, routing to DOs) |
| `_generated/cloudflare/user-do.js` | Per-user Durable Object (personal state, lease, offline handlers) |
| `_generated/cloudflare/org-do.js` | Org-level Durable Object (shared state, event sequencing, barrier broadcast) |
| `_generated/migrations/001_initial.sql` | SQLite DDL from `migration(1, ...)` |
| `_generated/cloudflare/wrangler.toml` | DO bindings, D1 binding, R2 binding, cron triggers, secrets |
| `_generated/openapi.yaml` | API spec for proxyFetch endpoints + webhooks |
| `_generated/functions/webhooks/on_image_ready.js` | Standalone webhook handler (portable) |
| `_generated/functions/cron/daily_pricing.js` | Standalone cron handler (portable) |
