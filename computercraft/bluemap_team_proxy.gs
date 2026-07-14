// Google Apps Script proxy for BlueMap players + compact FTB Chunks team data.
// Deploy as a Web App with access set to "Anyone".

const BLUEMAP_BASE = "http://172.255.251.68:25581";
const TEAM_CACHE_SECONDS = 120;

function fetchJson_(path) {
  const response = UrlFetchApp.fetch(BLUEMAP_BASE + path, {
    muteHttpExceptions: true,
    followRedirects: true,
    headers: { "Accept": "application/json" }
  });
  const code = response.getResponseCode();
  if (code < 200 || code >= 300) {
    throw new Error(path + " returned HTTP " + code);
  }
  return JSON.parse(response.getContentText());
}

function parseTeams_(markerData) {
  const markerSet = markerData["ftbchunks.claims.2d"];
  if (!markerSet || !markerSet.markers) {
    throw new Error("FTB Chunks 2D marker set was not found");
  }

  const grouped = {};
  Object.keys(markerSet.markers).forEach(function(id) {
    const marker = markerSet.markers[id];
    const label = String(marker.label || "Unknown");
    const detail = String(marker.detail || "");
    const headingMatch = detail.match(/<h3[^>]*>([^<]+)<\/h3>/i);
    const name = headingMatch ? headingMatch[1].trim() :
      label.replace(/\s+.{1,3}\s+Region.*$/i, "").trim();
    const key = name.toLowerCase();
    const chunkMatch = detail.match(/Chunks:<\/div>\s*<div>([\d,]+)/i);
    const chunks = chunkMatch ? Number(chunkMatch[1].replace(/,/g, "")) : 0;

    if (!grouped[key]) {
      const members = [];
      const seen = {};
      const memberRegex = /alt="([^"]+)"/g;
      let match;
      while ((match = memberRegex.exec(detail)) !== null) {
        const member = match[1];
        if (!seen[member.toLowerCase()]) {
          seen[member.toLowerCase()] = true;
          members.push(member);
        }
      }
      grouped[key] = {
        name: name,
        color: marker.lineColor || marker.fillColor || {r:255, g:255, b:255},
        chunks: 0,
        memberNames: members
      };
    }
    grouped[key].chunks += chunks;
  });

  return Object.keys(grouped).map(function(key) {
    const team = grouped[key];
    team.areaBlocks = team.chunks * 256;
    team.members = team.memberNames.length;
    return team;
  });
}

function teamDefinitions_() {
  const cache = CacheService.getScriptCache();
  const cached = cache.get("bluemap-team-definitions-v2");
  if (cached) return JSON.parse(cached);
  const teams = parseTeams_(fetchJson_("/maps/world/live/markers.json"));
  const encoded = JSON.stringify(teams);
  if (encoded.length < 95000) {
    cache.put("bluemap-team-definitions-v2", encoded, TEAM_CACHE_SECONDS);
  }
  return teams;
}

function doGet() {
  try {
    const playerData = fetchJson_("/maps/world/live/players.json");
    const players = Array.isArray(playerData.players) ? playerData.players : [];
    const online = {};
    players.forEach(function(player) {
      online[String(player.name || "").toLowerCase()] = true;
    });

    const teams = teamDefinitions_().map(function(definition) {
      const onlineNames = definition.memberNames.filter(function(name) {
        return online[name.toLowerCase()] === true;
      });
      return {
        name: definition.name,
        color: definition.color,
        chunks: definition.chunks,
        areaBlocks: definition.areaBlocks,
        members: definition.members,
        online: onlineNames.length,
        onlineNames: onlineNames,
        memberNames: definition.memberNames
      };
    });

    teams.sort(function(a, b) {
      return b.online - a.online || b.members - a.members ||
        a.name.localeCompare(b.name);
    });

    return ContentService.createTextOutput(JSON.stringify({
      players: players,
      teams: teams,
      generatedAt: new Date().toISOString()
    })).setMimeType(ContentService.MimeType.JSON);
  } catch (error) {
    return ContentService.createTextOutput(JSON.stringify({
      players: [],
      teams: [],
      error: String(error && error.message || error)
    })).setMimeType(ContentService.MimeType.JSON);
  }
}
