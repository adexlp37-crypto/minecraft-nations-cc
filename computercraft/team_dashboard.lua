local proxyUrl = "https://script.google.com/macros/s/AKfycbyXcO7DJgloCLhteQixcPabIXHQTANvCyrMaOrLWjava--_iqFB-ItfgLTwbBpHzOV3/exec"
local profileApiUrl = "https://api.ashcon.app/mojang/v2/user/"
local refreshSeconds = 10
local animationSeconds = 0.5
local lastSeenFile = ".team_dashboard_last_seen"

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
  local separator = proxyUrl:find("?", 1, true) and "&" or "?"
  local url = proxyUrl .. separator .. "dashboard=" ..
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
local viewMode = "list"
local selectedName, detailPage = nil, 1
local rowTeams = {}
local rowPlayers = {}
local mapCells = {}
local selectedPlayerName, playerProfile, playerError = nil, nil, nil
local profileCache = {}
local lastSeen = {}
local animationFrame = 0
local draw

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
  if changed then saveLastSeen() end
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
  playerProfile, playerError = fetchProfile(name)
  draw()
end

local function drawHeader(title, accent)
  local width, height = target.getSize()
  target.setBackgroundColor(colors.black)
  target.clear()
  writeAt(target, 2, 1, title, colors.white, colors.black)
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

  local left, right = 2, math.max(2, width - 1)
  local top, bottom = 4, math.max(4, height - 2)
  local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
  for _, base in ipairs(bases) do
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

  writeAt(target, 2, 3, "NUMBER = PLAYERS CURRENTLY AT BASE", colors.gray, colors.black)
  for _, base in ipairs(bases) do
    local x1, x2 = screenX(base.minX), screenX(base.maxX)
    local y1, y2 = screenY(base.minZ), screenY(base.maxZ)
    if x2 < x1 then x1, x2 = x2, x1 end
    if y2 < y1 then y1, y2 = y2, y1 end
    x2 = math.max(x1, x2)
    y2 = math.max(y1, y2)
    local baseColor = nearestColor(target, base.color)
    for y = y1, y2 do
      mapCells[y] = mapCells[y] or {}
      writeAt(target, x1, y, string.rep(" ", math.max(1, x2 - x1 + 1)), colors.black, baseColor)
      for x = x1, x2 do mapCells[y][x] = base end
    end
    local centerX = screenX(base.x)
    local centerY = screenY(base.z)
    local count = tostring(tonumber(base.atBase) or 0)
    local labelX = math.max(left, math.min(right - #count + 1, centerX - math.floor(#count / 2)))
    writeAt(target, labelX, centerY, count, colors.white, colors.black)
    mapCells[centerY] = mapCells[centerY] or {}
    for x = labelX, math.min(right, labelX + #count - 1) do mapCells[centerY][x] = base end
  end

  local totalAtBase, totalOnline = 0, 0
  for _, team in ipairs(type(data.teams) == "table" and data.teams or {}) do
    totalAtBase = totalAtBase + (tonumber(team.atBase) or 0)
    totalOnline = totalOnline + (tonumber(team.online) or 0)
  end
  writeAt(target, 1, height, "< LIST ", colors.black, colors.cyan)
  writeAt(target, 10, height,
    "AT BASE " .. totalAtBase .. " / ONLINE " .. totalOnline, colors.lightGray, colors.black)
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
    writeAt(target, math.max(8, width - 8), y,
      isOnline and "ONLINE" or "OFFLINE",
      isOnline and colors.lime or colors.gray, colors.black)
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

  local onlineNow = playerIsOnline(team, selectedPlayerName)
  local livePlayer = selectedPlayerData(selectedPlayerName)
  writeAt(target, 2, 5, "STATUS     " .. (onlineNow and "ONLINE NOW" or "OFFLINE"),
    onlineNow and colors.lime or colors.gray, colors.black)
  writeAt(target, 2, 6, "LAST SEEN  " .. (onlineNow and "ONLINE NOW" or lastSeenText(selectedPlayerName)),
    onlineNow and colors.lime or colors.lightBlue, colors.black)
  if livePlayer then
    local location = livePlayer.locationStatus == "OWN_BASE" and "IN OWN BASE" or
      livePlayer.locationStatus == "FOREIGN_BASE" and
        ("IN " .. tostring(livePlayer.insideTeam or "FOREIGN BASE")) or "OUTSIDE BASES"
    writeAt(target, 2, 7, "LOCATION   " .. location,
      livePlayer.locationStatus == "OWN_BASE" and colors.lime or colors.orange, colors.black)
  end

  if not playerProfile and not playerError then
    writeAt(target, 2, 8, "LOADING PROFILE...", colors.yellow, colors.black)
    return
  end
  if playerError then
    writeAt(target, 2, 8, "PROFILE UNAVAILABLE", colors.red, colors.black)
    writeAt(target, 2, 10, playerError, colors.orange, colors.black)
    writeAt(target, 1, height, "< BACK TO TEAM", colors.lightGray, colors.black)
    return
  end

  local created = playerProfile.created_at
  local age = accountAge(created)
  writeAt(target, 2, 8, "CURRENT  " .. tostring(playerProfile.username or selectedPlayerName),
    colors.white, colors.black)
  writeAt(target, 2, 9, "CREATED  " .. (created and tostring(created) or "UNKNOWN"),
    created and colors.lime or colors.gray, colors.black)
  writeAt(target, 2, 10, "AGE      " .. (age and (tostring(age) .. " years") or "UNKNOWN"),
    age and colors.lightBlue or colors.gray, colors.black)
  writeAt(target, 2, 11, "UUID     " .. tostring(playerProfile.uuid or "UNKNOWN"),
    colors.lightGray, colors.black)
  writeAt(target, 2, 13, "KNOWN USERNAMES", colors.white, colors.black)

  local history = type(playerProfile.username_history) == "table" and
    playerProfile.username_history or {}
  local rows = math.max(1, height - 14)
  if #history == 0 then
    writeAt(target, 2, 14, "No public history available", colors.gray, colors.black)
  else
    for index = 1, math.min(#history, rows) do
      local item = history[index]
      local username = type(item) == "table" and item.username or tostring(item)
      local changed = type(item) == "table" and item.changed_at or nil
      writeAt(target, 2, index + 13, index .. ". " .. tostring(username),
        index == #history and colors.white or colors.lightGray, colors.black)
      if changed and width > 38 then
        writeAt(target, width - 11, index + 13, tostring(changed):sub(1, 10), colors.gray, colors.black)
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
  else
    drawAnimatedLine(2, colors.cyan)
  end
end

local function update()
  local newData, err = fetchData()
  if newData then
    rememberOnlinePlayers(newData)
    data, lastError = newData, nil
  else lastError = err end
  draw()
end

update()
local timer = os.startTimer(refreshSeconds)
local animationTimer = os.startTimer(animationSeconds)
while true do
  local event, value, x, y = os.pullEvent()
  if event == "timer" and value == timer then
    update()
    timer = os.startTimer(refreshSeconds)
  elseif event == "timer" and value == animationTimer then
    animate()
    animationTimer = os.startTimer(animationSeconds)
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
      elseif viewMode == "map" and (value == keys.left or value == keys.backspace) then viewMode = "list"
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
    elseif viewMode == "map" and mapCells[touchY] and mapCells[touchY][touchX] then
      playClick("open")
      selectedName = tostring(mapCells[touchY][touchX].team)
      detailPage = 1
    elseif viewMode == "list" and touchY == height and touchX >= 18 and touchX <= 24 then
      playClick("open")
      viewMode = "map"
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
    elseif viewMode == "map" and mapCells[clickY] and mapCells[clickY][clickX] then
      playClick("open")
      selectedName = tostring(mapCells[clickY][clickX].team)
      detailPage = 1
    elseif viewMode == "list" and clickY == height and clickX >= 18 and clickX <= 24 then
      playClick("open")
      viewMode = "map"
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
