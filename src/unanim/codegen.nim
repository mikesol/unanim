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
                       hasDO: bool = false): string =
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
  result &= "};\n"

proc generateDurableObjectJs*(): string =
  ## Generate a Durable Object ES module class with SQLite event storage.
  ## The DO:
  ## - Creates an events table in SQLite on initialization
  ## - Stores events via POST /events
  ## - Retrieves events via GET /events?since=N
  ## - Reports status via GET /status
  ## - Handles CORS preflight
  ##
  ## See VISION.md Section 4.2 (The Event Log)
  result = """// Unanim Generated Durable Object
// Event storage backed by SQLite via Cloudflare Durable Objects.
// This class is standalone — copy to a fresh Cloudflare project and it works.

export class UserDO {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.sql = state.storage.sql;
    this.state.blockConcurrencyWhile(async () => {
      await this.initialize();
    });
  }

  async initialize() {
    this.sql.exec(`CREATE TABLE IF NOT EXISTS events (
      sequence INTEGER PRIMARY KEY,
      timestamp TEXT NOT NULL,
      event_type TEXT NOT NULL,
      schema_version INTEGER NOT NULL,
      payload TEXT NOT NULL,
      state_hash_after TEXT NOT NULL,
      parent_hash TEXT NOT NULL
    )`);
  }

  async sha256Hex(input) {
    const encoder = new TextEncoder();
    const data = encoder.encode(input);
    const hashBuffer = await crypto.subtle.digest("SHA-256", data);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, "0")).join("");
  }

  canonicalForm(event) {
    return [
      event.sequence.toString(),
      event.timestamp,
      event.event_type,
      event.schema_version.toString(),
      event.payload,
      event.state_hash_after,
      event.parent_hash,
    ].join("|");
  }

  async hashEvent(event) {
    const canonical = this.canonicalForm(event);
    return await this.sha256Hex(canonical);
  }

  async computeStateHash(event) {
    const forHashing = { ...event, state_hash_after: "" };
    return await this.hashEvent(forHashing);
  }

  async verifyChain(events, anchorHash) {
    let expectedParentHash = anchorHash;

    for (let i = 0; i < events.length; i++) {
      const event = events[i];

      if (event.parent_hash !== expectedParentHash) {
        return {
          valid: false,
          failedAt: i,
          error: `Event ${event.sequence}: parent_hash mismatch. Expected ${expectedParentHash.slice(0, 16)}..., got ${event.parent_hash.slice(0, 16)}...`,
        };
      }

      const computedStateHash = await this.computeStateHash(event);
      if (event.state_hash_after !== computedStateHash) {
        return {
          valid: false,
          failedAt: i,
          error: `Event ${event.sequence}: state_hash_after mismatch. Expected ${computedStateHash.slice(0, 16)}..., got ${event.state_hash_after.slice(0, 16)}...`,
        };
      }

      expectedParentHash = await this.hashEvent(event);
    }

    return { valid: true };
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;

    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    const corsHeaders = {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    };

    try {
      if (path === "/events" && request.method === "POST") {
        return await this.storeEvents(request, corsHeaders);
      } else if (path === "/events" && request.method === "GET") {
        const since = parseInt(url.searchParams.get("since") || "0", 10);
        return await this.getEvents(since, corsHeaders);
      } else if (path === "/status" && request.method === "GET") {
        return await this.getStatus(corsHeaders);
      } else if (path === "/proxy" && request.method === "POST") {
        return await this.handleProxy(request, corsHeaders);
      } else {
        return new Response(JSON.stringify({ error: "Not found" }), {
          status: 404,
          headers: corsHeaders,
        });
      }
    } catch (e) {
      return new Response(JSON.stringify({ error: e.message }), {
        status: 500,
        headers: corsHeaders,
      });
    }
  }

  async storeEvents(request, corsHeaders) {
    const body = await request.json();
    const events = Array.isArray(body) ? body : [body];

    for (const event of events) {
      this.sql.exec(
        `INSERT INTO events (sequence, timestamp, event_type, schema_version, payload, state_hash_after, parent_hash) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        event.sequence,
        event.timestamp,
        event.event_type,
        event.schema_version,
        event.payload,
        event.state_hash_after,
        event.parent_hash
      );
    }

    return new Response(JSON.stringify({ stored: events.length }), {
      status: 200,
      headers: corsHeaders,
    });
  }

  async getEvents(since, corsHeaders) {
    const rows = this.sql.exec(
      `SELECT sequence, timestamp, event_type, schema_version, payload, state_hash_after, parent_hash FROM events WHERE sequence > ? ORDER BY sequence ASC`,
      since
    ).toArray();

    return new Response(JSON.stringify(rows), {
      status: 200,
      headers: corsHeaders,
    });
  }

  async getStatus(corsHeaders) {
    const countResult = this.sql.exec(`SELECT COUNT(*) as count FROM events`).one();
    const latestResult = this.sql.exec(`SELECT MAX(sequence) as latest FROM events`).one();

    return new Response(JSON.stringify({
      event_count: countResult.count,
      latest_sequence: latestResult.latest || 0,
    }), {
      status: 200,
      headers: corsHeaders,
    });
  }

  injectSecrets(value) {
    if (typeof value !== "string") return value;
    return value.replace(/<<SECRET:([^>]+)>>/g, (match, secretName) => {
      const envKey = secretName.toUpperCase().replace(/-/g, "_").replace(/\./g, "_");
      const secretValue = this.env[envKey];
      if (secretValue === undefined) {
        throw new Error(`Secret "${secretName}" (env: ${envKey}) is not configured.`);
      }
      return secretValue;
    });
  }

  async handleProxy(request, corsHeaders) {
    const body = await request.json();
    const { events_since, events, request: apiRequest } = body;

    // Determine anchor hash: hashEvent(last_stored_event) or zeros for genesis.
    // parentHash of the next event = hashEvent(previous) which hashes the full
    // canonical form (including populated state_hash_after), so the anchor must
    // be computed the same way — not just state_hash_after.
    let anchorHash = "0".repeat(64);
    if (events_since && events_since > 0) {
      const anchorRows = this.sql.exec(
        `SELECT sequence, timestamp, event_type, schema_version, payload, state_hash_after, parent_hash FROM events WHERE sequence = ?`,
        events_since
      ).toArray();
      if (anchorRows.length > 0) {
        anchorHash = await this.hashEvent(anchorRows[0]);
      }
    } else {
      // Use last stored event's hash as anchor, or zeros if empty
      const lastRows = this.sql.exec(
        `SELECT sequence, timestamp, event_type, schema_version, payload, state_hash_after, parent_hash FROM events ORDER BY sequence DESC LIMIT 1`
      ).toArray();
      if (lastRows.length > 0) {
        anchorHash = await this.hashEvent(lastRows[0]);
      }
    }

    // Verify incoming events chain from anchor
    if (events && events.length > 0) {
      const verification = await this.verifyChain(events, anchorHash);
      if (!verification.valid) {
        // Fetch server events for the client to reconcile
        const sinceSeq = events_since || 0;
        const serverRows = this.sql.exec(
          `SELECT sequence, timestamp, event_type, schema_version, payload, state_hash_after, parent_hash FROM events WHERE sequence > ? ORDER BY sequence ASC`,
          sinceSeq
        ).toArray();

        return new Response(JSON.stringify({
          events_accepted: false,
          error: verification.error,
          failed_at: verification.failedAt,
          server_events: serverRows,
          response: null,
        }), {
          status: 409,
          headers: corsHeaders,
        });
      }

      // Store verified events
      for (const event of events) {
        this.sql.exec(
          `INSERT INTO events (sequence, timestamp, event_type, schema_version, payload, state_hash_after, parent_hash) VALUES (?, ?, ?, ?, ?, ?, ?)`,
          event.sequence,
          event.timestamp,
          event.event_type,
          event.schema_version,
          event.payload,
          event.state_hash_after,
          event.parent_hash
        );
      }
    }

    // Inject secrets into the API request
    let resolvedUrl = this.injectSecrets(apiRequest.url);
    const resolvedHeaders = {};
    if (apiRequest.headers && typeof apiRequest.headers === "object") {
      for (const [key, value] of Object.entries(apiRequest.headers)) {
        resolvedHeaders[key] = this.injectSecrets(value);
      }
    }
    let resolvedBody = apiRequest.body;
    if (typeof resolvedBody === "string") {
      resolvedBody = this.injectSecrets(resolvedBody);
    } else if (resolvedBody !== undefined && resolvedBody !== null) {
      resolvedBody = JSON.stringify(resolvedBody);
    }

    // Forward API call
    try {
      const apiResponse = await fetch(resolvedUrl, {
        method: apiRequest.method || "POST",
        headers: resolvedHeaders,
        body: resolvedBody,
      });

      const responseBody = await apiResponse.text();
      const responseHeaders = {};
      apiResponse.headers.forEach((value, key) => {
        responseHeaders[key] = value;
      });

      return new Response(JSON.stringify({
        events_accepted: true,
        server_events: [],
        response: {
          status: apiResponse.status,
          headers: responseHeaders,
          body: responseBody,
        },
      }), {
        status: 200,
        headers: corsHeaders,
      });
    } catch (e) {
      return new Response(JSON.stringify({
        events_accepted: true,
        server_events: [],
        response: null,
        error: "Upstream request failed: " + e.message,
      }), {
        status: 502,
        headers: corsHeaders,
      });
    }
  }
}
"""

proc generateWranglerToml*(appName: string, secrets: seq[string],
                           hasDO: bool = false): string =
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

  # Generate the JS and TOML — always include DO for Phase 1+
  let workerJs = generateWorkerJs(secrets, routes, hasDO = true)
  let durableObjectJs = generateDurableObjectJs()
  let combinedJs = workerJs & "\n" & durableObjectJs
  let wranglerToml = generateWranglerToml(appName, secrets, hasDO = true)

  # Create output directory and write files
  discard gorge("mkdir -p " & outputDir)
  writeFile(outputDir & "/worker.js", combinedJs)
  writeFile(outputDir & "/wrangler.toml", wranglerToml)
