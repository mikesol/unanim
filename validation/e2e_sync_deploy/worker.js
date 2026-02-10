// Unanim Generated Cloudflare Worker
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
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, X-User-Id",
        },
      });
    }

    // Route /do/* requests to Durable Objects
    const reqUrl = new URL(request.url);
    if (reqUrl.pathname.startsWith("/do/")) {
      const userId = request.headers.get("X-User-Id") || reqUrl.searchParams.get("user_id");
      if (!userId) {
        return new Response(JSON.stringify({ error: "Missing user ID. Provide X-User-Id header or user_id query param." }), {
          status: 400,
          headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
        });
      }
      const doId = env.USER_DO.idFromName(userId);
      const doStub = env.USER_DO.get(doId);
      const doPath = reqUrl.pathname.replace(/^\/do/, "");
      const doUrl = new URL(doPath + reqUrl.search, request.url);
      return doStub.fetch(new Request(doUrl, request));
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

// Unanim Generated Durable Object
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
      payload TEXT NOT NULL
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
      } else if (path === "/proxy" && request.method === "POST") {
        return await this.handleProxy(request, corsHeaders);
      } else if (path === "/sync" && request.method === "POST") {
        return await this.handleSync(request, corsHeaders);
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
        `INSERT INTO events (sequence, timestamp, event_type, schema_version, payload) VALUES (?, ?, ?, ?, ?)`,
        event.sequence,
        event.timestamp,
        event.event_type,
        event.schema_version,
        event.payload
      );
    }

    return new Response(JSON.stringify({ stored: events.length }), {
      status: 200,
      headers: corsHeaders,
    });
  }

  async getEvents(since, corsHeaders) {
    const rows = this.sql.exec(
      `SELECT sequence, timestamp, event_type, schema_version, payload FROM events WHERE sequence > ? ORDER BY sequence ASC`,
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

  getServerEventsSince(eventsSince, clientSequences) {
    const rows = this.sql.exec(
      `SELECT sequence, timestamp, event_type, schema_version, payload FROM events WHERE sequence > ? ORDER BY sequence ASC`,
      eventsSince
    ).toArray();
    return rows.filter(row => !clientSequences.has(row.sequence));
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

  async verifyAndStoreEvents(events_since, events, corsHeaders) {
    // Determine expected next sequence from stored events
    let expectedNextSeq = 1;
    if (events_since && events_since > 0) {
      expectedNextSeq = events_since + 1;
    } else {
      const lastRow = this.sql.exec(
        `SELECT MAX(sequence) as latest FROM events`
      ).one();
      if (lastRow.latest) {
        expectedNextSeq = lastRow.latest + 1;
      }
    }

    // Verify and store incoming events (sequence continuity check)
    if (events && events.length > 0) {
      if (events[0].sequence !== expectedNextSeq) {
        const sinceSeq = events_since || 0;
        const serverEvents = this.getServerEventsSince(sinceSeq, new Set());

        return { error: new Response(JSON.stringify({
          events_accepted: false,
          error: `Sequence gap: expected ${expectedNextSeq}, got ${events[0].sequence}`,
          server_events: serverEvents,
          response: null,
        }), {
          status: 409,
          headers: corsHeaders,
        }) };
      }

      // Verify internal sequence continuity
      for (let i = 1; i < events.length; i++) {
        if (events[i].sequence !== events[i - 1].sequence + 1) {
          const sinceSeq = events_since || 0;
          const serverEvents = this.getServerEventsSince(sinceSeq, new Set());

          return { error: new Response(JSON.stringify({
            events_accepted: false,
            error: `Sequence gap at event ${i}: expected ${events[i - 1].sequence + 1}, got ${events[i].sequence}`,
            server_events: serverEvents,
            response: null,
          }), {
            status: 409,
            headers: corsHeaders,
          }) };
        }
      }

      // Store verified events
      for (const event of events) {
        this.sql.exec(
          `INSERT INTO events (sequence, timestamp, event_type, schema_version, payload) VALUES (?, ?, ?, ?, ?)`,
          event.sequence,
          event.timestamp,
          event.event_type,
          event.schema_version,
          event.payload
        );
      }
    }

    // Collect client event sequences for filtering
    const clientSequences = new Set();
    if (events && events.length > 0) {
      for (const event of events) {
        clientSequences.add(event.sequence);
      }
    }

    // Get events the client hasn't seen
    const sinceSeq = events_since || 0;
    const serverEvents = this.getServerEventsSince(sinceSeq, clientSequences);

    return { serverEvents };
  }

  async handleProxy(request, corsHeaders) {
    const body = await request.json();
    const { events_since, events, request: apiRequest } = body;

    if (!apiRequest || !apiRequest.url) {
      return new Response(JSON.stringify({ error: "Missing 'request.url' in proxy body." }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    const result = await this.verifyAndStoreEvents(events_since, events, corsHeaders);
    if (result.error) return result.error;
    const serverEvents = result.serverEvents;

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
        server_events: serverEvents,
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
        server_events: serverEvents,
        response: null,
        error: "Upstream request failed: " + e.message,
      }), {
        status: 502,
        headers: corsHeaders,
      });
    }
  }

  async handleSync(request, corsHeaders) {
    const body = await request.json();
    const { events_since, events } = body;

    const result = await this.verifyAndStoreEvents(events_since, events, corsHeaders);
    if (result.error) return result.error;

    return new Response(JSON.stringify({
      events_accepted: true,
      server_events: result.serverEvents,
      response: null,
    }), {
      status: 200,
      headers: corsHeaders,
    });
  }
}
