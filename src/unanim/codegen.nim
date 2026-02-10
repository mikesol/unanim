## unanim/codegen - Compile-time code generation for Cloudflare Worker artifacts.
##
## Reads metadata from secret registry and proxyFetch classifications,
## generates a standalone Cloudflare Worker JS file and wrangler.toml.
##
## See VISION.md Section 6: Infrastructure Mapping
## See VISION.md Section 7: Migration and Ejection

import std/macros
import std/macrocache
import std/strutils
import ./secret
import ./proxyfetch
import ./cron
import ./after

type
  SecretBinding* = object
    name*: string             ## The secret name (e.g. "openai-key")
    envVar*: string           ## The Worker env var name (e.g. "OPENAI_KEY")

  RouteInfo* = object
    index*: int               ## Route index (for path matching)
    targetUrl*: string        ## Currently empty -- filled at runtime by client
    secrets*: seq[string]     ## Secret names needed for this route

proc sanitizeEnvVar*(name: string): string =
  ## Convert a secret name like "openai-key" to an env var like "OPENAI_KEY"
  result = name.toUpperAscii().replace("-", "_").replace(".", "_")

proc generateWorkerJs*(secrets: seq[string], routes: seq[RouteInfo],
                       hasDO: bool = false,
                       cronSchedules: seq[string] = @[]): string =
  ## Generate a standalone Cloudflare Worker JS file (ES modules format).
  ## The Worker:
  ## - Accepts POST requests with JSON body containing target URL and headers
  ## - Reads secrets from env, replaces <<SECRET:name>> placeholders
  ## - Forwards the request to the target URL
  ## - Returns the response
  ## When hasDO is true, also routes /do/* requests to Durable Objects.
  ##
  ## SCAFFOLD(phase1, #4): This is a simplified v1 stateless router.
  ## Phase 2 adds DOs, Phase 3 adds sync, Phase 4 adds auth/webhooks/cron.

  # CORS configuration varies based on DO support
  let corsMethods = if hasDO: "GET, POST, OPTIONS" else: "POST, OPTIONS"
  let corsHeaders = if hasDO: "Content-Type, X-User-Id" else: "Content-Type"

  # Section 1: Header and fetch handler opening
  result = "// Unanim Generated Cloudflare Worker\n"
  result &= "// SCAFFOLD(phase1, #4): Stateless router with credential injection.\n"
  result &= "// This Worker is standalone — copy to a fresh Cloudflare project and it works.\n"
  result &= "\n"
  result &= "export default {\n"
  result &= "  async fetch(request, env, ctx) {\n"

  # Section 2: CORS preflight handler
  result &= "    // Handle CORS preflight\n"
  result &= "    if (request.method === \"OPTIONS\") {\n"
  result &= "      return new Response(null, {\n"
  result &= "        status: 204,\n"
  result &= "        headers: {\n"
  result &= "          \"Access-Control-Allow-Origin\": \"*\",\n"
  result &= "          \"Access-Control-Allow-Methods\": \"" & corsMethods & "\",\n"
  result &= "          \"Access-Control-Allow-Headers\": \"" & corsHeaders & "\",\n"
  result &= "        },\n"
  result &= "      });\n"
  result &= "    }\n"

  # Section 3: DO routing (only when hasDO is true)
  if hasDO:
    result &= "\n"
    result &= "    // Route /do/* requests to Durable Objects\n"
    result &= "    const reqUrl = new URL(request.url);\n"
    result &= "    if (reqUrl.pathname.startsWith(\"/do/\")) {\n"
    result &= "      const userId = request.headers.get(\"X-User-Id\") || reqUrl.searchParams.get(\"user_id\");\n"
    result &= "      if (!userId) {\n"
    result &= "        return new Response(JSON.stringify({ error: \"Missing user ID. Provide X-User-Id header or user_id query param.\" }), {\n"
    result &= "          status: 400,\n"
    result &= "          headers: { \"Content-Type\": \"application/json\", \"Access-Control-Allow-Origin\": \"*\" },\n"
    result &= "        });\n"
    result &= "      }\n"
    result &= "      const doId = env.USER_DO.idFromName(userId);\n"
    result &= "      const doStub = env.USER_DO.get(doId);\n"
    result &= "      const doPath = reqUrl.pathname.replace(/^\\/do/, \"\");\n"
    result &= "      const doUrl = new URL(doPath + reqUrl.search, request.url);\n"
    result &= "      return doStub.fetch(new Request(doUrl, request));\n"
    result &= "    }\n"

  # Section 4: POST-only check and proxy logic
  result &= "\n"
  result &= "    // Only accept POST requests\n"
  result &= "    if (request.method !== \"POST\") {\n"
  result &= "      return new Response(JSON.stringify({ error: \"Method not allowed. Use POST.\" }), {\n"
  result &= "        status: 405,\n"
  result &= "        headers: { \"Content-Type\": \"application/json\", \"Access-Control-Allow-Origin\": \"*\" },\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    let body;\n"
  result &= "    try {\n"
  result &= "      body = await request.json();\n"
  result &= "    } catch (e) {\n"
  result &= "      return new Response(JSON.stringify({ error: \"Invalid JSON body.\" }), {\n"
  result &= "        status: 400,\n"
  result &= "        headers: { \"Content-Type\": \"application/json\", \"Access-Control-Allow-Origin\": \"*\" },\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    const { url, headers, method, requestBody } = body;\n"
  result &= "\n"
  result &= "    if (!url) {\n"
  result &= "      return new Response(JSON.stringify({ error: \"Missing 'url' in request body.\" }), {\n"
  result &= "        status: 400,\n"
  result &= "        headers: { \"Content-Type\": \"application/json\", \"Access-Control-Allow-Origin\": \"*\" },\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "\n"

  # Section 5: Secret injection function
  result &= "    // Inject secrets: replace <<SECRET:name>> placeholders with env values\n"
  result &= "    function injectSecrets(value) {\n"
  result &= "      if (typeof value !== \"string\") return value;\n"
  result &= "      return value.replace(/<<SECRET:([^>]+)>>/g, (match, secretName) => {\n"
  result &= "        const envKey = secretName.toUpperCase().replace(/-/g, \"_\").replace(/\\./g, \"_\");\n"
  result &= "        const secretValue = env[envKey];\n"
  result &= "        if (secretValue === undefined) {\n"
  result &= "          throw new Error(`Secret \"${secretName}\" (env: ${envKey}) is not configured.`);\n"
  result &= "        }\n"
  result &= "        return secretValue;\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "\n"

  # Section 6: Secret resolution into headers, URL, body
  result &= "    // Inject secrets into headers\n"
  result &= "    const resolvedHeaders = {};\n"
  result &= "    if (headers && typeof headers === \"object\") {\n"
  result &= "      for (const [key, value] of Object.entries(headers)) {\n"
  result &= "        resolvedHeaders[key] = injectSecrets(value);\n"
  result &= "      }\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    // Inject secrets into URL (in case secret is embedded in URL)\n"
  result &= "    const resolvedUrl = injectSecrets(url);\n"
  result &= "\n"
  result &= "    // Inject secrets into request body if it's a string\n"
  result &= "    let resolvedBody = requestBody;\n"
  result &= "    if (typeof resolvedBody === \"string\") {\n"
  result &= "      resolvedBody = injectSecrets(resolvedBody);\n"
  result &= "    } else if (resolvedBody !== undefined && resolvedBody !== null) {\n"
  result &= "      resolvedBody = JSON.stringify(resolvedBody);\n"
  result &= "    }\n"
  result &= "\n"

  # Section 7: Forward request and return response
  result &= "    // Forward the request\n"
  result &= "    try {\n"
  result &= "      const response = await fetch(resolvedUrl, {\n"
  result &= "        method: method || \"POST\",\n"
  result &= "        headers: resolvedHeaders,\n"
  result &= "        body: resolvedBody,\n"
  result &= "      });\n"
  result &= "\n"
  result &= "      const responseBody = await response.text();\n"
  result &= "\n"
  result &= "      return new Response(responseBody, {\n"
  result &= "        status: response.status,\n"
  result &= "        headers: {\n"
  result &= "          \"Content-Type\": response.headers.get(\"Content-Type\") || \"application/octet-stream\",\n"
  result &= "          \"Access-Control-Allow-Origin\": \"*\",\n"
  result &= "        },\n"
  result &= "      });\n"
  result &= "    } catch (e) {\n"
  result &= "      return new Response(JSON.stringify({ error: \"Upstream request failed: \" + e.message }), {\n"
  result &= "        status: 502,\n"
  result &= "        headers: { \"Content-Type\": \"application/json\", \"Access-Control-Allow-Origin\": \"*\" },\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "  },\n"

  # Section 8: Scheduled handler for cron triggers (only when crons registered)
  if cronSchedules.len > 0:
    result &= "  async scheduled(event, env, ctx) {\n"
    result &= "    // Route cron trigger to DO for execution\n"
    result &= "    const doId = env.USER_DO.idFromName(\"__cron__\");\n"
    result &= "    const doStub = env.USER_DO.get(doId);\n"
    result &= "    await doStub.fetch(new Request(\"https://internal/cron\", {\n"
    result &= "      method: \"POST\",\n"
    result &= "      body: JSON.stringify({ trigger: event.cron, scheduledTime: event.scheduledTime }),\n"
    result &= "    }));\n"
    result &= "  },\n"

  result &= "};\n"

proc generateDurableObjectJs*(hasCron: bool = false, hasAfter: bool = false): string =
  ## Generate a Durable Object ES module class with SQLite event storage.
  ## The DO:
  ## - Creates an events table in SQLite on initialization
  ## - Stores events via POST /events
  ## - Retrieves events via GET /events?since=N
  ## - Reports status via GET /status
  ## - Verifies sequence continuity at /proxy boundary
  ## - Handles CORS preflight
  ## - When hasCron: handles /cron route for scheduled execution
  ## - When hasAfter: handles DO Alarms for delayed execution
  ##
  ## See VISION.md Section 4.2 (The Event Log)

  # Section 1: Header and constructor
  result = "// Unanim Generated Durable Object\n"
  result &= "// Event storage backed by SQLite via Cloudflare Durable Objects.\n"
  result &= "// This class is standalone — copy to a fresh Cloudflare project and it works.\n"
  result &= "\n"
  result &= "export class UserDO {\n"
  result &= "  constructor(state, env) {\n"
  result &= "    this.state = state;\n"
  result &= "    this.env = env;\n"
  result &= "    this.sql = state.storage.sql;\n"
  result &= "    this.state.blockConcurrencyWhile(async () => {\n"
  result &= "      await this.initialize();\n"
  result &= "    });\n"
  result &= "  }\n"
  result &= "\n"

  # Section 2: Initialize
  result &= "  async initialize() {\n"
  result &= "    this.sql.exec(`CREATE TABLE IF NOT EXISTS events (\n"
  result &= "      sequence INTEGER PRIMARY KEY,\n"
  result &= "      timestamp TEXT NOT NULL,\n"
  result &= "      event_type TEXT NOT NULL,\n"
  result &= "      schema_version INTEGER NOT NULL,\n"
  result &= "      payload TEXT NOT NULL\n"
  result &= "    )`);\n"
  result &= "  }\n"
  result &= "\n"

  # Section 3: fetch handler with routing
  result &= "  async fetch(request) {\n"
  result &= "    const url = new URL(request.url);\n"
  result &= "    const path = url.pathname;\n"
  result &= "\n"
  result &= "    // Handle CORS preflight\n"
  result &= "    if (request.method === \"OPTIONS\") {\n"
  result &= "      return new Response(null, {\n"
  result &= "        status: 204,\n"
  result &= "        headers: {\n"
  result &= "          \"Access-Control-Allow-Origin\": \"*\",\n"
  result &= "          \"Access-Control-Allow-Methods\": \"GET, POST, OPTIONS\",\n"
  result &= "          \"Access-Control-Allow-Headers\": \"Content-Type\",\n"
  result &= "        },\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    const corsHeaders = {\n"
  result &= "      \"Content-Type\": \"application/json\",\n"
  result &= "      \"Access-Control-Allow-Origin\": \"*\",\n"
  result &= "    };\n"
  result &= "\n"
  result &= "    try {\n"
  result &= "      if (path === \"/events\" && request.method === \"POST\") {\n"
  result &= "        return await this.storeEvents(request, corsHeaders);\n"
  result &= "      } else if (path === \"/events\" && request.method === \"GET\") {\n"
  result &= "        const since = parseInt(url.searchParams.get(\"since\") || \"0\", 10);\n"
  result &= "        return await this.getEvents(since, corsHeaders);\n"
  result &= "      } else if (path === \"/status\" && request.method === \"GET\") {\n"
  result &= "        return await this.getStatus(corsHeaders);\n"
  result &= "      } else if (path === \"/proxy\" && request.method === \"POST\") {\n"
  result &= "        return await this.handleProxy(request, corsHeaders);\n"
  result &= "      } else if (path === \"/sync\" && request.method === \"POST\") {\n"
  result &= "        return await this.handleSync(request, corsHeaders);\n"

  # Conditional cron route
  if hasCron:
    result &= "      } else if (path === \"/cron\" && request.method === \"POST\") {\n"
    result &= "        return await this.handleCron(request, corsHeaders);\n"

  # Conditional schedule-alarm route
  if hasAfter:
    result &= "      } else if (path === \"/schedule-alarm\" && request.method === \"POST\") {\n"
    result &= "        return await this.handleScheduleAlarm(request, corsHeaders);\n"

  result &= "      } else {\n"
  result &= "        return new Response(JSON.stringify({ error: \"Not found\" }), {\n"
  result &= "          status: 404,\n"
  result &= "          headers: corsHeaders,\n"
  result &= "        });\n"
  result &= "      }\n"
  result &= "    } catch (e) {\n"
  result &= "      return new Response(JSON.stringify({ error: e.message }), {\n"
  result &= "        status: 500,\n"
  result &= "        headers: corsHeaders,\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "  }\n"
  result &= "\n"

  # Section 4: storeEvents
  result &= "  async storeEvents(request, corsHeaders) {\n"
  result &= "    const body = await request.json();\n"
  result &= "    const events = Array.isArray(body) ? body : [body];\n"
  result &= "\n"
  result &= "    for (const event of events) {\n"
  result &= "      this.sql.exec(\n"
  result &= "        `INSERT INTO events (sequence, timestamp, event_type, schema_version, payload) VALUES (?, ?, ?, ?, ?)`,\n"
  result &= "        event.sequence,\n"
  result &= "        event.timestamp,\n"
  result &= "        event.event_type,\n"
  result &= "        event.schema_version,\n"
  result &= "        event.payload\n"
  result &= "      );\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    return new Response(JSON.stringify({ stored: events.length }), {\n"
  result &= "      status: 200,\n"
  result &= "      headers: corsHeaders,\n"
  result &= "    });\n"
  result &= "  }\n"
  result &= "\n"

  # Section 5: getEvents
  result &= "  async getEvents(since, corsHeaders) {\n"
  result &= "    const rows = this.sql.exec(\n"
  result &= "      `SELECT sequence, timestamp, event_type, schema_version, payload FROM events WHERE sequence > ? ORDER BY sequence ASC`,\n"
  result &= "      since\n"
  result &= "    ).toArray();\n"
  result &= "\n"
  result &= "    return new Response(JSON.stringify(rows), {\n"
  result &= "      status: 200,\n"
  result &= "      headers: corsHeaders,\n"
  result &= "    });\n"
  result &= "  }\n"
  result &= "\n"

  # Section 6: getStatus
  result &= "  async getStatus(corsHeaders) {\n"
  result &= "    const countResult = this.sql.exec(`SELECT COUNT(*) as count FROM events`).one();\n"
  result &= "    const latestResult = this.sql.exec(`SELECT MAX(sequence) as latest FROM events`).one();\n"
  result &= "\n"
  result &= "    return new Response(JSON.stringify({\n"
  result &= "      event_count: countResult.count,\n"
  result &= "      latest_sequence: latestResult.latest || 0,\n"
  result &= "    }), {\n"
  result &= "      status: 200,\n"
  result &= "      headers: corsHeaders,\n"
  result &= "    });\n"
  result &= "  }\n"
  result &= "\n"

  # Section 7: getServerEventsSince
  result &= "  getServerEventsSince(eventsSince, clientSequences) {\n"
  result &= "    const rows = this.sql.exec(\n"
  result &= "      `SELECT sequence, timestamp, event_type, schema_version, payload FROM events WHERE sequence > ? ORDER BY sequence ASC`,\n"
  result &= "      eventsSince\n"
  result &= "    ).toArray();\n"
  result &= "    return rows.filter(row => !clientSequences.has(row.sequence));\n"
  result &= "  }\n"
  result &= "\n"

  # Section 8: injectSecrets
  result &= "  injectSecrets(value) {\n"
  result &= "    if (typeof value !== \"string\") return value;\n"
  result &= "    return value.replace(/<<SECRET:([^>]+)>>/g, (match, secretName) => {\n"
  result &= "      const envKey = secretName.toUpperCase().replace(/-/g, \"_\").replace(/\\./g, \"_\");\n"
  result &= "      const secretValue = this.env[envKey];\n"
  result &= "      if (secretValue === undefined) {\n"
  result &= "        throw new Error(`Secret \"${secretName}\" (env: ${envKey}) is not configured.`);\n"
  result &= "      }\n"
  result &= "      return secretValue;\n"
  result &= "    });\n"
  result &= "  }\n"
  result &= "\n"

  # Section 9: verifyAndStoreEvents
  result &= "  async verifyAndStoreEvents(events_since, events, corsHeaders) {\n"
  result &= "    // Determine expected next sequence from stored events\n"
  result &= "    let expectedNextSeq = 1;\n"
  result &= "    if (events_since && events_since > 0) {\n"
  result &= "      expectedNextSeq = events_since + 1;\n"
  result &= "    } else {\n"
  result &= "      const lastRow = this.sql.exec(\n"
  result &= "        `SELECT MAX(sequence) as latest FROM events`\n"
  result &= "      ).one();\n"
  result &= "      if (lastRow.latest) {\n"
  result &= "        expectedNextSeq = lastRow.latest + 1;\n"
  result &= "      }\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    // Verify and store incoming events (sequence continuity check)\n"
  result &= "    if (events && events.length > 0) {\n"
  result &= "      if (events[0].sequence !== expectedNextSeq) {\n"
  result &= "        const sinceSeq = events_since || 0;\n"
  result &= "        const serverEvents = this.getServerEventsSince(sinceSeq, new Set());\n"
  result &= "\n"
  result &= "        return { error: new Response(JSON.stringify({\n"
  result &= "          events_accepted: false,\n"
  result &= "          error: `Sequence gap: expected ${expectedNextSeq}, got ${events[0].sequence}`,\n"
  result &= "          server_events: serverEvents,\n"
  result &= "          response: null,\n"
  result &= "        }), {\n"
  result &= "          status: 409,\n"
  result &= "          headers: corsHeaders,\n"
  result &= "        }) };\n"
  result &= "      }\n"
  result &= "\n"
  result &= "      // Verify internal sequence continuity\n"
  result &= "      for (let i = 1; i < events.length; i++) {\n"
  result &= "        if (events[i].sequence !== events[i - 1].sequence + 1) {\n"
  result &= "          const sinceSeq = events_since || 0;\n"
  result &= "          const serverEvents = this.getServerEventsSince(sinceSeq, new Set());\n"
  result &= "\n"
  result &= "          return { error: new Response(JSON.stringify({\n"
  result &= "            events_accepted: false,\n"
  result &= "            error: `Sequence gap at event ${i}: expected ${events[i - 1].sequence + 1}, got ${events[i].sequence}`,\n"
  result &= "            server_events: serverEvents,\n"
  result &= "            response: null,\n"
  result &= "          }), {\n"
  result &= "            status: 409,\n"
  result &= "            headers: corsHeaders,\n"
  result &= "          }) };\n"
  result &= "        }\n"
  result &= "      }\n"
  result &= "\n"
  result &= "      // Store verified events\n"
  result &= "      for (const event of events) {\n"
  result &= "        this.sql.exec(\n"
  result &= "          `INSERT INTO events (sequence, timestamp, event_type, schema_version, payload) VALUES (?, ?, ?, ?, ?)`,\n"
  result &= "          event.sequence,\n"
  result &= "          event.timestamp,\n"
  result &= "          event.event_type,\n"
  result &= "          event.schema_version,\n"
  result &= "          event.payload\n"
  result &= "        );\n"
  result &= "      }\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    // Collect client event sequences for filtering\n"
  result &= "    const clientSequences = new Set();\n"
  result &= "    if (events && events.length > 0) {\n"
  result &= "      for (const event of events) {\n"
  result &= "        clientSequences.add(event.sequence);\n"
  result &= "      }\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    // Get events the client hasn't seen\n"
  result &= "    const sinceSeq = events_since || 0;\n"
  result &= "    const serverEvents = this.getServerEventsSince(sinceSeq, clientSequences);\n"
  result &= "\n"
  result &= "    return { serverEvents };\n"
  result &= "  }\n"
  result &= "\n"

  # Section 10: handleProxy
  result &= "  async handleProxy(request, corsHeaders) {\n"
  result &= "    const body = await request.json();\n"
  result &= "    const { events_since, events, request: apiRequest } = body;\n"
  result &= "\n"
  result &= "    if (!apiRequest || !apiRequest.url) {\n"
  result &= "      return new Response(JSON.stringify({ error: \"Missing 'request.url' in proxy body.\" }), {\n"
  result &= "        status: 400,\n"
  result &= "        headers: corsHeaders,\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    const result = await this.verifyAndStoreEvents(events_since, events, corsHeaders);\n"
  result &= "    if (result.error) return result.error;\n"
  result &= "    const serverEvents = result.serverEvents;\n"
  result &= "\n"
  result &= "    // Inject secrets into the API request\n"
  result &= "    let resolvedUrl = this.injectSecrets(apiRequest.url);\n"
  result &= "    const resolvedHeaders = {};\n"
  result &= "    if (apiRequest.headers && typeof apiRequest.headers === \"object\") {\n"
  result &= "      for (const [key, value] of Object.entries(apiRequest.headers)) {\n"
  result &= "        resolvedHeaders[key] = this.injectSecrets(value);\n"
  result &= "      }\n"
  result &= "    }\n"
  result &= "    let resolvedBody = apiRequest.body;\n"
  result &= "    if (typeof resolvedBody === \"string\") {\n"
  result &= "      resolvedBody = this.injectSecrets(resolvedBody);\n"
  result &= "    } else if (resolvedBody !== undefined && resolvedBody !== null) {\n"
  result &= "      resolvedBody = JSON.stringify(resolvedBody);\n"
  result &= "    }\n"
  result &= "\n"
  result &= "    // Forward API call\n"
  result &= "    try {\n"
  result &= "      const apiResponse = await fetch(resolvedUrl, {\n"
  result &= "        method: apiRequest.method || \"POST\",\n"
  result &= "        headers: resolvedHeaders,\n"
  result &= "        body: resolvedBody,\n"
  result &= "      });\n"
  result &= "\n"
  result &= "      const responseBody = await apiResponse.text();\n"
  result &= "      const responseHeaders = {};\n"
  result &= "      apiResponse.headers.forEach((value, key) => {\n"
  result &= "        responseHeaders[key] = value;\n"
  result &= "      });\n"
  result &= "\n"
  result &= "      return new Response(JSON.stringify({\n"
  result &= "        events_accepted: true,\n"
  result &= "        server_events: serverEvents,\n"
  result &= "        response: {\n"
  result &= "          status: apiResponse.status,\n"
  result &= "          headers: responseHeaders,\n"
  result &= "          body: responseBody,\n"
  result &= "        },\n"
  result &= "      }), {\n"
  result &= "        status: 200,\n"
  result &= "        headers: corsHeaders,\n"
  result &= "      });\n"
  result &= "    } catch (e) {\n"
  result &= "      return new Response(JSON.stringify({\n"
  result &= "        events_accepted: true,\n"
  result &= "        server_events: serverEvents,\n"
  result &= "        response: null,\n"
  result &= "        error: \"Upstream request failed: \" + e.message,\n"
  result &= "      }), {\n"
  result &= "        status: 502,\n"
  result &= "        headers: corsHeaders,\n"
  result &= "      });\n"
  result &= "    }\n"
  result &= "  }\n"
  result &= "\n"

  # Section 11: handleSync
  result &= "  async handleSync(request, corsHeaders) {\n"
  result &= "    const body = await request.json();\n"
  result &= "    const { events_since, events } = body;\n"
  result &= "\n"
  result &= "    const result = await this.verifyAndStoreEvents(events_since, events, corsHeaders);\n"
  result &= "    if (result.error) return result.error;\n"
  result &= "\n"
  result &= "    return new Response(JSON.stringify({\n"
  result &= "      events_accepted: true,\n"
  result &= "      server_events: result.serverEvents,\n"
  result &= "      response: null,\n"
  result &= "    }), {\n"
  result &= "      status: 200,\n"
  result &= "      headers: corsHeaders,\n"
  result &= "    });\n"
  result &= "  }\n"

  # Section 12: handleCron (conditional)
  if hasCron:
    result &= "\n"
    result &= "  async handleCron(request, corsHeaders) {\n"
    result &= "    const body = await request.json();\n"
    result &= "    const { trigger, scheduledTime } = body;\n"
    result &= "\n"
    result &= "    // Store a cron_result event\n"
    result &= "    const lastRow = this.sql.exec(\"SELECT MAX(sequence) as latest FROM events\").one();\n"
    result &= "    const nextSeq = (lastRow.latest || 0) + 1;\n"
    result &= "    const event = {\n"
    result &= "      sequence: nextSeq,\n"
    result &= "      timestamp: new Date().toISOString(),\n"
    result &= "      event_type: \"cron_result\",\n"
    result &= "      schema_version: 1,\n"
    result &= "      payload: JSON.stringify({ trigger, scheduledTime }),\n"
    result &= "    };\n"
    result &= "    this.sql.exec(\n"
    result &= "      \"INSERT INTO events (sequence, timestamp, event_type, schema_version, payload) VALUES (?, ?, ?, ?, ?)\",\n"
    result &= "      event.sequence, event.timestamp, event.event_type, event.schema_version, event.payload\n"
    result &= "    );\n"
    result &= "\n"
    result &= "    return new Response(JSON.stringify({ ok: true, sequence: nextSeq }), {\n"
    result &= "      status: 200,\n"
    result &= "      headers: corsHeaders,\n"
    result &= "    });\n"
    result &= "  }\n"

  # Section 13: alarm + scheduleAlarm + handleScheduleAlarm (conditional)
  if hasAfter:
    result &= "\n"
    result &= "  async alarm() {\n"
    result &= "    // DO Alarm fired — execute scheduled handler\n"
    result &= "    // Get alarm metadata from storage\n"
    result &= "    const alarmMeta = await this.state.storage.get(\"__alarm_meta__\");\n"
    result &= "    if (alarmMeta) {\n"
    result &= "      // Store a scheduled event\n"
    result &= "      const lastRow = this.sql.exec(\"SELECT MAX(sequence) as latest FROM events\").one();\n"
    result &= "      const nextSeq = (lastRow.latest || 0) + 1;\n"
    result &= "      const event = {\n"
    result &= "        sequence: nextSeq,\n"
    result &= "        timestamp: new Date().toISOString(),\n"
    result &= "        event_type: \"proxy_minted\",\n"
    result &= "        schema_version: 1,\n"
    result &= "        payload: JSON.stringify({ type: \"alarm_fired\", meta: alarmMeta }),\n"
    result &= "      };\n"
    result &= "      this.sql.exec(\n"
    result &= "        \"INSERT INTO events (sequence, timestamp, event_type, schema_version, payload) VALUES (?, ?, ?, ?, ?)\",\n"
    result &= "        event.sequence, event.timestamp, event.event_type, event.schema_version, event.payload\n"
    result &= "      );\n"
    result &= "      await this.state.storage.delete(\"__alarm_meta__\");\n"
    result &= "    }\n"
    result &= "  }\n"
    result &= "\n"
    result &= "  async scheduleAlarm(delayMs, meta) {\n"
    result &= "    await this.state.storage.put(\"__alarm_meta__\", meta);\n"
    result &= "    await this.state.storage.setAlarm(Date.now() + delayMs);\n"
    result &= "  }\n"
    result &= "\n"
    result &= "  async handleScheduleAlarm(request, corsHeaders) {\n"
    result &= "    const body = await request.json();\n"
    result &= "    const { delayMs, meta } = body;\n"
    result &= "\n"
    result &= "    if (!delayMs || delayMs <= 0) {\n"
    result &= "      return new Response(JSON.stringify({ error: \"Missing or invalid 'delayMs' in request body.\" }), {\n"
    result &= "        status: 400,\n"
    result &= "        headers: corsHeaders,\n"
    result &= "      });\n"
    result &= "    }\n"
    result &= "\n"
    result &= "    await this.scheduleAlarm(delayMs, meta || {});\n"
    result &= "\n"
    result &= "    return new Response(JSON.stringify({ ok: true, alarm_scheduled: true, delayMs }), {\n"
    result &= "      status: 200,\n"
    result &= "      headers: corsHeaders,\n"
    result &= "    });\n"
    result &= "  }\n"

  # Close the class
  result &= "}\n"

proc generateWranglerToml*(appName: string, secrets: seq[string],
                           hasDO: bool = false,
                           cronSchedules: seq[string] = @[]): string =
  ## Generate a wrangler.toml configuration file for the Cloudflare Worker.
  ## When hasDO is true, includes Durable Object bindings and migrations.
  ##
  ## SCAFFOLD(phase1, #4): Minimal config for stateless Worker.
  ## Phase 2 adds DO bindings, D1 bindings, R2 bindings.
  ## Phase 4 adds cron triggers.

  result = "# Unanim Generated Wrangler Configuration\n"
  result &= "# SCAFFOLD(phase1, #4): Stateless Worker config.\n"
  result &= "# This config is standalone — use with any Cloudflare Workers project.\n\n"
  result &= "name = \"" & appName & "\"\n"
  result &= "main = \"worker.js\"\n"
  result &= "compatibility_date = \"2024-01-01\"\n"
  result &= "compatibility_flags = [\"nodejs_compat\"]\n"

  if secrets.len > 0:
    result &= "\n# Secret bindings — set actual values with: wrangler secret put <NAME>\n"
    result &= "# The following secrets are referenced in the application:\n"
    for s in secrets:
      let envVar = sanitizeEnvVar(s)
      result &= "#   " & envVar & "  (from secret(\"" & s & "\"))\n"
    result &= "\n# To configure all secrets:\n"
    for s in secrets:
      let envVar = sanitizeEnvVar(s)
      result &= "#   wrangler secret put " & envVar & "\n"

  result &= "\n[vars]\n"
  result &= "# Non-secret environment variables can be added here\n"

  if secrets.len > 0:
    result &= "\n# [IMPORTANT] Secrets must be set via `wrangler secret put`, not in this file.\n"
    result &= "# The Worker reads them from env." & sanitizeEnvVar(secrets[0]) & " etc.\n"

  if hasDO:
    result &= "\n[durable_objects]\n"
    result &= "bindings = [{ name = \"USER_DO\", class_name = \"UserDO\" }]\n"
    result &= "\n[[migrations]]\n"
    result &= "tag = \"v1\"\n"
    result &= "new_sqlite_classes = [\"UserDO\"]\n"

  if cronSchedules.len > 0:
    result &= "\n[triggers]\n"
    result &= "crons = ["
    for i, sched in cronSchedules:
      if i > 0:
        result &= ", "
      result &= "\"" & sched & "\""
    result &= "]\n"

proc generateArtifacts*(appName: string, outputDir: string) {.compileTime.} =
  ## Generate all Cloudflare Worker artifacts at compile time.
  ## Reads from the secret registry and proxyFetch classification cache.
  ## Writes worker.js and wrangler.toml to outputDir.
  ##
  ## SCAFFOLD(phase1, #4): Only generates stateless Worker + wrangler.toml.
  ## Phase 2 adds DO generation, Phase 3 adds sync, Phase 4 adds auth/webhooks.

  # Collect unique secrets from both the secret registry and proxyFetch classifications
  var secrets: seq[string] = @[]
  for s in secretRegistry:
    if s notin secrets:
      secrets.add(s)

  # Collect route info from proxyFetch classifications
  var routes: seq[RouteInfo] = @[]
  var routeIndex = 0
  for item in pfClassifications:
    let classOrd = item[0].intVal
    if classOrd == ord(ProxyRequired):
      var secretNames: seq[string] = @[]
      let secretsArr = item[1]
      for j in 0..<secretsArr.len:
        let sName = secretsArr[j].strVal
        secretNames.add(sName)
        # Also add to secrets list if not already there
        if sName notin secrets:
          secrets.add(sName)
      routes.add(RouteInfo(
        index: routeIndex,
        secrets: secretNames
      ))
      inc routeIndex

  # Collect cron schedules from the cron registry
  var cronSchedules: seq[string] = @[]
  for item in cronRegistry:
    cronSchedules.add(item[0].strVal)

  # Check if after() handlers have been registered
  let hasAfterHandlers = afterRegistry.len > 0
  let hasCronHandlers = cronSchedules.len > 0

  # Generate the JS and TOML — always include DO for Phase 1+
  let workerJs = generateWorkerJs(secrets, routes, hasDO = true,
                                   cronSchedules = cronSchedules)
  let durableObjectJs = generateDurableObjectJs(hasCron = hasCronHandlers,
                                                 hasAfter = hasAfterHandlers)
  let combinedJs = workerJs & "\n" & durableObjectJs
  let wranglerToml = generateWranglerToml(appName, secrets, hasDO = true,
                                           cronSchedules = cronSchedules)

  # Create output directory and write files
  discard gorge("mkdir -p " & outputDir)
  writeFile(outputDir & "/worker.js", combinedJs)
  writeFile(outputDir & "/wrangler.toml", wranglerToml)
