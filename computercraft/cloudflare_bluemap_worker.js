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
const BLUEMAP_BASE = "http://172.255.251.68.nip.io:25581";

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

async function fetchBlueMap(path) {
  const response = await fetch(BLUEMAP_BASE + path, {
    headers: { "Accept": "application/json" },
    signal: AbortSignal.timeout(8000)
  });
  if (!response.ok) throw new Error(`${path} returned HTTP ${response.status}`);
  return response.json();
}

function teamName(marker) {
  const label = String(marker.label || "Unknown");
  const detail = String(marker.detail || "");
  const heading = detail.match(/<h3[^>]*>([^<]+)<\/h3>/i);
  return heading ? heading[1].trim() : label.replace(/\s+.{1,3}\s+Region.*$/i, "").trim();
}

function members(detail) {
  const result = [];
  const seen = new Set();
  const regex = /alt="([^"]+)"/g;
  let match;
  while ((match = regex.exec(String(detail || ""))) !== null) {
    const name = match[1].trim();
    const key = name.toLowerCase();
    if (name && !seen.has(key)) {
      seen.add(key);
      result.push(name);
    }
  }
  return result;
}

function markerBounds(marker, id) {
  const shape = Array.isArray(marker.shape) ? marker.shape : [];
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  for (const point of shape) {
    const x = Number(point.x), z = Number(point.z);
    if (!Number.isFinite(x) || !Number.isFinite(z)) continue;
    minX = Math.min(minX, x); maxX = Math.max(maxX, x);
    minZ = Math.min(minZ, z); maxZ = Math.max(maxZ, z);
  }
  const position = marker.position || {};
  const centerX = Number.isFinite(Number(position.x)) ? Number(position.x) :
    (Number.isFinite(minX) ? (minX + maxX) / 2 : 0);
  const centerZ = Number.isFinite(Number(position.z)) ? Number(position.z) :
    (Number.isFinite(minZ) ? (minZ + maxZ) / 2 : 0);
  if (!Number.isFinite(minX)) minX = maxX = centerX;
  if (!Number.isFinite(minZ)) minZ = maxZ = centerZ;
  const chunkMatch = String(marker.detail || "").match(/Chunks:<\/div>\s*<div>([\d,]+)/i);
  return {
    id: String(id), x: Math.round(centerX), z: Math.round(centerZ),
    minX: Math.floor(minX), maxX: Math.ceil(maxX),
    minZ: Math.floor(minZ), maxZ: Math.ceil(maxZ),
    width: Math.max(1, Math.ceil(maxX - minX)),
    depth: Math.max(1, Math.ceil(maxZ - minZ)),
    chunks: chunkMatch ? Number(chunkMatch[1].replace(/,/g, "")) : 0
  };
}

function parseTeamDefinitions(markerData) {
  const markerSet = markerData["ftbchunks.claims.2d"];
  if (!markerSet || !markerSet.markers) throw new Error("FTB Chunks marker set missing");
  const grouped = new Map();
  for (const [id, marker] of Object.entries(markerSet.markers)) {
    const name = teamName(marker);
    const key = name.toLowerCase();
    if (!grouped.has(key)) grouped.set(key, {
      key, name,
      color: marker.lineColor || marker.fillColor || { r:255, g:255, b:255 },
      memberNames: [], regions: []
    });
    const team = grouped.get(key);
    const known = new Set(team.memberNames.map(name => name.toLowerCase()));
    for (const member of members(marker.detail)) {
      if (!known.has(member.toLowerCase())) {
        known.add(member.toLowerCase()); team.memberNames.push(member);
      }
    }
    team.regions.push(markerBounds(marker, id));
  }
  return Array.from(grouped.values()).map(team => {
    team.chunks = team.regions.reduce((sum, region) => sum + (Number(region.chunks) || 0), 0);
    team.areaBlocks = team.chunks * 256;
    team.members = team.memberNames.length;
    return team;
  });
}

function inside(position, region) {
  const x = Number(position && position.x), z = Number(position && position.z);
  return Number.isFinite(x) && Number.isFinite(z) &&
    x >= region.minX && x <= region.maxX && z >= region.minZ && z <= region.maxZ;
}

async function fetchDirect(mode) {
  const playerData = await fetchBlueMap("/maps/world/live/players.json");
  const rawPlayers = Array.isArray(playerData.players) ? playerData.players : [];
  if (mode === "players") return { players: rawPlayers, generatedAt: new Date().toISOString() };

  const definitions = parseTeamDefinitions(
    await fetchBlueMap("/maps/world/live/markers.json")
  );
  const memberTeam = new Map();
  for (const team of definitions) {
    for (const name of team.memberNames) memberTeam.set(name.toLowerCase(), team);
  }
  const players = rawPlayers.map(player => {
    const team = memberTeam.get(String(player.name || "").toLowerCase()) || null;
    let ownBaseRegion = null, insideTeam = null, insideRegion = null;
    if (team) team.regions.some((region, index) => {
      if (!inside(player.position, region)) return false;
      ownBaseRegion = index + 1; insideTeam = team.name; insideRegion = index + 1; return true;
    });
    if (!ownBaseRegion) definitions.some(candidate => candidate.regions.some((region, index) => {
      if (!inside(player.position, region)) return false;
      insideTeam = candidate.name; insideRegion = index + 1; return true;
    }));
    return {
      ...player, team: team ? team.name : null,
      inOwnBase: ownBaseRegion !== null, ownBaseRegion, insideTeam, insideRegion,
      locationStatus: ownBaseRegion ? "OWN_BASE" : (insideTeam ? "FOREIGN_BASE" : "OUTSIDE_BASES")
    };
  });
  const enriched = new Map(players.map(player => [String(player.name || "").toLowerCase(), player]));
  const bases = [];
  const teams = definitions.map(definition => {
    const onlinePlayers = definition.memberNames.map(name => enriched.get(name.toLowerCase())).filter(Boolean);
    const onlineNames = onlinePlayers.map(player => player.name);
    const atBaseNames = onlinePlayers.filter(player => player.inOwnBase).map(player => player.name);
    definition.regions.forEach((region, index) => {
      const playersAtBase = onlinePlayers.filter(player => player.ownBaseRegion === index + 1)
        .map(player => player.name);
      bases.push({
        id: `${definition.key}:${index + 1}`, team: definition.name, region: index + 1,
        color: definition.color, ...region, online: onlinePlayers.length,
        atBase: playersAtBase.length, playersAtBase
      });
    });
    return {
      name: definition.name, color: definition.color, chunks: definition.chunks,
      areaBlocks: definition.areaBlocks, members: definition.members,
      online: onlineNames.length, atBase: atBaseNames.length,
      away: Math.max(0, onlineNames.length - atBaseNames.length),
      onlineNames, atBaseNames, memberNames: definition.memberNames, regions: definition.regions
    };
  });
  teams.sort((a, b) => b.online - a.online || b.members - a.members || a.name.localeCompare(b.name));
  bases.sort((a, b) => b.chunks - a.chunks || a.team.localeCompare(b.team));
  return { players, teams, bases, generatedAt: new Date().toISOString() };
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
      let payload;
      try {
        payload = await fetchDirect(mode);
        payload.gateway = { provider: "cloudflare", source: "bluemap-direct", cached: false };
      } catch (directError) {
        payload = await fetchGoogle(mode, forceTeams);
        payload.gateway.directError = String(directError && directError.message || directError);
      }
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
