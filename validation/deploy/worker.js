// Unanim Generated Cloudflare Worker
// SCAFFOLD(phase1, #4): Stateless router with credential injection.
// This Worker is standalone — copy to a fresh Cloudflare project and it works.

export default {
  async fetch(request, env, ctx) {
    // Only accept POST requests
    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed. Use POST." }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      });
    }

    let body;
    try {
      body = await request.json();
    } catch (e) {
      return new Response(JSON.stringify({ error: "Invalid JSON body." }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { url, headers, method, requestBody } = body;

    if (!url) {
      return new Response(JSON.stringify({ error: "Missing 'url' in request body." }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
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
        },
      });
    } catch (e) {
      return new Response(JSON.stringify({ error: "Upstream request failed: " + e.message }), {
        status: 502,
        headers: { "Content-Type": "application/json" },
      });
    }
  },
};
