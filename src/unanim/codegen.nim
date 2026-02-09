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

proc generateWorkerJs*(secrets: seq[string], routes: seq[RouteInfo]): string =
  ## Generate a standalone Cloudflare Worker JS file (ES modules format).
  ## The Worker:
  ## - Accepts POST requests with JSON body containing target URL and headers
  ## - Reads secrets from env, replaces <<SECRET:name>> placeholders
  ## - Forwards the request to the target URL
  ## - Returns the response
  ##
  ## SCAFFOLD(phase1, #4): This is a simplified v1 stateless router.
  ## Phase 2 adds DOs, Phase 3 adds sync, Phase 4 adds auth/webhooks/cron.

  result = """// Unanim Generated Cloudflare Worker
// SCAFFOLD(phase1, #4): Stateless router with credential injection.
// This Worker is standalone — copy to a fresh Cloudflare project and it works.

export default {
  async fetch(request, env, ctx) {
    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    // Only accept POST requests
    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed. Use POST." }), {
        status: 405,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    let body;
    try {
      body = await request.json();
    } catch (e) {
      return new Response(JSON.stringify({ error: "Invalid JSON body." }), {
        status: 400,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    const { url, headers, method, requestBody } = body;

    if (!url) {
      return new Response(JSON.stringify({ error: "Missing 'url' in request body." }), {
        status: 400,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }

    // Inject secrets: replace <<SECRET:name>> placeholders with env values
    function injectSecrets(value) {
      if (typeof value !== "string") return value;
      return value.replace(/<<SECRET:([^>]+)>>/g, (match, secretName) => {
        const envKey = secretName.toUpperCase().replace(/-/g, "_").replace(/\./g, "_");
        const secretValue = env[envKey];
        if (secretValue === undefined) {
          throw new Error(`Secret "${secretName}" (env: ${envKey}) is not configured.`);
        }
        return secretValue;
      });
    }

    // Inject secrets into headers
    const resolvedHeaders = {};
    if (headers && typeof headers === "object") {
      for (const [key, value] of Object.entries(headers)) {
        resolvedHeaders[key] = injectSecrets(value);
      }
    }

    // Inject secrets into URL (in case secret is embedded in URL)
    const resolvedUrl = injectSecrets(url);

    // Inject secrets into request body if it's a string
    let resolvedBody = requestBody;
    if (typeof resolvedBody === "string") {
      resolvedBody = injectSecrets(resolvedBody);
    } else if (resolvedBody !== undefined && resolvedBody !== null) {
      resolvedBody = JSON.stringify(resolvedBody);
    }

    // Forward the request
    try {
      const response = await fetch(resolvedUrl, {
        method: method || "POST",
        headers: resolvedHeaders,
        body: resolvedBody,
      });

      const responseBody = await response.text();

      return new Response(responseBody, {
        status: response.status,
        headers: {
          "Content-Type": response.headers.get("Content-Type") || "application/octet-stream",
          "Access-Control-Allow-Origin": "*",
        },
      });
    } catch (e) {
      return new Response(JSON.stringify({ error: "Upstream request failed: " + e.message }), {
        status: 502,
        headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
      });
    }
  },
};
"""

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
        `INSERT OR REPLACE INTO events (sequence, timestamp, event_type, schema_version, payload, state_hash_after, parent_hash) VALUES (?, ?, ?, ?, ?, ?, ?)`,
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
    result &= "new_classes = [\"UserDO\"]\n"

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

  # Generate the JS and TOML
  let workerJs = generateWorkerJs(secrets, routes)
  let wranglerToml = generateWranglerToml(appName, secrets)

  # Create output directory and write files
  discard gorge("mkdir -p " & outputDir)
  writeFile(outputDir & "/worker.js", workerJs)
  writeFile(outputDir & "/wrangler.toml", wranglerToml)
