math.randomseed(os.time())

local preferredMonitorSide = "left"
local preferredModemSide = "top"
local updateInterval = 3
local renderInterval = 0.3

local watchlist = {
  ["Tbnyeet"] = true,
  ["Lilia_Mer"] = true,
}

local googleAppUrl = "https://script.google.com/macros/s/AKfycbw9DD4BqpG0ruyu86A0wn5VwZ8zbofbI16fvZu1nhu2SZ4Vyg6TGIrh2UQy763e3H2l/exec"

local cachedPlayers = {}
local highlightedPlayers = {}
local playerClickMap = {}
local lastStatus = "Starting..."
local lastUpdate = "never"

local blinkState = true
local colorIndex = 1
local rainbowColors = {
  colors.red, colors.orange, colors.yellow,
  colors.green, colors.blue, colors.purple, colors.magenta
}

local function findMonitor()
  if peripheral.getType(preferredMonitorSide) == "monitor" then
    return preferredMonitorSide, peripheral.wrap(preferredMonitorSide)
  end

  local name, monitor = peripheral.find("monitor")
  return name, monitor
end

local function openModem()
  if peripheral.getType(preferredModemSide) == "modem" then
    rednet.open(preferredModemSide)
    print("Rednet active on " .. preferredModemSide)
    return
  end

  for _, side in ipairs(peripheral.getNames()) do
    if peripheral.getType(side) == "modem" then
      rednet.open(side)
      print("Rednet active on " .. side)
      return
    end
  end

  print("No modem found. Scanner display still works.")
end

local monitorName, monitor = findMonitor()
if monitor then
  monitor.setTextScale(0.5)
else
  print("No monitor found. Attach one or change preferredMonitorSide.")
end

openModem()

local function writeLine(target, y, text, textColor, backgroundColor)
  local width = target.getSize()
  target.setCursorPos(1, y)
  target.setTextColor(textColor or colors.white)
  target.setBackgroundColor(backgroundColor or colors.black)
  if #text > width then
    text = text:sub(1, width)
  end
  target.write(text .. string.rep(" ", math.max(0, width - #text)))
end

local function playerCoords(player)
  local position = player.position or {}
  local x = math.floor((position.x or 0) + 0.5)
  local y = math.floor((position.y or 0) + 0.5)
  local z = math.floor((position.z or 0) + 0.5)
  return x, y, z
end

local function normalizePlayers(data)
  if type(data) ~= "table" then
    return {}
  end

  local players = data.players or data
  if type(players) ~= "table" then
    return {}
  end

  local normalized = {}
  for _, player in ipairs(players) do
    if type(player) == "table" and player.name and player.position then
      normalized[#normalized + 1] = player
    end
  end
  return normalized
end

local function internetFetchLoop()
  local httpHeaders = {
    ["User-Agent"] = "CC-Tweaked Minecraft Nations Scanner",
    ["Accept"] = "application/json",
    ["Cache-Control"] = "no-cache"
  }

  while true do
    local epoch = os.epoch and os.epoch("utc") or os.clock()
    local finalUrl = googleAppUrl .. "?cb=" .. tostring(epoch) .. tostring(math.random(1, 100000))
    local httpSuccess, response = pcall(http.get, {
      url = finalUrl,
      headers = httpHeaders,
      redirect = true
    })

    if httpSuccess and response then
      local readSuccess, rawJson = pcall(response.readAll)
      response.close()

      if readSuccess and rawJson and rawJson ~= "" then
        local jsonSuccess, data = pcall(textutils.unserializeJSON, rawJson)
        local players = normalizePlayers(data)

        if jsonSuccess and #players > 0 then
          cachedPlayers = players
          lastStatus = "OK: " .. tostring(#players) .. " players"
          lastUpdate = os.date("%H:%M:%S")
          if rednet.isOpen() then
            rednet.broadcast(rawJson, "bluemap_alarm_system")
          end
        elseif jsonSuccess then
          cachedPlayers = {}
          lastStatus = "OK: no players"
          lastUpdate = os.date("%H:%M:%S")
        else
          lastStatus = "JSON error"
        end
      else
        lastStatus = "Empty response"
      end
    else
      lastStatus = "HTTP error"
    end

    os.sleep(updateInterval)
  end
end

local function monitorRenderLoop()
  if not monitor then
    while true do
      print("Scanner running without monitor. " .. lastStatus)
      os.sleep(5)
    end
  end

  while true do
    local maxW, maxH = monitor.getSize()
    playerClickMap = {}

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    writeLine(monitor, 1, "BlueMap Player Tracker", colors.white)
    writeLine(monitor, 2, "Status: " .. lastStatus .. " | " .. lastUpdate, colors.gray)

    local pinnedList = {}
    local normalList = {}
    local watchListPlayers = {}

    for _, player in ipairs(cachedPlayers) do
      if highlightedPlayers[player.name] then
        pinnedList[#pinnedList + 1] = player
      elseif watchlist[player.name] then
        watchListPlayers[#watchListPlayers + 1] = player
      else
        normalList[#normalList + 1] = player
      end
    end

    local currentY = 4

    if #pinnedList > 0 then
      writeLine(monitor, currentY, ">> HIGH PRIORITY TARGETS <<", blinkState and colors.yellow or colors.orange)
      currentY = currentY + 1

      for _, player in ipairs(pinnedList) do
        playerClickMap[currentY] = player.name
        local x, y, z = playerCoords(player)
        local prefix = blinkState and "==> " or "--> "
        local suffix = blinkState and " <==" or " <--"
        local text = string.format("%s%s: X:%d Y:%d Z:%d%s", prefix, player.name, x, y, z, suffix)
        writeLine(monitor, currentY, text, blinkState and colors.white or colors.yellow, colors.purple)
        currentY = currentY + 1
      end

      writeLine(monitor, currentY, string.rep("-", maxW), colors.gray)
      currentY = currentY + 1
    end

    for _, player in ipairs(normalList) do
      if currentY < maxH then
        playerClickMap[currentY] = player.name
        local x, y, z = playerCoords(player)
        writeLine(monitor, currentY, string.format("%s: X:%d Y:%d Z:%d", player.name, x, y, z), colors.lightGray)
        currentY = currentY + 1
      end
    end

    if #cachedPlayers == 0 then
      writeLine(monitor, 4, "Waiting for player data...", colors.gray)
    end

    if #watchListPlayers > 0 and maxH >= 5 then
      local boxHeight = math.min(#watchListPlayers + 2, maxH - 3)
      local boxTop = maxH - boxHeight + 1
      local boxColor = blinkState and colors.red or colors.gray

      writeLine(monitor, boxTop, "+" .. string.rep("-", math.max(0, maxW - 2)) .. "+", boxColor)

      for i, player in ipairs(watchListPlayers) do
        local row = boxTop + i
        if row < maxH then
          playerClickMap[row] = player.name
          local x, y, z = playerCoords(player)
          local localColorIndex = ((colorIndex + i) % #rainbowColors) + 1
          local text = string.format("| %s: X:%d Y:%d Z:%d", player.name, x, y, z)
          writeLine(monitor, row, text, rainbowColors[localColorIndex])
          monitor.setCursorPos(maxW, row)
          monitor.setTextColor(boxColor)
          monitor.write("|")
        end
      end

      writeLine(monitor, maxH, "+" .. string.rep("-", math.max(0, maxW - 2)) .. "+", boxColor)
    end

    blinkState = not blinkState
    colorIndex = colorIndex + 1
    os.sleep(renderInterval)
  end
end

local function monitorTouchLoop()
  while true do
    local event, side, x, y = os.pullEvent("monitor_touch")
    if side == monitorName then
      local clickedPlayer = playerClickMap[y]
      if clickedPlayer then
        highlightedPlayers[clickedPlayer] = not highlightedPlayers[clickedPlayer] or nil
      end
    end
  end
end

if not http then
  error("HTTP is disabled in the server config.", 0)
end

parallel.waitForAny(internetFetchLoop, monitorRenderLoop, monitorTouchLoop)
