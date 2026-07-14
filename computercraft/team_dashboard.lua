local proxyUrl = "https://script.google.com/macros/s/AKfycbxw_loC2T0hdhyFTXam2AObNn5Tkz6bPTeAR2SoRMOBiEXaS0fYM1sQBusM0_rNAkRiLA/exec"
local refreshSeconds = 10
local animationSeconds = 0.5

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
local selectedName, detailPage = nil, 1
local rowTeams = {}
local animationFrame = 0

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
  writeAt(target, 1, 1, "< BACK ", foreground, background)
end

local function selectedTeam()
  if not data or not selectedName then return nil end
  for _, team in ipairs(data.teams) do
    if tostring(team.name) == selectedName then return team end
  end
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

  local footer = string.format(" PAGE %d/%d   %d TEAMS   TAP A TEAM", page, pageCount, #data.teams)
  writeAt(target, 1, height, footer, colors.lightGray, colors.black)
end

local function drawDetails(team)
  local width, height = target.getSize()
  local teamColor = nearestColor(target, team.color)
  target.setBackgroundColor(colors.black)
  target.clear()
  drawBackButton()
  writeAt(target, 9, 1, "TEAM DETAILS", colors.white, colors.black)
  drawAnimatedLine(2, teamColor)
  writeAt(target, 2, 3, tostring(team.name or "UNKNOWN"), teamColor, colors.black)
  writeAt(target, 2, 5,
    string.format("ONLINE  %d / %d", tonumber(team.online) or 0, tonumber(team.members) or 0),
    (tonumber(team.online) or 0) > 0 and colors.lime or colors.gray, colors.black)
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
    writeAt(target, 2, y, isOnline and ">" or "-",
      isOnline and colors.lime or colors.gray, colors.black)
    writeAt(target, 5, y, name,
      isOnline and colors.white or colors.lightGray, colors.black)
    writeAt(target, math.max(8, width - 8), y,
      isOnline and "ONLINE" or "OFFLINE",
      isOnline and colors.lime or colors.gray, colors.black)
  end
  writeAt(target, 1, height,
    string.format(" MEMBER PAGE %d/%d   < BACK", detailPage, pages), colors.gray, colors.black)
end

local function draw()
  local team = selectedTeam()
  if team then drawDetails(team) else drawRanking() end
end

local function animate()
  animationFrame = animationFrame + 1
  local team = selectedTeam()
  if team then
    drawBackButton()
    drawAnimatedLine(2, nearestColor(target, team.color))
  else
    drawAnimatedLine(2, colors.cyan)
  end
end

local function update()
  local newData, err = fetchData()
  if newData then data, lastError = newData, nil
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
    if selectedName then
      if value == keys.left or value == keys.backspace then selectedName, detailPage = nil, 1
      elseif value == keys.right or value == keys.pageDown or value == keys.down then detailPage = detailPage + 1
      elseif value == keys.pageUp or value == keys.up then detailPage = detailPage - 1
      elseif value == keys.r then update() end
    else
      if value == keys.right or value == keys.pageDown or value == keys.down then page = page + 1
      elseif value == keys.left or value == keys.pageUp or value == keys.up then page = page - 1
      elseif value == keys.r then update() end
    end
    draw()
  elseif event == "monitor_touch" then
    local touchX, touchY = x, y
    if selectedName then
      if touchY == 1 and touchX <= 7 then
        playClick("back")
        selectedName, detailPage = nil, 1
      else
        playClick("page")
        detailPage = detailPage + 1
      end
    elseif rowTeams[touchY] then
      playClick("open")
      selectedName = tostring(rowTeams[touchY].name)
      detailPage = 1
    else
      playClick("page")
      page = page + 1
    end
    draw()
  elseif event == "mouse_click" then
    local clickX, clickY = x, y
    if selectedName then
      if clickY == 1 and clickX <= 7 then
        playClick("back")
        selectedName, detailPage = nil, 1
      else
        playClick("page")
        detailPage = detailPage + 1
      end
    elseif rowTeams[clickY] then
      playClick("open")
      selectedName = tostring(rowTeams[clickY].name)
      detailPage = 1
    else
      playClick("page")
      page = page + 1
    end
    draw()
  end
end
