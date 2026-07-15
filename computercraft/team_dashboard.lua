local launchArgs = { ... }
local localMode = tostring(launchArgs[1] or ""):lower() == "local"
local localCacheFile = ".base_control_live.json"

local proxyUrls = {
  "https://script.google.com/macros/s/AKfycbx11MizOXaAJ-ScN7C0-7Tuo2mjEu-urxRAnNAASwkQSa9iTUTy50JPuq8pEnZDs0F4uw/exec",
  "https://script.google.com/macros/s/AKfycbwSsBb4SokTdVDhIUv0zTJzcMT8o_hJyzo7ziEdlMOYK8gACLHOKyQPZbpPnzTESiR5Jg/exec",
  "https://script.google.com/macros/s/AKfycbyXcO7DJgloCLhteQixcPabIXHQTANvCyrMaOrLWjava--_iqFB-ItfgLTwbBpHzOV3/exec"
}
local proxyNames = { "G1", "G2", "G3" }
local activeProxy = 1
local profileApiUrl = "https://api.ashcon.app/mojang/v2/user/"
local dashboardVersion = "18"
local playerRefreshSeconds = 6
local teamRefreshSeconds = 600
local animationSeconds = 0.5
local lastSeenFile = ".team_dashboard_last_seen"
local earthBlocksPerDegree = 204.8

local palette = {
  colors.white, colors.orange, colors.magenta, colors.lightBlue,
  colors.yellow, colors.lime, colors.pink, colors.gray,
  colors.lightGray, colors.cyan, colors.purple, colors.blue,
  colors.brown, colors.green, colors.red, colors.black
}

local function writeAt(target, x, y, value, foreground, background)
  local width, height = target.getSize()
  if y < 1 or y > height or x > width then return end
  target.setCursorPos(math.max(1, x), y)
  if foreground then target.setTextColor(foreground) end
  if background then target.setBackgroundColor(background) end
  target.write(tostring(value):sub(1, math.max(0, width - x + 1)))
end

local function nearestColor(target, rgb)
  if type(rgb) ~= "table" then return colors.white end
  local red = (tonumber(rgb.r) or 255) / 255
  local green = (tonumber(rgb.g) or 255) / 255
  local blue = (tonumber(rgb.b) or 255) / 255
  local best, bestDistance = colors.white, math.huge
  for _, candidate in ipairs(palette) do
    local r, g, b = target.getPaletteColor(candidate)
    local distance = (red-r)^2 + (green-g)^2 + (blue-b)^2
    if distance < bestDistance then
      best, bestDistance = candidate, distance
    end
  end
  if best == colors.black then return colors.gray end
  return best
end

local function compactNumber(value)
  value = tonumber(value) or 0
  if value >= 1000000 then return string.format("%.1fM", value / 1000000) end
  if value >= 1000 then return string.format("%.1fK", value / 1000) end
  return tostring(math.floor(value))
end

local function fetchData()
  local proxyUrl = proxyUrls[activeProxy]
  local separator = proxyUrl:find("?", 1, true) and "&" or "?"
  local cloudflareMode = proxyUrl:find("workers.dev", 1, true) and "mode=teams&" or ""
  local url = proxyUrl .. separator .. cloudflareMode .. "dashboard=" ..
    tostring(os.epoch and os.epoch("utc") or math.random(1, 999999))
  local ok, response, err = pcall(http.get, {
    url=url, redirect=true, timeout=12,
    headers={ ["Accept"]="application/json", ["Cache-Control"]="no-cache" }
  })
  if not ok then return nil, tostring(response) end
  if not response then return nil, tostring(err or "request failed") end
  local body = response.readAll()
  response.close()
  local data = textutils.unserializeJSON(body)
  if type(data) ~= "table" then return nil, "Proxy returned invalid JSON" end
  if data.error then return nil, "Proxy: " .. tostring(data.error) end
  if type(data.teams) ~= "table" then
    return nil, "Proxy has no teams field. Deploy bluemap_team_proxy.gs first."
  end
  table.sort(data.teams, function(a, b)
    local ao, bo = tonumber(a.online) or 0, tonumber(b.online) or 0
    if ao ~= bo then return ao > bo end
    local am, bm = tonumber(a.members) or 0, tonumber(b.members) or 0
    if am ~= bm then return am > bm end
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
  return data
end

local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local target = monitor or term
if monitor then monitor.setTextScale(1) end

local data, lastError, page = nil, nil, 1
local lastPlayerUpdate = nil
local lastHubUpdate = 0
local viewMode = "list"
local awayPage = 1
local selectedName, detailPage = nil, 1
local rowTeams = {}
local rowPlayers = {}
local rowAwayPlayers = {}
local mapCells = {}
local selectedPlayerName, playerProfile, playerError = nil, nil, nil
local profileCache = {}
local lastSeen = {}
local lastSeenSavedAt = 0
local animationFrame = 0
local draw
local requestProfile

local function loadLastSeen()
  if not fs.exists(lastSeenFile) then return end
  local file = fs.open(lastSeenFile, "r")
  if not file then return end
  local saved = textutils.unserializeJSON(file.readAll())
  file.close()
  if type(saved) == "table" then lastSeen = saved end
end

local function saveLastSeen()
  local temporary = lastSeenFile .. ".tmp"
  local file = fs.open(temporary, "w")
  if not file then return end
  file.write(textutils.serializeJSON(lastSeen))
  file.close()
  if fs.exists(lastSeenFile) then fs.delete(lastSeenFile) end
  fs.move(temporary, lastSeenFile)
end

local function rememberOnlinePlayers(newData)
  if not os.epoch then return end
  local now = os.epoch("utc")
  local changed = false
  for _, team in ipairs(type(newData.teams) == "table" and newData.teams or {}) do
    for _, name in ipairs(type(team.onlineNames) == "table" and team.onlineNames or {}) do
      local key = tostring(name):lower()
      lastSeen[key] = { name=tostring(name), time=now }
      changed = true
    end
  end
  if changed and now - lastSeenSavedAt >= 30000 then
    saveLastSeen()
    lastSeenSavedAt = now
  end
end

local function playerIsOnline(team, name)
  if not team or not name then return false end
  for _, onlineName in ipairs(type(team.onlineNames) == "table" and team.onlineNames or {}) do
    if tostring(onlineName):lower() == tostring(name):lower() then return true end
  end
  return false
end

local function lastSeenText(name)
  local entry = lastSeen[tostring(name or ""):lower()]
  if type(entry) ~= "table" or not tonumber(entry.time) or not os.epoch then
    return "NOT OBSERVED YET"
  end
  local seconds = math.max(0, math.floor((os.epoch("utc") - tonumber(entry.time)) / 1000))
  if seconds < 60 then return "JUST NOW" end
  if seconds < 3600 then return math.floor(seconds / 60) .. "m AGO" end
  if seconds < 86400 then return math.floor(seconds / 3600) .. "h AGO" end
  if seconds < 604800 then return math.floor(seconds / 86400) .. "d AGO" end
  return os.date("!%Y-%m-%d %H:%M UTC", math.floor(tonumber(entry.time) / 1000))
end

loadLastSeen()

local function playClick(kind)
  if not speaker then return end
  if kind == "open" then
    pcall(speaker.playNote, "pling", 0.45, 14)
  elseif kind == "back" then
    pcall(speaker.playNote, "harp", 0.40, 8)
  else
    pcall(speaker.playNote, "hat", 0.35, 10)
  end
end

local function drawAnimatedLine(y, accent)
  local width = target.getSize()
  writeAt(target, 1, y, string.rep("-", width), colors.gray, colors.black)
  local length = math.min(6, width)
  local start = animationFrame % math.max(1, width) + 1
  local firstLength = math.min(length, width - start + 1)
  writeAt(target, start, y, string.rep("=", firstLength), accent, colors.black)
  if firstLength < length then
    writeAt(target, 1, y, string.rep("=", length - firstLength), accent, colors.black)
  end
end

local function drawBackButton()
  local backColors = { colors.gray, colors.cyan, colors.purple, colors.orange }
  local index = math.floor(animationFrame / 5) % #backColors + 1
  local background = backColors[index]
  local foreground = background == colors.gray and colors.white or colors.black
  writeAt(target, 1, 1, "<  BACK  ", foreground, background)
end

local function drawPageButtons(y, current, total)
  writeAt(target, 1, y, "< PREV ", colors.white, current > 1 and colors.gray or colors.black)
  writeAt(target, 8, y, " NEXT > ", colors.white, current < total and colors.gray or colors.black)
  local width = target.getSize()
  local status = tostring(current) .. "/" .. tostring(total)
  writeAt(target, math.max(17, width - #status + 1), y, status, colors.lightGray, colors.black)
end

local function selectedTeam()
  if not data or not selectedName then return nil end
  for _, team in ipairs(data.teams) do
    if tostring(team.name) == selectedName then return team end
  end
end

local function selectedPlayerData(name)
  if not data or type(data.players) ~= "table" then return nil end
  for _, player in ipairs(data.players) do
    if tostring(player.name or ""):lower() == tostring(name or ""):lower() then
      return player
    end
  end
end

local function teamByName(name)
  if not data or type(data.teams) ~= "table" then return nil end
  for _, team in ipairs(data.teams) do
    if tostring(team.name or ""):lower() == tostring(name or ""):lower() then return team end
  end
end

local function approximateEarthRegion(position)
  if type(position) ~= "table" then return "UNKNOWN REGION" end
  local x, z = tonumber(position.x), tonumber(position.z)
  if not x or not z then return "UNKNOWN REGION" end
  local longitude = x / earthBlocksPerDegree
  local latitude = -z / earthBlocksPerDegree

  if latitude <= -60 then return "ANTARCTICA" end
  if latitude >= 72 then return "ARCTIC" end
  if latitude >= 7 and latitude <= 84 and longitude >= -170 and longitude <= -50 then
    return "NORTH AMERICA"
  end
  if latitude >= -56 and latitude <= 14 and longitude >= -82 and longitude <= -34 then
    return "SOUTH AMERICA"
  end
  if latitude >= -35 and latitude <= 37 and longitude >= -18 and longitude <= 52 and
      not (longitude > 32 and latitude > 22) then
    return "AFRICA"
  end
  if latitude >= 35 and latitude <= 72 and longitude >= -25 and longitude <= 60 and
      not (longitude > 42 and latitude < 55) then
    return "EUROPE"
  end
  if latitude >= -50 and latitude <= 8 and longitude >= 105 and longitude <= 180 then
    return "OCEANIA"
  end
  if latitude >= -12 and latitude <= 80 and longitude >= 25 and longitude <= 180 then
    return "ASIA"
  end
  if latitude <= -45 then return "SOUTHERN OCEAN" end
  if latitude >= 66 then return "ARCTIC OCEAN" end
  if latitude < 25 and longitude >= 20 and longitude <= 120 then return "INDIAN OCEAN" end
  if longitude >= -75 and longitude <= 25 then return "ATLANTIC OCEAN" end
  return "PACIFIC OCEAN"
end

local function currentLocation(player, compact)
  if type(player) ~= "table" then return "UNKNOWN", colors.gray end
  if player.locationStatus == "OWN_BASE" or player.inOwnBase == true then
    return "OWN BASE", colors.lime
  end
  if player.locationStatus == "FOREIGN_BASE" and player.insideTeam then
    local location = (compact and "" or "IN ") .. tostring(player.insideTeam)
    local region = tonumber(player.insideRegion)
    if region then location = location .. " BASE #" .. tostring(math.floor(region)) end
    return location, colors.red
  end
  local region = approximateEarthRegion(player.position)
  return (compact and "WILD / " or "WILDERNESS / ") .. region, colors.orange
end

local function drawAwayTeamLegend(players, width)
  local listed, seen = {}, {}
  for _, player in ipairs(players) do
    local name = tostring(player.team or "UNKNOWN")
    local key = name:lower()
    if not seen[key] then
      seen[key] = true
      listed[#listed + 1] = { name=name, team=teamByName(name) }
    end
  end
  table.sort(listed, function(a, b) return a.name:lower() < b.name:lower() end)

  writeAt(target, 2, 3, "ORIGIN", colors.gray, colors.black)
  local x, y = 10, 3
  for index, entry in ipairs(listed) do
    local label = "[" .. entry.name:sub(1, 10) .. "]"
    if x + #label - 1 > width then x, y = 2, y + 1 end
    if y > 4 then
      local remaining = #listed - index + 1
      writeAt(target, math.max(2, width - 5), 4, "+" .. tostring(remaining), colors.lightGray, colors.black)
      break
    end
    local teamColor = entry.team and nearestColor(target, entry.team.color) or colors.white
    if teamColor == colors.black then teamColor = colors.gray end
    writeAt(target, x, y, label, teamColor, colors.black)
    x = x + #label + 1
  end
end

local function awayPlayers()
  local result = {}
  if not data or type(data.players) ~= "table" then return result end
  for _, player in ipairs(data.players) do
    if player.team and player.inOwnBase == false then result[#result + 1] = player end
  end
  table.sort(result, function(a, b)
    local al = tostring(currentLocation(a, true)):lower()
    local bl = tostring(currentLocation(b, true)):lower()
    if al ~= bl then return al < bl end
    return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
  end)
  return result
end

local function accountAge(createdAt)
  local year, month, day = tostring(createdAt or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
  if not year then return nil end
  local now = os.date("*t")
  local age = now.year - tonumber(year)
  if now.month < tonumber(month) or
      (now.month == tonumber(month) and now.day < tonumber(day)) then age = age - 1 end
  return math.max(0, age)
end

local function fetchProfile(name)
  local cached = profileCache[name:lower()]
  local now = os.clock()
  if cached and now - cached.time < 300 then return cached.data, cached.error end
  local ok, response, err = pcall(http.get, {
    url=profileApiUrl .. textutils.urlEncode(name), redirect=true, timeout=12,
    headers={ ["Accept"]="application/json", ["User-Agent"]="CC-Nations-Dashboard/1.0" }
  })
  if not ok then return nil, tostring(response) end
  if not response then return nil, tostring(err or "profile request failed") end
  local body = response.readAll()
  response.close()
  local profile = textutils.unserializeJSON(body)
  if type(profile) ~= "table" or not profile.uuid then
    local message = type(profile) == "table" and profile.reason or "invalid profile response"
    profileCache[name:lower()] = { time=now, error=tostring(message) }
    return nil, tostring(message)
  end
  profileCache[name:lower()] = { time=now, data=profile }
  return profile
end

local function openPlayer(name)
  selectedPlayerName, playerProfile, playerError = name, nil, nil
  draw()
  requestProfile(name)
end

local function drawHeader(title, accent)
  local width, height = target.getSize()
  target.setBackgroundColor(colors.black)
  target.clear()
  writeAt(target, 2, 1, title .. "  v" .. dashboardVersion, colors.white, colors.black)
  if width > 42 then
    local liveAge = lastPlayerUpdate and os.epoch and
      math.max(0, math.floor((os.epoch("utc") - lastPlayerUpdate) / 1000)) or nil
    writeAt(target, width - 20, 1,
      (liveAge and ("LIVE " .. tostring(liveAge) .. "s") or "SYNC...") .. " " ..
        (localMode and "HUB" or tostring(proxyNames[activeProxy] or ("P" .. activeProxy))),
      liveAge and liveAge <= 5 and colors.lime or colors.orange, colors.black)
  end
  if width > 30 then
    writeAt(target, width - 7, 1, os.date("%H:%M"), colors.gray, colors.black)
  end
  drawAnimatedLine(2, accent or colors.cyan)
end

local function drawRanking()
  local width, height = target.getSize()
  drawHeader("NATIONS  /  LIVE RANKING", colors.cyan)
  rowTeams = {}

  if not data then
    writeAt(target, 2, 4, "BLUEMAP CONNECTION ERROR", colors.red, colors.black)
    writeAt(target, 2, 6, lastError or "No data", colors.orange, colors.black)
    writeAt(target, 2, 8, "Retrying automatically...", colors.lightGray, colors.black)
    return
  end

  local rows = math.max(1, height - 5)
  local pageCount = math.max(1, math.ceil(#data.teams / rows))
  page = math.max(1, math.min(page, pageCount))
  local first = (page - 1) * rows + 1

  writeAt(target, 1, 3, "#  TEAM", colors.gray, colors.black)
  writeAt(target, math.max(14, width - 8), 3, "ONLINE", colors.gray, colors.black)

  for row = 1, rows do
    local rank = first + row - 1
    local team = data.teams[rank]
    if not team then break end
    local y = row + 3
    rowTeams[y] = team
    local teamColor = nearestColor(target, team.color)
    local onlineText = tostring(team.online or 0) .. "/" .. tostring(team.members or 0)
    local onlineX = math.max(14, width - 8)
    local nameWidth = math.max(3, onlineX - 6)
    local rankColor = rank == 1 and colors.yellow or
      rank == 2 and colors.lightGray or rank == 3 and colors.orange or colors.gray
    writeAt(target, 1, y, string.format("%2d", rank), rankColor, colors.black)
    writeAt(target, 4, y, "|", teamColor, colors.black)
    writeAt(target, 6, y, tostring(team.name or "?"):sub(1, nameWidth), teamColor, colors.black)
    writeAt(target, onlineX, y, onlineText,
      (tonumber(team.online) or 0) > 0 and colors.lime or colors.gray, colors.black)
  end

  drawPageButtons(height, page, pageCount)
  if width >= 25 then writeAt(target, 18, height, " MAP > ", colors.black, colors.cyan) end
  if width >= 35 then
    writeAt(target, 26, height, " AWAY > ", colors.black,
      #awayPlayers() > 0 and colors.orange or colors.gray)
  end
end

local function drawMap()
  local width, height = target.getSize()
  drawHeader("NATIONS  /  BASE OVERVIEW", colors.lime)
  rowTeams = {}
  mapCells = {}

  local bases = data and type(data.bases) == "table" and data.bases or {}
  if #bases == 0 then
    writeAt(target, 2, 5, "NO BASE DATA", colors.orange, colors.black)
    writeAt(target, 2, 7, "Deploy the new proxy code", colors.lightGray, colors.black)
    writeAt(target, 1, height, "< LIST", colors.black, colors.cyan)
    return
  end

  local primaryBases = {}
  for _, base in ipairs(bases) do
    local key = tostring(base.team or ""):lower()
    if not primaryBases[key] or
        (tonumber(base.chunks) or 0) > (tonumber(primaryBases[key].chunks) or 0) then
      primaryBases[key] = base
    end
  end
  local visibleBases = {}
  for _, base in pairs(primaryBases) do visibleBases[#visibleBases + 1] = base end

  local left, right = 2, math.max(2, width - 1)
  local top, bottom = 4, math.max(4, height - 2)
  local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
  for _, base in ipairs(visibleBases) do
    minX = math.min(minX, tonumber(base.minX) or tonumber(base.x) or 0)
    maxX = math.max(maxX, tonumber(base.maxX) or tonumber(base.x) or 0)
    minZ = math.min(minZ, tonumber(base.minZ) or tonumber(base.z) or 0)
    maxZ = math.max(maxZ, tonumber(base.maxZ) or tonumber(base.z) or 0)
  end
  local spanX, spanZ = math.max(1, maxX - minX), math.max(1, maxZ - minZ)
  local plotWidth, plotHeight = math.max(1, right - left), math.max(1, bottom - top)
  local function screenX(value)
    return math.max(left, math.min(right,
      left + math.floor(((tonumber(value) or minX) - minX) / spanX * plotWidth + 0.5)))
  end
  local function screenY(value)
    return math.max(top, math.min(bottom,
      top + math.floor(((tonumber(value) or minZ) - minZ) / spanZ * plotHeight + 0.5)))
  end

  writeAt(target, 2, 3, "[N] AT BASE   !N AWAY   . OFFLINE", colors.gray, colors.black)

  -- Quiet background: only one small dot for each offline team's main base.
  for _, base in ipairs(visibleBases) do
    local team = teamByName(base.team)
    if not team or (tonumber(team.online) or 0) == 0 then
      local x, y = screenX(base.x), screenY(base.z)
      mapCells[y] = mapCells[y] or {}
      writeAt(target, x, y, ".", nearestColor(target, base.color), colors.black)
      mapCells[y][x] = base
    end
  end

  -- Active teams are drawn last and therefore stay readable.
  for _, base in ipairs(visibleBases) do
    local team = teamByName(base.team)
    if team and (tonumber(team.online) or 0) > 0 then
      local centerX, centerY = screenX(base.x), screenY(base.z)
      local label = "[" .. tostring(tonumber(team.atBase) or 0) .. "]"
      if (tonumber(team.away) or 0) > 0 then label = label .. "!" .. tostring(team.away) end
      local x1 = math.max(left, math.min(right - #label + 1, centerX - math.floor(#label / 2)))
      local baseColor = nearestColor(target, base.color)
      writeAt(target, x1, centerY, label,
        (tonumber(team.away) or 0) > 0 and colors.orange or colors.white, baseColor)
      mapCells[centerY] = mapCells[centerY] or {}
      for x = x1, math.min(right, x1 + #label - 1) do mapCells[centerY][x] = base end
    end
  end

  local totalAtBase, totalOnline = 0, 0
  for _, team in ipairs(type(data.teams) == "table" and data.teams or {}) do
    totalAtBase = totalAtBase + (tonumber(team.atBase) or 0)
    totalOnline = totalOnline + (tonumber(team.online) or 0)
  end
  writeAt(target, 1, height, "< LIST ", colors.black, colors.cyan)
  writeAt(target, 9, height, " AWAY > ", colors.black,
    #awayPlayers() > 0 and colors.orange or colors.gray)
  writeAt(target, 19, height,
    "AT BASE " .. totalAtBase .. " / ONLINE " .. totalOnline, colors.lightGray, colors.black)
end

local function drawAwayPlayers()
  local width, height = target.getSize()
  drawHeader("NATIONS  /  AWAY LOCATIONS", colors.orange)
  rowTeams = {}
  mapCells = {}
  rowAwayPlayers = {}
  local players = awayPlayers()
  local rows = math.max(1, height - 6)
  local pages = math.max(1, math.ceil(#players / rows))
  awayPage = math.max(1, math.min(awayPage, pages))
  local first = (awayPage - 1) * rows + 1

  drawAwayTeamLegend(players, width)
  local locationX = width >= 42 and 18 or math.max(12, math.floor(width * 0.44))
  local coordinatesX = width >= 52 and math.max(locationX + 18, width - 16) or nil
  local locationWidth = (coordinatesX or (width + 1)) - locationX - 1
  writeAt(target, 2, 5, "PLAYER", colors.gray, colors.black)
  writeAt(target, locationX, 5, "CURRENT LOCATION", colors.gray, colors.black)
  if coordinatesX then writeAt(target, coordinatesX, 5, "X / Z", colors.gray, colors.black) end

  if #players == 0 then
    writeAt(target, 2, 6, "ALL ONLINE MEMBERS ARE AT BASE", colors.lime, colors.black)
  end
  for row = 1, rows do
    local player = players[first + row - 1]
    if not player then break end
    local y = row + 5
    rowAwayPlayers[y] = player
    local position = type(player.position) == "table" and player.position or {}
    local coordinates = tostring(math.floor(tonumber(position.x) or 0)) .. " / " ..
      tostring(math.floor(tonumber(position.z) or 0))
    local location, locationColor = currentLocation(player, true)
    local originTeam = teamByName(player.team)
    local nameColor = originTeam and nearestColor(target, originTeam.color) or colors.white
    if nameColor == colors.black then nameColor = colors.gray end
    writeAt(target, 2, y, tostring(player.name or "?"):sub(1, math.max(3, locationX - 4)),
      nameColor, colors.black)
    writeAt(target, locationX, y, location:sub(1, math.max(3, locationWidth)),
      locationColor, colors.black)
    if coordinatesX then
      writeAt(target, coordinatesX, y, coordinates, colors.lightGray, colors.black)
    end
  end

  writeAt(target, 1, height, "< LIST ", colors.black, colors.cyan)
  writeAt(target, 9, height, " MAP > ", colors.black, colors.lime)
  writeAt(target, 18, height, "<", colors.white, awayPage > 1 and colors.gray or colors.black)
  writeAt(target, 22, height, ">", colors.white, awayPage < pages and colors.gray or colors.black)
  local status = tostring(awayPage) .. "/" .. tostring(pages) .. "  " .. #players .. " AWAY"
  writeAt(target, math.max(25, width - #status + 1), height, status, colors.orange, colors.black)
end

local function drawDetails(team)
  local width, height = target.getSize()
  local teamColor = nearestColor(target, team.color)
  rowPlayers = {}
  target.setBackgroundColor(colors.black)
  target.clear()
  drawBackButton()
  writeAt(target, 12, 1, "TEAM DETAILS", colors.white, colors.black)
  drawAnimatedLine(2, teamColor)
  writeAt(target, 2, 3, tostring(team.name or "UNKNOWN"), teamColor, colors.black)
  writeAt(target, 2, 5,
    string.format("ONLINE  %d / %d", tonumber(team.online) or 0, tonumber(team.members) or 0),
    (tonumber(team.online) or 0) > 0 and colors.lime or colors.gray, colors.black)
  if team.atBase ~= nil and width >= 42 then
    writeAt(target, 22, 6,
      "AT BASE " .. tostring(team.atBase or 0) .. "  AWAY " .. tostring(team.away or 0),
      (tonumber(team.atBase) or 0) > 0 and colors.lime or colors.gray, colors.black)
  end
  local memberHeadingY = 8
  if width >= 42 then
    writeAt(target, width - 17, 5,
      "AREA  " .. compactNumber(team.areaBlocks) .. " blocks", colors.yellow, colors.black)
    writeAt(target, 2, 6, "CLAIMS  " .. tostring(team.chunks or 0) .. " chunks", colors.lightGray, colors.black)
  else
    writeAt(target, 2, 6,
      "AREA    " .. compactNumber(team.areaBlocks) .. " blocks", colors.yellow, colors.black)
    writeAt(target, 2, 7, "CLAIMS  " .. tostring(team.chunks or 0) .. " chunks", colors.lightGray, colors.black)
    memberHeadingY = 9
  end
  writeAt(target, 2, memberHeadingY, "MEMBERS", colors.white, colors.black)

  local online = {}
  for _, name in ipairs(type(team.onlineNames) == "table" and team.onlineNames or {}) do
    online[tostring(name):lower()] = true
  end
  local members = {}
  for _, name in ipairs(type(team.memberNames) == "table" and team.memberNames or {}) do
    members[#members + 1] = tostring(name)
  end
  table.sort(members, function(a, b)
    local ao, bo = online[a:lower()] and 1 or 0, online[b:lower()] and 1 or 0
    if ao ~= bo then return ao > bo end
    return a:lower() < b:lower()
  end)

  local memberRows = math.max(1, height - memberHeadingY - 1)
  local pages = math.max(1, math.ceil(#members / memberRows))
  detailPage = math.max(1, math.min(detailPage, pages))
  local first = (detailPage - 1) * memberRows + 1
  for row = 1, memberRows do
    local name = members[first + row - 1]
    if not name then break end
    local isOnline = online[name:lower()] == true
    local y = memberHeadingY + row
    rowPlayers[y] = name
    writeAt(target, 2, y, isOnline and ">" or "-",
      isOnline and colors.lime or colors.gray, colors.black)
    writeAt(target, 5, y, name,
      isOnline and colors.white or colors.lightGray, colors.black)
    local livePlayer = isOnline and selectedPlayerData(name) or nil
    local memberStatus = not isOnline and "OFFLINE" or
      (livePlayer and livePlayer.inOwnBase == false and "AWAY" or "BASE")
    writeAt(target, math.max(8, width - 8), y, memberStatus,
      memberStatus == "AWAY" and colors.orange or
        (isOnline and colors.lime or colors.gray), colors.black)
  end
  drawPageButtons(height, detailPage, pages)
end

local function drawPlayerProfile(team)
  local width, height = target.getSize()
  local teamColor = team and nearestColor(target, team.color) or colors.cyan
  target.setBackgroundColor(colors.black)
  target.clear()
  drawBackButton()
  writeAt(target, 12, 1, "PLAYER PROFILE", colors.white, colors.black)
  drawAnimatedLine(2, teamColor)
  writeAt(target, 2, 3, selectedPlayerName or "UNKNOWN", teamColor, colors.black)
  writeAt(target, 2, 4, "ORIGIN     " .. tostring(team and team.name or "UNKNOWN"),
    teamColor, colors.black)

  local onlineNow = playerIsOnline(team, selectedPlayerName)
  local livePlayer = selectedPlayerData(selectedPlayerName)
  writeAt(target, 2, 5, "STATUS     " .. (onlineNow and "ONLINE NOW" or "OFFLINE"),
    onlineNow and colors.lime or colors.gray, colors.black)
  writeAt(target, 2, 6, "LAST SEEN  " .. (onlineNow and "ONLINE NOW" or lastSeenText(selectedPlayerName)),
    onlineNow and colors.lime or colors.lightBlue, colors.black)
  if livePlayer then
    local location, locationColor = currentLocation(livePlayer, false)
    writeAt(target, 2, 7, "LOCATION   " .. location,
      locationColor, colors.black)
    local position = type(livePlayer.position) == "table" and livePlayer.position or {}
    writeAt(target, 2, 8,
      "POSITION   X " .. tostring(math.floor(tonumber(position.x) or 0)) ..
      "  Z " .. tostring(math.floor(tonumber(position.z) or 0)), colors.lightGray, colors.black)
  end

  if not playerProfile and not playerError then
    writeAt(target, 2, 10, "LOADING PROFILE...", colors.yellow, colors.black)
    return
  end
  if playerError then
    writeAt(target, 2, 10, "PROFILE UNAVAILABLE", colors.red, colors.black)
    writeAt(target, 2, 12, playerError, colors.orange, colors.black)
    writeAt(target, 1, height, "< BACK TO TEAM", colors.lightGray, colors.black)
    return
  end

  local created = playerProfile.created_at
  local age = accountAge(created)
  writeAt(target, 2, 10, "CURRENT  " .. tostring(playerProfile.username or selectedPlayerName),
    colors.white, colors.black)
  writeAt(target, 2, 11, "CREATED  " .. (created and tostring(created) or "UNKNOWN"),
    created and colors.lime or colors.gray, colors.black)
  writeAt(target, 2, 12, "AGE      " .. (age and (tostring(age) .. " years") or "UNKNOWN"),
    age and colors.lightBlue or colors.gray, colors.black)
  writeAt(target, 2, 13, "UUID     " .. tostring(playerProfile.uuid or "UNKNOWN"),
    colors.lightGray, colors.black)
  writeAt(target, 2, 15, "KNOWN USERNAMES", colors.white, colors.black)

  local history = type(playerProfile.username_history) == "table" and
    playerProfile.username_history or {}
  local rows = math.max(1, height - 16)
  if #history == 0 then
    writeAt(target, 2, 16, "No public history available", colors.gray, colors.black)
  else
    for index = 1, math.min(#history, rows) do
      local item = history[index]
      local username = type(item) == "table" and item.username or tostring(item)
      local changed = type(item) == "table" and item.changed_at or nil
      writeAt(target, 2, index + 15, index .. ". " .. tostring(username),
        index == #history and colors.white or colors.lightGray, colors.black)
      if changed and width > 38 then
        writeAt(target, width - 11, index + 15, tostring(changed):sub(1, 10), colors.gray, colors.black)
      end
    end
  end
  writeAt(target, 1, height, "< BACK TO TEAM", colors.lightGray, colors.black)
end

draw = function()
  local team = selectedTeam()
  if selectedPlayerName then drawPlayerProfile(team)
  elseif team then drawDetails(team)
  elseif viewMode == "map" then drawMap()
  elseif viewMode == "away" then drawAwayPlayers()
  else drawRanking() end
end

local function animate()
  animationFrame = animationFrame + 1
  local team = selectedTeam()
  if team then
    drawBackButton()
    drawAnimatedLine(2, nearestColor(target, team.color))
  elseif viewMode == "map" then
    drawAnimatedLine(2, colors.lime)
  elseif viewMode == "away" then
    drawAnimatedLine(2, colors.orange)
  else
    drawAnimatedLine(2, colors.cyan)
  end
end

local pendingRequests = { players=false, teams=false }
local requestKinds = {}
local profileRequests = {}

local function rotateProxy(failedProxy)
  if #proxyUrls > 1 and activeProxy == failedProxy then
    activeProxy = activeProxy % #proxyUrls + 1
  end
end

local function sortTeams()
  if not data or type(data.teams) ~= "table" then return end
  table.sort(data.teams, function(a, b)
    local ao, bo = tonumber(a.online) or 0, tonumber(b.online) or 0
    if ao ~= bo then return ao > bo end
    local am, bm = tonumber(a.members) or 0, tonumber(b.members) or 0
    if am ~= bm then return am > bm end
    return tostring(a.name):lower() < tostring(b.name):lower()
  end)
end

local function applyPlayers(players)
  if not data or type(data.teams) ~= "table" or type(players) ~= "table" then return end
  data.players = players
  local teams = {}
  for _, team in ipairs(data.teams) do
    local key = tostring(team.name or ""):lower()
    teams[key] = team
    team.onlineNames, team.atBaseNames = {}, {}
    team.online, team.atBase, team.away = 0, 0, 0
  end
  for _, player in ipairs(players) do
    local team = teams[tostring(player.team or ""):lower()]
    if team then
      team.online = team.online + 1
      team.onlineNames[#team.onlineNames + 1] = tostring(player.name or "?")
      if player.inOwnBase == true then
        team.atBase = team.atBase + 1
        team.atBaseNames[#team.atBaseNames + 1] = tostring(player.name or "?")
      end
    end
  end
  for _, team in ipairs(data.teams) do team.away = math.max(0, team.online - team.atBase) end

  if type(data.bases) == "table" then
    for _, base in ipairs(data.bases) do
      local team = teams[tostring(base.team or ""):lower()]
      base.online = team and team.online or 0
      base.atBase, base.playersAtBase = 0, {}
      for _, player in ipairs(players) do
        if tostring(player.team or ""):lower() == tostring(base.team or ""):lower() and
            player.inOwnBase == true and
            tonumber(player.ownBaseRegion) == tonumber(base.region) then
          base.atBase = base.atBase + 1
          base.playersAtBase[#base.playersAtBase + 1] = tostring(player.name or "?")
        end
      end
    end
  end
  sortTeams()
  rememberOnlinePlayers(data)
end

local function requestProxy(kind)
  if pendingRequests[kind] then return end
  local proxyIndex = activeProxy
  local proxyUrl = proxyUrls[proxyIndex]
  local separator = proxyUrl:find("?", 1, true) and "&" or "?"
  local stamp = tostring(os.epoch and os.epoch("utc") or math.random(1, 999999))
  local modeParameter = proxyUrl:find("workers.dev", 1, true) and
    ("mode=" .. kind .. "&") or ""
  local url = proxyUrl .. separator .. modeParameter .. "dashboard=" .. stamp
  local callOk, ok, err = pcall(http.request, {
    url=url,
    redirect=true,
    timeout=kind == "players" and 10 or 35,
    headers={ ["Accept"]="application/json", ["Cache-Control"]="no-cache" }
  })
  if callOk and ok then
    pendingRequests[kind] = true
    requestKinds[url] = { kind=kind, proxy=proxyIndex }
  else
    lastError = tostring((not callOk and ok) or err or (kind .. " request failed"))
    rotateProxy(proxyIndex)
  end
end

requestProfile = function(name)
  local key = tostring(name):lower()
  local cached = profileCache[key]
  local now = os.clock()
  if cached and now - cached.time < 300 then
    playerProfile, playerError = cached.data, cached.error
    draw()
    return
  end
  local url = profileApiUrl .. textutils.urlEncode(name)
  local ok, started, err = pcall(http.request, {
    url=url,
    redirect=true,
    timeout=12,
    headers={ ["Accept"]="application/json", ["User-Agent"]="CC-Nations-Dashboard/2.0" }
  })
  if not ok or not started then
    playerError = tostring((not ok and started) or err or "profile request failed")
    profileCache[key] = { time=now, error=playerError }
    draw()
    return
  end
  profileRequests[url] = tostring(name)
end

local function handleProfileSuccess(url, response)
  local name = profileRequests[url]
  profileRequests[url] = nil
  local body = response.readAll()
  response.close()
  local profile = textutils.unserializeJSON(body)
  local now = os.clock()
  local profileData, profileError
  if type(profile) ~= "table" or not profile.uuid then
    profileError = type(profile) == "table" and
      tostring(profile.reason or "invalid profile response") or "invalid profile response"
    profileCache[tostring(name):lower()] = { time=now, error=profileError }
  else
    profileData = profile
    profileCache[tostring(name):lower()] = { time=now, data=profileData }
  end
  if selectedPlayerName and tostring(selectedPlayerName):lower() == tostring(name):lower() then
    playerProfile, playerError = profileData, profileError
    draw()
  end
end

local function handleProfileFailure(url, err, response)
  local name = profileRequests[url]
  profileRequests[url] = nil
  if response then pcall(response.close) end
  if not name then return end
  local message = tostring(err or "profile request failed")
  profileCache[tostring(name):lower()] = { time=os.clock(), error=message }
  if selectedPlayerName and tostring(selectedPlayerName):lower() == tostring(name):lower() then
    playerProfile, playerError = nil, message
    draw()
  end
end

local function handleProxySuccess(url, response)
  local request = requestKinds[url]
  local kind = type(request) == "table" and request.kind or request
  local proxyIndex = type(request) == "table" and request.proxy or activeProxy
  requestKinds[url] = nil
  local body = response.readAll()
  response.close()
  local payload = textutils.unserializeJSON(body)
  if not kind then kind = type(payload) == "table" and type(payload.teams) == "table" and "teams" or "players" end
  pendingRequests[kind] = false
  if type(payload) ~= "table" then
    lastError = "Proxy returned invalid JSON"
    rotateProxy(proxyIndex)
  elseif payload.error then
    lastError = "Proxy: " .. tostring(payload.error)
    rotateProxy(proxyIndex)
  elseif kind == "teams" then
    if type(payload.teams) ~= "table" then
      lastError = "Proxy has no teams field. Deploy the new proxy code."
      rotateProxy(proxyIndex)
    else
      data, lastError = payload, nil
      lastPlayerUpdate = os.epoch and os.epoch("utc") or nil
      sortTeams()
      rememberOnlinePlayers(data)
    end
  elseif type(payload.players) == "table" then
    local hadTeamData = data and type(data.teams) == "table"
    applyPlayers(payload.players)
    lastPlayerUpdate = os.epoch and os.epoch("utc") or nil
    if hadTeamData then lastError = nil
    else lastError = lastError or "Waiting for team data" end
  else
    lastError = "Proxy has no players field"
    rotateProxy(proxyIndex)
  end
  draw()
end

local function handleProxyFailure(url, err, response)
  local request = requestKinds[url]
  local kind = (type(request) == "table" and request.kind or request) or
    (tostring(url):find("mode=players", 1, true) and "players") or
    (tostring(url):find("mode=teams", 1, true) and "teams")
  local proxyIndex = type(request) == "table" and request.proxy or activeProxy
  requestKinds[url] = nil
  if kind then pendingRequests[kind] = false
  else pendingRequests.players, pendingRequests.teams = false, false end
  if response then pcall(response.close) end
  lastError = tostring(proxyNames[proxyIndex] or ("P" .. proxyIndex)) .. ": " ..
    tostring(err or "HTTP request failed")
  rotateProxy(proxyIndex)
  draw()
end

local function loadHubData()
  if not fs.exists(localCacheFile) then
    lastError = "Waiting for Base Control data..."
    draw()
    return
  end
  local file = fs.open(localCacheFile, "r")
  if not file then
    lastError = "Cannot read Base Control cache"
    draw()
    return
  end
  local payload = textutils.unserializeJSON(file.readAll())
  file.close()
  if type(payload) ~= "table" or type(payload.players) ~= "table" or type(payload.teams) ~= "table" then
    lastError = "Invalid Base Control cache"
    draw()
    return
  end
  local updatedAt = tonumber(payload.hubUpdatedAt) or 0
  if updatedAt ~= lastHubUpdate then
    data = payload
    lastHubUpdate = updatedAt
    lastPlayerUpdate = updatedAt > 0 and updatedAt or (os.epoch and os.epoch("utc") or nil)
    activeProxy = tonumber(payload.hubProxy) or activeProxy
    sortTeams()
    rememberOnlinePlayers(data)
  end
  local age = os.epoch and updatedAt > 0 and math.floor((os.epoch("utc") - updatedAt) / 1000) or 0
  lastError = age > 30 and ("HUB DATA STALE: " .. tostring(age) .. "s") or nil
  draw()
end

local function update()
  if localMode then loadHubData()
  else requestProxy("teams") end
end

lastError = localMode and "Waiting for Base Control data..." or "Loading live data..."
draw()
if not localMode then requestProxy("teams") end
local localTimer = localMode and os.startTimer(0.25) or nil
local playerTimer = not localMode and os.startTimer(playerRefreshSeconds) or nil
local teamTimer = not localMode and os.startTimer(teamRefreshSeconds) or nil
local animationTimer = os.startTimer(animationSeconds)
while true do
  local event, value, x, y = os.pullEvent()
  if event == "timer" and localMode and value == localTimer then
    loadHubData()
    localTimer = os.startTimer(1)
  elseif event == "timer" and not localMode and value == playerTimer then
    requestProxy("players")
    playerTimer = os.startTimer(playerRefreshSeconds)
  elseif event == "timer" and not localMode and value == teamTimer then
    requestProxy("teams")
    teamTimer = os.startTimer(teamRefreshSeconds)
  elseif event == "timer" and value == animationTimer then
    animate()
    animationTimer = os.startTimer(animationSeconds)
  elseif event == "http_success" then
    if profileRequests[value] then handleProfileSuccess(value, x)
    elseif not localMode then handleProxySuccess(value, x) end
  elseif event == "http_failure" then
    if profileRequests[value] then handleProfileFailure(value, x, y)
    elseif not localMode then handleProxyFailure(value, x, y) end
  elseif event == "key" then
    if selectedPlayerName then
      if value == keys.left or value == keys.backspace then
        selectedPlayerName, playerProfile, playerError = nil, nil, nil
      elseif value == keys.r then
        profileCache[selectedPlayerName:lower()] = nil
        openPlayer(selectedPlayerName)
      end
    elseif selectedName then
      if value == keys.left or value == keys.backspace then selectedName, detailPage = nil, 1
      elseif value == keys.right or value == keys.pageDown or value == keys.down then detailPage = detailPage + 1
      elseif value == keys.pageUp or value == keys.up then detailPage = detailPage - 1
      elseif value == keys.r then update() end
    else
      if value == keys.m then viewMode = viewMode == "map" and "list" or "map"
      elseif value == keys.a then viewMode = viewMode == "away" and "list" or "away"
      elseif viewMode == "away" and (value == keys.right or value == keys.pageDown or value == keys.down) then
        awayPage = awayPage + 1
      elseif viewMode == "away" and (value == keys.pageUp or value == keys.up) then
        awayPage = awayPage - 1
      elseif (viewMode == "map" or viewMode == "away") and
          (value == keys.left or value == keys.backspace) then viewMode = "list"
      elseif value == keys.right or value == keys.pageDown or value == keys.down then page = page + 1
      elseif value == keys.left or value == keys.pageUp or value == keys.up then page = page - 1
      elseif value == keys.r then update() end
    end
    draw()
  elseif event == "monitor_touch" then
    local touchX, touchY = x, y
    local _, height = target.getSize()
    if selectedPlayerName then
      if (touchY == 1 and touchX <= 9) or touchY == height then
        playClick("back")
        selectedPlayerName, playerProfile, playerError = nil, nil, nil
      else
        playClick("page")
      end
    elseif selectedName then
      if touchY == 1 and touchX <= 9 then
        playClick("back")
        selectedName, detailPage = nil, 1
      elseif rowPlayers[touchY] then
        playClick("open")
        openPlayer(rowPlayers[touchY])
      elseif touchY == height and touchX <= 7 then
        playClick("page")
        detailPage = detailPage - 1
      elseif touchY == height and touchX >= 8 and touchX <= 15 then
        playClick("page")
        detailPage = detailPage + 1
      else
        playClick("page")
      end
    elseif viewMode == "map" and touchY == height and touchX <= 7 then
      playClick("back")
      viewMode = "list"
    elseif viewMode == "map" and touchY == height and touchX >= 9 and touchX <= 16 then
      playClick("open")
      viewMode = "away"
    elseif viewMode == "map" and mapCells[touchY] and mapCells[touchY][touchX] then
      playClick("open")
      selectedName = tostring(mapCells[touchY][touchX].team)
      detailPage = 1
    elseif viewMode == "away" and touchY == height and touchX <= 7 then
      playClick("back")
      viewMode = "list"
    elseif viewMode == "away" and touchY == height and touchX >= 9 and touchX <= 15 then
      playClick("open")
      viewMode = "map"
    elseif viewMode == "away" and touchY == height and touchX >= 18 and touchX <= 20 then
      playClick("page")
      awayPage = awayPage - 1
    elseif viewMode == "away" and touchY == height and touchX >= 21 and touchX <= 23 then
      playClick("page")
      awayPage = awayPage + 1
    elseif viewMode == "away" and rowAwayPlayers[touchY] then
      local player = rowAwayPlayers[touchY]
      playClick("open")
      selectedName = tostring(player.team)
      detailPage = 1
      openPlayer(tostring(player.name))
    elseif viewMode == "list" and touchY == height and touchX >= 18 and touchX <= 24 then
      playClick("open")
      viewMode = "map"
    elseif viewMode == "list" and touchY == height and touchX >= 26 and touchX <= 34 then
      playClick("open")
      viewMode = "away"
    elseif rowTeams[touchY] then
      playClick("open")
      selectedName = tostring(rowTeams[touchY].name)
      detailPage = 1
    elseif touchY == height and touchX <= 7 then
      playClick("page")
      page = page - 1
    elseif touchY == height and touchX >= 8 and touchX <= 15 then
      playClick("page")
      page = page + 1
    else
      playClick("page")
    end
    draw()
  elseif event == "mouse_click" then
    local clickX, clickY = x, y
    local _, height = target.getSize()
    if selectedPlayerName then
      if (clickY == 1 and clickX <= 9) or clickY == height then
        playClick("back")
        selectedPlayerName, playerProfile, playerError = nil, nil, nil
      else
        playClick("page")
      end
    elseif selectedName then
      if clickY == 1 and clickX <= 9 then
        playClick("back")
        selectedName, detailPage = nil, 1
      elseif rowPlayers[clickY] then
        playClick("open")
        openPlayer(rowPlayers[clickY])
      elseif clickY == height and clickX <= 7 then
        playClick("page")
        detailPage = detailPage - 1
      elseif clickY == height and clickX >= 8 and clickX <= 15 then
        playClick("page")
        detailPage = detailPage + 1
      else
        playClick("page")
      end
    elseif viewMode == "map" and clickY == height and clickX <= 7 then
      playClick("back")
      viewMode = "list"
    elseif viewMode == "map" and clickY == height and clickX >= 9 and clickX <= 16 then
      playClick("open")
      viewMode = "away"
    elseif viewMode == "map" and mapCells[clickY] and mapCells[clickY][clickX] then
      playClick("open")
      selectedName = tostring(mapCells[clickY][clickX].team)
      detailPage = 1
    elseif viewMode == "away" and clickY == height and clickX <= 7 then
      playClick("back")
      viewMode = "list"
    elseif viewMode == "away" and clickY == height and clickX >= 9 and clickX <= 15 then
      playClick("open")
      viewMode = "map"
    elseif viewMode == "away" and clickY == height and clickX >= 18 and clickX <= 20 then
      playClick("page")
      awayPage = awayPage - 1
    elseif viewMode == "away" and clickY == height and clickX >= 21 and clickX <= 23 then
      playClick("page")
      awayPage = awayPage + 1
    elseif viewMode == "away" and rowAwayPlayers[clickY] then
      local player = rowAwayPlayers[clickY]
      playClick("open")
      selectedName = tostring(player.team)
      detailPage = 1
      openPlayer(tostring(player.name))
    elseif viewMode == "list" and clickY == height and clickX >= 18 and clickX <= 24 then
      playClick("open")
      viewMode = "map"
    elseif viewMode == "list" and clickY == height and clickX >= 26 and clickX <= 34 then
      playClick("open")
      viewMode = "away"
    elseif rowTeams[clickY] then
      playClick("open")
      selectedName = tostring(rowTeams[clickY].name)
      detailPage = 1
    elseif clickY == height and clickX <= 7 then
      playClick("page")
      page = page - 1
    elseif clickY == height and clickX >= 8 and clickX <= 15 then
      playClick("page")
      page = page + 1
    else
      playClick("page")
    end
    draw()
  end
end
