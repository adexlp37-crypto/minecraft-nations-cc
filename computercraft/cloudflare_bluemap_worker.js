// Minecraft Nations BlueMap cache gateway for Cloudflare Workers.
//
// Existing programs may call this URL without parameters and receive a compact
// { players = [...] } response. The team dashboard uses ?mode=players and
// ?mode=teams. Cloudflare caches the Google proxy responses so every in-game
// computer shares the same upstream request instead of spending Google quota.

const GOOGLE_PROXIES = [
  "https://script.google.com/macros/s/AKfycbx11MizOXaAJ-ScN7C0-7Tuo2mjEu-urxRAnNAASwkQSa9iTUTy50JPuq8pEnZDs0F4uw/exec",
  "https://script.google.com/macros/s/AKfycbwSsBb4SokTdVDhIUv0zTJzcMT8o_hJyzo7ziEdlMOYK8gACLHOKyQPZbpPnzTESiR5Jg/exec",
  "https://script.google.com/macros/s/AKfycbyXcO7DJgloCLhteQixcPabIXHQTANvCyrMaOrLWjava--_iqFB-ItfgLTwbBpHzOV3/exec"
];

const PLAYER_TTL_SECONDS = 6;
const TEAM_TTL_SECONDS = 600;
const ERROR_TTL_SECONDS = 30;

function jsonResponse(value, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "X-Content-Type-Options": "nosniff",
      ...extraHeaders
    }
  });
}

function validPayload(payload, mode) {
  if (!payload || typeof payload !== "object" || payload.error) return false;
  if (!Array.isArray(payload.players)) return false;
  return mode !== "teams" || (Array.isArray(payload.teams) && Array.isArray(payload.bases));
}

async function fetchGoogle(mode, forceTeams) {
  const failures = [];
  for (let index = 0; index < GOOGLE_PROXIES.length; index++) {
    const upstream = new URL(GOOGLE_PROXIES[index]);
    upstream.searchParams.set("mode", mode);
    upstream.searchParams.set("cloudflare", Date.now().toString());
    if (forceTeams) upstream.searchParams.set("refreshTeams", "1");

    try {
      const response = await fetch(upstream.toString(), {
        headers: {
          "Accept": "application/json",
          "Cache-Control": "no-cache",
          "User-Agent": "Minecraft-Nations-Cloudflare-Gateway/1.0"
        },
        redirect: "follow",
        signal: AbortSignal.timeout(7000)
      });
      const text = await response.text();
      let payload;
      try {
        payload = JSON.parse(text);
      } catch (_) {
        failures.push(`P${index + 1}: invalid JSON`);
        continue;
      }
      if (response.ok && validPayload(payload, mode)) {
        payload.gateway = {
          provider: "cloudflare",
          googleProxy: index + 1,
          cached: false
        };
        return payload;
      }
      failures.push(`P${index + 1}: ${payload.error || `HTTP ${response.status}`}`);
    } catch (error) {
      failures.push(`P${index + 1}: ${String(error && error.message || error)}`);
    }
  }
  throw new Error(failures.join(" | "));
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type"
        }
      });
    }
    if (request.method !== "GET") {
      return jsonResponse({ error: "GET requests only" }, 405);
    }

    const incoming = new URL(request.url);
    if (incoming.searchParams.get("mode") === "health") {
      return jsonResponse({
        ok: true,
        service: "minecraft-nations-bluemap-gateway",
        playerCacheSeconds: PLAYER_TTL_SECONDS,
        teamCacheSeconds: TEAM_TTL_SECONDS
      });
    }

    // Legacy scanners omit mode and only need players. This keeps the old
    // coordinate scanner and canal controller compatible.
    const mode = incoming.searchParams.get("mode") === "teams" ? "teams" : "players";
    const forceTeams = mode === "teams" && incoming.searchParams.get("refreshTeams") === "1";
    const ttl = mode === "teams" ? TEAM_TTL_SECONDS : PLAYER_TTL_SECONDS;
    const cache = caches.default;
    const cacheKey = new Request(`https://minecraft-nations-cache.invalid/${mode}`);
    const errorCacheKey = new Request(`https://minecraft-nations-cache.invalid/${mode}-error`);

    if (!forceTeams) {
      const hit = await cache.match(cacheKey);
      if (hit) {
        const cachedPayload = await hit.json();
        cachedPayload.gateway = cachedPayload.gateway || {};
        cachedPayload.gateway.provider = "cloudflare";
        cachedPayload.gateway.cached = true;
        return jsonResponse(cachedPayload, 200, {
          "Cache-Control": "no-store",
          "X-Nations-Cache": "HIT"
        });
      }

      const errorHit = await cache.match(errorCacheKey);
      if (errorHit) {
        const errorPayload = await errorHit.json();
        return jsonResponse(errorPayload, 502, {
          "Cache-Control": "no-store",
          "X-Nations-Cache": "ERROR-HIT"
        });
      }
    }

    try {
      const payload = await fetchGoogle(mode, forceTeams);
      const stored = jsonResponse(payload, 200, {
        "Cache-Control": `public, max-age=${ttl}`,
        "X-Nations-Cache": "MISS"
      });
      ctx.waitUntil(cache.put(cacheKey, stored.clone()));
      ctx.waitUntil(cache.delete(errorCacheKey));
      return jsonResponse(payload, 200, {
        "Cache-Control": "no-store",
        "X-Nations-Cache": "MISS"
      });
    } catch (error) {
      const errorPayload = {
        players: [],
        teams: [],
        bases: [],
        generatedAt: new Date().toISOString(),
        gateway: { provider: "cloudflare", cached: false },
        error: String(error && error.message || error)
      };
      const storedError = jsonResponse(errorPayload, 502, {
        "Cache-Control": `public, max-age=${ERROR_TTL_SECONDS}`
      });
      ctx.waitUntil(cache.put(errorCacheKey, storedError));
      return jsonResponse(errorPayload, 502, {
        "Cache-Control": "no-store",
        "X-Nations-Cache": "ERROR-MISS"
      });
    }
  }
};
