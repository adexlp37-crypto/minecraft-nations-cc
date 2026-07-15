// BlueMap player/team proxy for Google Apps Script.
// Deploy as a Web App with access set to "Anyone".
//
// Normal request:       YOUR_WEB_APP_URL
// Force team refresh:   YOUR_WEB_APP_URL?refreshTeams=1
//
// Team/base geometry is stored persistently. Normal requests only download the
// small live players.json file, so movement remains live without repeatedly
// downloading the large markers.json file.

const BLUEMAP_BASE = "http://172.255.251.68:25581";
const TEAM_CACHE_KEY = "bluemap-team-definitions-v4";
const TEAM_PROPERTY_META = "BLUEMAP_TEAM_DATA_V4_META";
const TEAM_PROPERTY_PREFIX = "BLUEMAP_TEAM_DATA_V4_";
const PROPERTY_CHUNK_SIZE = 8000;
const MEMORY_CACHE_SECONDS = 21600;
const TEAM_REFRESH_MILLISECONDS = 10 * 60 * 1000;
const PLAYER_CACHE_KEY = "bluemap-live-players-v1";
const PLAYER_CACHE_SECONDS = 6;

function fetchJson_(path) {
  const response = UrlFetchApp.fetch(BLUEMAP_BASE + path, {
    muteHttpExceptions: true,
    followRedirects: true,
    headers: { Accept: "application/json" }
  });
  const code = response.getResponseCode();
  if (code < 200 || code >= 300) {
    throw new Error(path + " returned HTTP " + code);
  }
  return JSON.parse(response.getContentText());
}

function livePlayerData_() {
  const cache = CacheService.getScriptCache();
  const cached = cache.get(PLAYER_CACHE_KEY);
  if (cached) return JSON.parse(cached);
  const playerData = fetchJson_("/maps/world/live/players.json");
  const encoded = JSON.stringify(playerData);
  if (encoded.length < 95000) {
    cache.put(PLAYER_CACHE_KEY, encoded, PLAYER_CACHE_SECONDS);
  }
  return playerData;
}

function teamName_(marker) {
  const label = String(marker.label || "Unknown");
  const detail = String(marker.detail || "");
  const heading = detail.match(/<h3[^>]*>([^<]+)<\/h3>/i);
  return heading ? heading[1].trim() :
    label.replace(/\s+.{1,3}\s+Region.*$/i, "").trim();
}

function members_(detail) {
  const result = [];
  const seen = {};
  const regex = /alt="([^"]+)"/g;
  let match;
  while ((match = regex.exec(String(detail || ""))) !== null) {
    const name = match[1].trim();
    const key = name.toLowerCase();
    if (name && !seen[key]) {
      seen[key] = true;
      result.push(name);
    }
  }
  return result;
}

function markerBounds_(marker, fallbackId) {
  const shape = Array.isArray(marker.shape) ? marker.shape : [];
  let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
  shape.forEach(function(point) {
    const x = Number(point.x);
    const z = Number(point.z);
    if (!isFinite(x) || !isFinite(z)) return;
    minX = Math.min(minX, x);
    maxX = Math.max(maxX, x);
    minZ = Math.min(minZ, z);
    maxZ = Math.max(maxZ, z);
  });

  const position = marker.position || {};
  const centerX = isFinite(Number(position.x)) ? Number(position.x) :
    (isFinite(minX) ? (minX + maxX) / 2 : 0);
  const centerZ = isFinite(Number(position.z)) ? Number(position.z) :
    (isFinite(minZ) ? (minZ + maxZ) / 2 : 0);
  if (!isFinite(minX)) minX = maxX = centerX;
  if (!isFinite(minZ)) minZ = maxZ = centerZ;

  const chunkMatch = String(marker.detail || "")
    .match(/Chunks:<\/div>\s*<div>([\d,]+)/i);
  return {
    id: String(fallbackId),
    x: Math.round(centerX),
    z: Math.round(centerZ),
    minX: Math.floor(minX),
    maxX: Math.ceil(maxX),
    minZ: Math.floor(minZ),
    maxZ: Math.ceil(maxZ),
    width: Math.max(1, Math.ceil(maxX - minX)),
    depth: Math.max(1, Math.ceil(maxZ - minZ)),
    chunks: chunkMatch ? Number(chunkMatch[1].replace(/,/g, "")) : 0
  };
}

function parseTeams_(markerData) {
  const markerSet = markerData["ftbchunks.claims.2d"];
  if (!markerSet || !markerSet.markers) {
    throw new Error("FTB Chunks 2D marker set was not found");
  }

  const grouped = {};
  Object.keys(markerSet.markers).forEach(function(id) {
    const marker = markerSet.markers[id];
    const name = teamName_(marker);
    const key = name.toLowerCase();
    if (!grouped[key]) {
      grouped[key] = {
        key: key,
        name: name,
        color: marker.lineColor || marker.fillColor || { r:255, g:255, b:255 },
        memberNames: [],
        regions: []
      };
    }

    const team = grouped[key];
    const known = {};
    team.memberNames.forEach(function(member) { known[member.toLowerCase()] = true; });
    members_(marker.detail).forEach(function(member) {
      if (!known[member.toLowerCase()]) {
        known[member.toLowerCase()] = true;
        team.memberNames.push(member);
      }
    });
    team.regions.push(markerBounds_(marker, id));
  });

  return Object.keys(grouped).map(function(key) {
    const team = grouped[key];
    team.chunks = team.regions.reduce(function(total, region) {
      return total + (Number(region.chunks) || 0);
    }, 0);
    team.areaBlocks = team.chunks * 256;
    team.members = team.memberNames.length;
    return team;
  });
}

function savePersistentTeams_(teams) {
  const properties = PropertiesService.getScriptProperties();
  const encoded = JSON.stringify(teams);
  const oldMetaRaw = properties.getProperty(TEAM_PROPERTY_META);
  const oldMeta = oldMetaRaw ? JSON.parse(oldMetaRaw) : {};
  const count = Math.ceil(encoded.length / PROPERTY_CHUNK_SIZE);
  const values = {};
  for (let index = 0; index < count; index++) {
    values[TEAM_PROPERTY_PREFIX + index] = encoded.slice(
      index * PROPERTY_CHUNK_SIZE,
      (index + 1) * PROPERTY_CHUNK_SIZE
    );
  }
  values[TEAM_PROPERTY_META] = JSON.stringify({
    count: count,
    updatedAt: new Date().toISOString()
  });
  properties.setProperties(values, false);
  for (let index = count; index < Number(oldMeta.count || 0); index++) {
    properties.deleteProperty(TEAM_PROPERTY_PREFIX + index);
  }

  const cacheText = JSON.stringify({ teams: teams, updatedAt: JSON.parse(values[TEAM_PROPERTY_META]).updatedAt });
  if (cacheText.length < 95000) {
    CacheService.getScriptCache().put(TEAM_CACHE_KEY, cacheText, MEMORY_CACHE_SECONDS);
  }
  return JSON.parse(values[TEAM_PROPERTY_META]).updatedAt;
}

function loadPersistentTeams_() {
  const cached = CacheService.getScriptCache().get(TEAM_CACHE_KEY);
  if (cached) return JSON.parse(cached);

  const properties = PropertiesService.getScriptProperties();
  const metaRaw = properties.getProperty(TEAM_PROPERTY_META);
  if (!metaRaw) return null;
  const meta = JSON.parse(metaRaw);
  let encoded = "";
  for (let index = 0; index < Number(meta.count || 0); index++) {
    const part = properties.getProperty(TEAM_PROPERTY_PREFIX + index);
    if (part === null) return null;
    encoded += part;
  }
  const stored = { teams: JSON.parse(encoded), updatedAt: meta.updatedAt };
  const cacheText = JSON.stringify(stored);
  if (cacheText.length < 95000) {
    CacheService.getScriptCache().put(TEAM_CACHE_KEY, cacheText, MEMORY_CACHE_SECONDS);
  }
  return stored;
}

function teamDefinitions_(forceRefresh, allowStale) {
  if (!forceRefresh) {
    const stored = loadPersistentTeams_();
    if (stored) {
      const age = Date.now() - Date.parse(stored.updatedAt || 0);
      if (allowStale || age < TEAM_REFRESH_MILLISECONDS) return stored;
    }
  }

  const lock = LockService.getScriptLock();
  lock.waitLock(30000);
  try {
    if (!forceRefresh) {
      const stored = loadPersistentTeams_();
      if (stored) {
        const age = Date.now() - Date.parse(stored.updatedAt || 0);
        if (allowStale || age < TEAM_REFRESH_MILLISECONDS) return stored;
      }
    }
    const teams = parseTeams_(fetchJson_("/maps/world/live/markers.json"));
    const updatedAt = savePersistentTeams_(teams);
    return { teams: teams, updatedAt: updatedAt };
  } finally {
    lock.releaseLock();
  }
}

function insideRegion_(position, region) {
  if (!position) return false;
  const x = Number(position.x);
  const z = Number(position.z);
  return isFinite(x) && isFinite(z) &&
    x >= region.minX && x <= region.maxX &&
    z >= region.minZ && z <= region.maxZ;
}

function doGet(e) {
  try {
    const mode = e && e.parameter && String(e.parameter.mode || "full");
    const forceRefresh = e && e.parameter && e.parameter.refreshTeams === "1";
    // Player requests always use the last stored team snapshot. They never
    // download markers.json and therefore remain small and fast.
    const stored = teamDefinitions_(forceRefresh, mode === "players");
    const playerData = livePlayerData_();
    const rawPlayers = Array.isArray(playerData.players) ? playerData.players : [];
    const onlineByName = {};
    rawPlayers.forEach(function(player) {
      onlineByName[String(player.name || "").toLowerCase()] = player;
    });

    const memberTeam = {};
    stored.teams.forEach(function(team) {
      team.memberNames.forEach(function(name) {
        memberTeam[name.toLowerCase()] = team;
      });
    });

    const players = rawPlayers.map(function(player) {
      const team = memberTeam[String(player.name || "").toLowerCase()] || null;
      let ownRegion = null;
      let containingTeam = null;
      let containingRegion = null;

      if (team) {
        team.regions.some(function(region, index) {
          if (!insideRegion_(player.position, region)) return false;
          ownRegion = index + 1;
          return true;
        });
      }
      if (!ownRegion) {
        stored.teams.some(function(candidate) {
          return candidate.regions.some(function(region, index) {
            if (!insideRegion_(player.position, region)) return false;
            containingTeam = candidate.name;
            containingRegion = index + 1;
            return true;
          });
        });
      }

      return {
        uuid: player.uuid,
        name: player.name,
        foreign: player.foreign === true,
        position: player.position,
        rotation: player.rotation,
        team: team ? team.name : null,
        inOwnBase: ownRegion !== null,
        ownBaseRegion: ownRegion,
        insideTeam: ownRegion ? team.name : containingTeam,
        insideRegion: ownRegion || containingRegion,
        locationStatus: ownRegion ? "OWN_BASE" :
          (containingTeam ? "FOREIGN_BASE" : "OUTSIDE_BASES")
      };
    });

    const enrichedByName = {};
    players.forEach(function(player) {
      enrichedByName[String(player.name || "").toLowerCase()] = player;
    });

    if (mode === "players") {
      return ContentService.createTextOutput(JSON.stringify({
        players: players,
        generatedAt: new Date().toISOString(),
        teamDataUpdatedAt: stored.updatedAt
      })).setMimeType(ContentService.MimeType.JSON);
    }

    const bases = [];
    const teams = stored.teams.map(function(definition) {
      const onlinePlayers = definition.memberNames.map(function(name) {
        return enrichedByName[name.toLowerCase()];
      }).filter(Boolean);
      const onlineNames = onlinePlayers.map(function(player) { return player.name; });
      const atBaseNames = onlinePlayers.filter(function(player) {
        return player.inOwnBase;
      }).map(function(player) { return player.name; });

      definition.regions.forEach(function(region, index) {
        const regionPlayers = onlinePlayers.filter(function(player) {
          return player.ownBaseRegion === index + 1;
        }).map(function(player) { return player.name; });
        bases.push({
          id: definition.key + ":" + (index + 1),
          team: definition.name,
          region: index + 1,
          color: definition.color,
          x: region.x,
          z: region.z,
          minX: region.minX,
          maxX: region.maxX,
          minZ: region.minZ,
          maxZ: region.maxZ,
          width: region.width,
          depth: region.depth,
          chunks: region.chunks,
          online: onlinePlayers.length,
          atBase: regionPlayers.length,
          playersAtBase: regionPlayers
        });
      });

      return {
        name: definition.name,
        color: definition.color,
        chunks: definition.chunks,
        areaBlocks: definition.areaBlocks,
        members: definition.members,
        online: onlineNames.length,
        atBase: atBaseNames.length,
        away: Math.max(0, onlineNames.length - atBaseNames.length),
        onlineNames: onlineNames,
        atBaseNames: atBaseNames,
        memberNames: definition.memberNames,
        regions: definition.regions
      };
    });

    teams.sort(function(a, b) {
      return b.online - a.online || b.members - a.members ||
        a.name.localeCompare(b.name);
    });
    bases.sort(function(a, b) {
      return b.chunks - a.chunks || a.team.localeCompare(b.team);
    });

    return ContentService.createTextOutput(JSON.stringify({
      players: players,
      teams: teams,
      bases: bases,
      generatedAt: new Date().toISOString(),
      teamDataUpdatedAt: stored.updatedAt,
      teamDataRefreshed: forceRefresh
    })).setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({
      players: [],
      teams: [],
      bases: [],
      generatedAt: new Date().toISOString(),
      error: String(error && error.message || error)
    })).setMimeType(ContentService.MimeType.JSON);
  }
}
