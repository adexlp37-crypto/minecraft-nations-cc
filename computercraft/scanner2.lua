math.randomseed(os.time())

local preferredMonitorSide = "left"
local preferredModemSide = "top"
local updateInterval = 3
local maxRetryInterval = 60
local renderInterval = 0.3

local watchlist = {
  ["Tbnyeet"] = true,
  ["Lilia_Mer"] = true,
}

local blueMapBaseUrl = "http://172.255.251.68:25581"
local googleProxyUrl = "https://script.google.com/macros/s/AKfycbw9DD4BqpG0ruyu86A0wn5VwZ8zbofbI16fvZu1nhu2SZ4Vyg6TGIrh2UQy763e3H2l/exec"
local blueMapPlayerPaths = {
  "/players.json",
  "/live/players.json",
  "/tiles/players.json",
  "/maps/world/players.json",
  "/maps/world/live/players.json",
  "/maps/world/maps/players.json",
  "/maps/world/tiles/players.json",
  "/maps/world/live/markers.json",
  "/maps/world/markers.json"
}

local cachedPlayers = {}
local highlightedPlayers = {}
local playerClickMap = {}
local lastStatus = "Starting..."
local lastUpdate = "never"
local activePlayerUrl = nil
local diagnosticLines = {
  "No request completed yet.",
  "Checking BlueMap endpoints..."
}

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
  monitor.setTextScale(1)
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
    if type(player) == "table" then
      local position = player.position or player.pos
      local x = player.x or (position and position.x)
      local y = player.y or (position and position.y)
      local z = player.z or (position and position.z)
      local name = player.name or player.label or player.uuid

      if name and x and y and z then
        normalized[#normalized + 1] = {
          name = tostring(name),
          position = {
            x = tonumber(x) or 0,
            y = tonumber(y) or 0,
            z = tonumber(z) or 0
          },
          rotation = player.rotation
        }
      end
    end
  end
  return normalized
end

local function looksLikePlayerPayload(data)
  if type(data) ~= "table" then
    return false
  end

  if type(data.players) == "table" then
    return true
  end

  for _, value in pairs(data) do
    if type(value) == "table" then
      local position = value.position or value.pos
      if value.name and (position or value.x or value.z) then
        return true
      end
    end
  end

  return false
end

local function requestJson(url, headers)
  local httpSuccess, response, requestError = pcall(http.get, {
    url = url,
    headers = headers,
    redirect = true
  })

  if not httpSuccess then
    return nil, "HTTP crashed: " .. tostring(response)
  end

  if not response then
    return nil, "Request failed: " .. tostring(requestError or "unknown")
  end

  local responseCode = response.getResponseCode and response.getResponseCode() or 200

  local readSuccess, rawJson = pcall(response.readAll)
  response.close()

  if not readSuccess or not rawJson or rawJson == "" then
    return nil, "HTTP " .. tostring(responseCode) .. ": empty response"
  end

  local jsonSuccess, data = pcall(textutils.unserializeJSON, rawJson)
  if not jsonSuccess then
    return nil, "HTTP " .. tostring(responseCode) .. ": invalid JSON"
  end

  return data, nil, rawJson, responseCode
end

local function discoverPlayerUrl(headers)
  diagnosticLines = {
    "Testing BlueMap on port 25581...",
    "If this remains here, HTTP is blocked."
  }

  for _, path in ipairs(blueMapPlayerPaths) do
    local epoch = os.epoch and os.epoch("utc") or os.clock()
    local url = blueMapBaseUrl .. path .. "?cb=" .. tostring(epoch)
    lastStatus = "Testing " .. path
    local data, err = requestJson(url, headers)
    local players = normalizePlayers(data)
    if looksLikePlayerPayload(data) then
      activePlayerUrl = blueMapBaseUrl .. path
      diagnosticLines = {
        "CONNECTED: " .. path,
        "BlueMap data received successfully."
      }
      return activePlayerUrl, players
    end

    diagnosticLines = {
      "Last test: " .. path,
      err or "JSON received, but no players field",
      "Trying the next endpoint..."
    }
    os.sleep(0.05)
  end

  diagnosticLines = {
    "NO PLAYER ENDPOINT FOUND",
    "Last: " .. blueMapPlayerPaths[#blueMapPlayerPaths],
    "Check terminal for the exact reason.",
    "Likely: HTTP whitelist or wrong map ID."
  }
  return nil, {}
end

local function internetFetchLoop()
  local httpHeaders = {
    ["User-Agent"] = "CC-Tweaked Minecraft Nations Scanner",
    ["Accept"] = "application/json",
    ["Cache-Control"] = "no-cache"
  }

  local retryDelay = updateInterval

  while true do
    local epoch = os.epoch and os.epoch("utc") or os.clock()
    local finalUrl = googleProxyUrl .. "?cb=" .. tostring(epoch) .. tostring(math.random(1, 100000))
    lastStatus = "Contacting Google proxy..."

    local data, err, rawJson = requestJson(finalUrl, httpHeaders)
    local players = normalizePlayers(data)

    if data and looksLikePlayerPayload(data) then
      cachedPlayers = players
      lastStatus = "LIVE: " .. tostring(#players) .. " players"
      lastUpdate = os.date("%H:%M:%S")
      retryDelay = updateInterval
      diagnosticLines = {
        "GOOGLE PROXY CONNECTED",
        "Next update in " .. tostring(updateInterval) .. " seconds."
      }
      if rednet.isOpen() and rawJson then
        rednet.broadcast(rawJson, "bluemap_alarm_system")
      end
    else
      lastStatus = err or "Proxy returned invalid player data"
      retryDelay = math.min(maxRetryInterval, retryDelay * 2)
      diagnosticLines = {
        "GOOGLE PROXY TEMPORARILY BUSY",
        lastStatus,
        "Keeping the last known player data.",
        "Retry in " .. tostring(retryDelay) .. " seconds."
      }
      print("Google proxy: " .. lastStatus .. "; retry in " .. tostring(retryDelay) .. "s")
    end

    os.sleep(retryDelay)
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

    writeLine(monitor, 1, "BLUEMAP PLAYER TRACKER", colors.white, colors.blue)
    writeLine(monitor, 2, "Status: " .. lastStatus, colors.yellow)
    writeLine(monitor, 3, "Update: " .. lastUpdate, colors.lightGray)

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

    local currentY = 5

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
      writeLine(monitor, 5, "NO PLAYER DATA", colors.red)
      for i, line in ipairs(diagnosticLines) do
        if 6 + i <= maxH then
          writeLine(monitor, 5 + i, line, i == 1 and colors.white or colors.lightGray)
        end
      end
      if maxH >= 11 then
        writeLine(monitor, 11, "Source: Google BlueMap proxy", colors.gray)
      end
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
