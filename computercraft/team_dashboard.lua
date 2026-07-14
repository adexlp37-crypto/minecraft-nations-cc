local proxyUrl = "https://script.google.com/macros/s/AKfycbxw_loC2T0hdhyFTXam2AObNn5Tkz6bPTeAR2SoRMOBiEXaS0fYM1sQBusM0_rNAkRiLA/exec"
local refreshSeconds = 10

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
local target = monitor or term
if monitor then monitor.setTextScale(1) end

local data, lastError, page = nil, nil, 1

local function draw()
  local width, height = target.getSize()
  target.setBackgroundColor(colors.black)
  target.clear()
  writeAt(target, 1, 1, " NATIONS // LIVE RANKING", colors.white, colors.blue)
  if width > 24 then
    writeAt(target, width - 9, 1, os.date("%H:%M:%S"), colors.lightBlue, colors.blue)
  end

  if not data then
    writeAt(target, 2, 3, "BLUEMAP CONNECTION ERROR", colors.red)
    writeAt(target, 2, 5, lastError or "No data", colors.orange)
    writeAt(target, 2, 7, "Retrying automatically...", colors.lightGray)
    return
  end

  local rows = math.max(1, height - 4)
  local pageCount = math.max(1, math.ceil(#data.teams / rows))
  page = math.max(1, math.min(page, pageCount))
  local first = (page - 1) * rows + 1

  writeAt(target, 1, 2, "#  TEAM", colors.gray)
  writeAt(target, math.max(14, width - 13), 2, "ON", colors.gray)
  writeAt(target, math.max(20, width - 7), 2, "AREA", colors.gray)

  for row = 1, rows do
    local rank = first + row - 1
    local team = data.teams[rank]
    if not team then break end
    local y = row + 2
    local teamColor = nearestColor(target, team.color)
    local onlineText = tostring(team.online or 0) .. "/" .. tostring(team.members or 0)
    local areaText = compactNumber(team.areaBlocks)
    local onlineX = math.max(14, width - 13)
    local areaX = math.max(20, width - 7)
    local nameWidth = math.max(3, onlineX - 6)
    writeAt(target, 1, y, string.format("%2d", rank), colors.lightGray)
    writeAt(target, 4, y, "#", teamColor)
    writeAt(target, 6, y, tostring(team.name or "?"):sub(1, nameWidth), teamColor)
    writeAt(target, onlineX, y, onlineText,
      (tonumber(team.online) or 0) > 0 and colors.lime or colors.gray)
    writeAt(target, areaX, y, areaText, colors.yellow)
  end

  local footer = string.format("Page %d/%d | %d teams | arrows/touch", page, pageCount, #data.teams)
  writeAt(target, 1, height, footer, colors.lightGray)
end

local function update()
  local newData, err = fetchData()
  if newData then data, lastError = newData, nil
  else lastError = err end
  draw()
end

update()
local timer = os.startTimer(refreshSeconds)
while true do
  local event, value = os.pullEvent()
  if event == "timer" and value == timer then
    update()
    timer = os.startTimer(refreshSeconds)
  elseif event == "key" then
    if value == keys.right or value == keys.pageDown or value == keys.down then page = page + 1
    elseif value == keys.left or value == keys.pageUp or value == keys.up then page = page - 1
    elseif value == keys.r then update() end
    draw()
  elseif event == "monitor_touch" or event == "mouse_click" then
    local _, height = target.getSize()
    local rows = math.max(1, height - 4)
    local pages = data and math.max(1, math.ceil(#data.teams / rows)) or 1
    page = page % pages + 1
    draw()
  end
end
