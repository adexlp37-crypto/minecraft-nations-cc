local configFile = ".canal_gate.cfg"
local accessFile = ".canal_access.txt"
local defaultTrackerUrl = "https://minecraft-nations-cc.adexlp37.workers.dev"
local validSides = { top=true, bottom=true, left=true, right=true, front=true, back=true }

local function prompt(label, default)
  write(label .. " [" .. tostring(default) .. "]: ")
  local answer = read()
  return answer == "" and default or answer
end

local function numberPrompt(label, default)
  while true do
    local value = tonumber(prompt(label, default))
    if value then return value end
    print("Please enter a number.")
  end
end

local function setup()
  print("CANAL GATE SETUP")
  print("Enter two opposite corners for each rectangular zone.")
  local config = {}
  config.trackerUrl = prompt("BlueMap JSON/proxy URL", defaultTrackerUrl)
  config.webhookUrl = prompt("Discord webhook URL (blank disables)", "")
  repeat config.gateSide = prompt("Gate redstone output side", "back"):lower()
  until validSides[config.gateSide]
  repeat config.manualOpenSide = prompt("Emergency OPEN input side (blank disables)", "top"):lower()
  until config.manualOpenSide == "" or
    (validSides[config.manualOpenSide] and config.manualOpenSide ~= config.gateSide)
  config.activeHigh = prompt("Does redstone ON open the gate? y/n", "y"):lower() ~= "n"
  config.pollSeconds = math.max(1, numberPrompt("BlueMap refresh seconds", 3))
  config.holdSeconds = math.max(2, numberPrompt("Keep-open safety delay seconds", 10))
  config.travelSeconds = math.max(0, numberPrompt("Gate travel time seconds", 4))
  config.approach = {
    x1=numberPrompt("Approach corner 1 X", 0), z1=numberPrompt("Approach corner 1 Z", 0),
    x2=numberPrompt("Approach corner 2 X", 0), z2=numberPrompt("Approach corner 2 Z", 0)
  }
  config.passage = {
    x1=numberPrompt("Passage corner 1 X", 0), z1=numberPrompt("Passage corner 1 Z", 0),
    x2=numberPrompt("Passage corner 2 X", 0), z2=numberPrompt("Passage corner 2 Z", 0)
  }
  local file = assert(fs.open(configFile, "w"))
  file.write(textutils.serialize(config))
  file.close()
  if not fs.exists(accessFile) then
    file = assert(fs.open(accessFile, "w")); file.close()
  end
  print("Setup saved. Add users with: canal_gate add PlayerName")
end

local function loadConfig()
  if not fs.exists(configFile) then return nil end
  local file = fs.open(configFile, "r")
  local config = textutils.unserialize(file.readAll())
  file.close()
  return type(config) == "table" and config or nil
end

local function saveConfig(config)
  local file = assert(fs.open(configFile, "w"))
  file.write(textutils.serialize(config))
  file.close()
end

local function loadAccess()
  local names = {}
  if not fs.exists(accessFile) then return names end
  local file = fs.open(accessFile, "r")
  for name in file.readAll():gmatch("[^\r\n]+") do
    name = name:match("^%s*(.-)%s*$")
    if name ~= "" then names[name:lower()] = name end
  end
  file.close()
  return names
end

local function saveAccess(names)
  local values = {}
  for _, original in pairs(names) do values[#values + 1] = original end
  table.sort(values, function(a, b) return a:lower() < b:lower() end)
  local file = assert(fs.open(accessFile, "w"))
  file.write(table.concat(values, "\n") .. (#values > 0 and "\n" or ""))
  file.close()
end

local args = { ... }
local command = (args[1] or "run"):lower()
if command == "setup" then setup(); return end
if command == "url" then
  if not args[2] then error("Usage: canal_gate url <proxy URL>", 0) end
  local config = loadConfig()
  if not config then error("Run canal_gate setup first.", 0) end
  config.trackerUrl = args[2]
  saveConfig(config)
  print("Tracker URL updated.")
  return
elseif command == "manual" then
  if not args[2] then error("Usage: canal_gate manual <side|off>", 0) end
  local config = loadConfig()
  if not config then error("Run canal_gate setup first.", 0) end
  local side = args[2]:lower()
  if side == "off" or side == "none" then side = "" end
  if side ~= "" and (not validSides[side] or side == config.gateSide) then
    error("Choose top, bottom, left, right, front, back, or off; not the gate output side.", 0)
  end
  config.manualOpenSide = side
  saveConfig(config)
  print(side == "" and "Emergency OPEN input disabled." or ("Emergency OPEN input: " .. side))
  return
end
if command == "add" or command == "remove" then
  if not args[2] then error("Usage: canal_gate " .. command .. " PlayerName", 0) end
  local names = loadAccess()
  if command == "add" then names[args[2]:lower()] = args[2]
  else names[args[2]:lower()] = nil end
  saveAccess(names)
  print(command == "add" and "Access granted." or "Access removed.")
  return
elseif command == "list" then
  print("AUTHORIZED CANAL USERS")
  local names = loadAccess()
  local count = 0
  for _, name in pairs(names) do print("- " .. name); count = count + 1 end
  if count == 0 then print("(none - gate will remain closed)") end
  return
elseif command ~= "run" then
  print("Commands: setup, url <URL>, manual <side|off>, add <name>, remove <name>, list, run")
  return
end

local config = loadConfig()
if not config then
  print("First start: opening setup.")
  setup()
  config = assert(loadConfig())
end

local speaker = peripheral.find("speaker")
local monitor = peripheral.find("monitor")
if monitor then monitor.setTextScale(1) end
local display = monitor or term
-- Adopt the physical output that is already present. Restarting the computer
-- during an outage must not silently change an open gate to closed.
local gateOpen = redstone.getOutput(config.gateSide) == config.activeHigh
local lastAuthorizedSeen = -math.huge
local openingAt, arrivalPlayed
local previousPassage, passageCooldown = {}, {}
local lastError = ""

local function inside(position, zone)
  if type(position) ~= "table" then return false end
  local x, z = tonumber(position.x), tonumber(position.z)
  if not x or not z then return false end
  return x >= math.min(zone.x1, zone.x2) and x <= math.max(zone.x1, zone.x2)
    and z >= math.min(zone.z1, zone.z2) and z <= math.max(zone.z1, zone.z2)
end

local function note(pitch, duration)
  if speaker then
    pcall(speaker.playNote, "harp", 0.55, pitch)
    sleep(duration)
  end
end

local function openingSound()
  for _, pitch in ipairs({ 6, 10, 13, 18 }) do note(pitch, 0.16) end
end

local function arrivedSound()
  for _, pitch in ipairs({ 13, 18, 22 }) do note(pitch, 0.20) end
end

local function setGate(open)
  if gateOpen == open then return end
  gateOpen = open
  redstone.setOutput(config.gateSide, open == config.activeHigh)
  if open then
    openingAt, arrivalPlayed = os.clock(), false
    openingSound()
  else
    openingAt, arrivalPlayed = nil, false
  end
end

local function webhook(message)
  if not config.webhookUrl or config.webhookUrl == "" then return end
  local body = textutils.serializeJSON({ content = message })
  local ok, response, err = pcall(http.post, {
    url = config.webhookUrl, body = body, redirect = true, timeout = 8,
    headers = { ["Content-Type"] = "application/json", ["User-Agent"] = "CC-Canal-Gate/1.0" }
  })
  if ok and response then response.close()
  else lastError = "Webhook: " .. tostring(ok and err or response) end
end

local function fetchPlayers()
  local separator = config.trackerUrl:find("?", 1, true) and "&" or "?"
  local url = config.trackerUrl .. separator .. "canal=" ..
    tostring(os.epoch and os.epoch("utc") or math.random(1, 999999))
  local ok, response, err = pcall(http.get, {
    url=url, redirect=true, timeout=8,
    headers={ ["Accept"]="application/json", ["Cache-Control"]="no-cache" }
  })
  if not ok then return nil, tostring(response) end
  if not response then return nil, tostring(err or "request failed") end
  local body = response.readAll(); response.close()
  local data = textutils.unserializeJSON(body)
  if type(data) ~= "table" or type(data.players) ~= "table" then return nil, "invalid player JSON" end
  return data.players
end

local function draw(players, authorizedNearby, connectionOkay, manualOpen)
  local width = display.getSize()
  display.setBackgroundColor(colors.black); display.clear()
  display.setCursorPos(1, 1); display.setTextColor(colors.cyan)
  display.write(("ISRAEL CANAL CONTROL"):sub(1, width))
  display.setCursorPos(1, 2)
  display.setTextColor(gateOpen and colors.lime or colors.red)
  display.write(gateOpen and "GATE: OPEN" or "GATE: CLOSED")
  display.setCursorPos(1, 3); display.setTextColor(connectionOkay and colors.green or colors.orange)
  display.write(connectionOkay and "BLUEMAP: ONLINE" or "DATA STALE: HOLDING")
  display.setCursorPos(1, 4); display.setTextColor(colors.white)
  display.write("Authorized nearby: " .. tostring(authorizedNearby))
  display.setCursorPos(1, 5); display.setTextColor(colors.lightGray)
  display.write("Players received: " .. tostring(players and #players or 0))
  if manualOpen then
    display.setCursorPos(1, 6); display.setTextColor(colors.yellow)
    display.write("EMERGENCY OPEN ACTIVE")
  end
  if lastError ~= "" then
    display.setCursorPos(1, 7); display.setTextColor(colors.orange)
    display.write(lastError:sub(1, width))
  end
end

local function run()
  while true do
    local now = os.clock()
    local access = loadAccess()
    local players, err = fetchPlayers()
    local manualOpen = config.manualOpenSide and config.manualOpenSide ~= "" and
      redstone.getInput(config.manualOpenSide)
    local authorizedNearby = 0
    local notifications = {}
    if players then
      lastError = ""
      local currentPassage = {}
      for _, player in ipairs(players) do
        local name = tostring(player.name or "Unknown")
        local key = name:lower()
        local authorized = access[key] ~= nil
        if authorized and (inside(player.position, config.approach) or inside(player.position, config.passage)) then
          authorizedNearby = authorizedNearby + 1
          lastAuthorizedSeen = now
        end
        if inside(player.position, config.passage) then
          currentPassage[key] = true
          if not previousPassage[key] and now >= (passageCooldown[key] or 0) then
            passageCooldown[key] = now + 60
            local p = player.position or {}
            notifications[#notifications + 1] = string.format(
              "**Canal passage:** %s | %s | X %d / Z %d",
              name, authorized and "AUTHORIZED" or "UNAUTHORIZED",
              math.floor(tonumber(p.x) or 0), math.floor(tonumber(p.z) or 0))
          end
        end
      end
      previousPassage = currentPassage
    else
      lastError = "BlueMap: " .. tostring(err)
    end

    if manualOpen then
      setGate(true)
    elseif players then
      local shouldOpen = authorizedNearby > 0 or
        (gateOpen and now - lastAuthorizedSeen < config.holdSeconds)
      setGate(shouldOpen)
    end
    -- On stale data, preserve the current gate state. A local redstone input
    -- can still open the gate, preventing a network outage from locking users out.
    if gateOpen and openingAt and not arrivalPlayed and now - openingAt >= config.travelSeconds then
      arrivalPlayed = true
      arrivedSound()
    end
    for _, notification in ipairs(notifications) do webhook(notification) end
    draw(players, authorizedNearby, players ~= nil, manualOpen)
    sleep(config.pollSeconds)
  end
end

local ok, err = xpcall(run, function(message) return tostring(message) end)
-- Preserve the last physical gate state on a crash as well. The emergency
-- input remains the operator override while the controller is running.
if not ok then error(err, 0) end
