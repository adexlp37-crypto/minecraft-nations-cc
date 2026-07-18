local configFile = ".base_control.cfg"
local liveCacheFile = ".base_control_live.json"
local version = "4"

local defaultProxies = {
  "https://script.google.com/macros/s/AKfycbx11MizOXaAJ-ScN7C0-7Tuo2mjEu-urxRAnNAASwkQSa9iTUTy50JPuq8pEnZDs0F4uw/exec",
  "https://script.google.com/macros/s/AKfycbwSsBb4SokTdVDhIUv0zTJzcMT8o_hJyzo7ziEdlMOYK8gACLHOKyQPZbpPnzTESiR5Jg/exec",
  "https://script.google.com/macros/s/AKfycbyXcO7DJgloCLhteQixcPabIXHQTANvCyrMaOrLWjava--_iqFB-ItfgLTwbBpHzOV3/exec"
}

local validSides = { top=true, bottom=true, left=true, right=true, front=true, back=true }

local function defaultConfig()
  return {
    configVersion = 4,
    webhookUrl = "",
    roleIds = {
      ally="1525923176196866048",
      enemy="1525922403283243048",
      unknown="1525922526553968911"
    },
    groups = {
      member = {
        deformedrac="DeformedRac", shaycass382="ShayCass382",
        kekdex="Kekdex", arseniymuromov="arseniymuromov"
      },
      ally = { hruzi="Hruzi", ["1hygge"]="1Hygge" },
      enemy = { tbnyeet="Tbnyeet" }
    },
    doorSide = "right",
    closeSignal = true,
    emergencyOpenSide = "",
    refreshSeconds = 6,
    home = { minX=7110, maxX=7156, minY=50, maxY=120, minZ=-6459, maxZ=-6395 },
    outer = { minX=6800, maxX=7500, minY=50, maxY=2000, minZ=-7000, maxZ=-6000 },
    inner = { minX=7056, maxX=7156, minY=50, maxY=2000, minZ=-6440, maxZ=-6395 },
    proxies = defaultProxies
  }
end

local function saveConfig(config)
  local file = assert(fs.open(configFile, "w"))
  file.write(textutils.serialize(config))
  file.close()
end

local function loadConfig()
  if not fs.exists(configFile) then return nil end
  local file = fs.open(configFile, "r")
  if not file then return nil end
  local config = textutils.unserialize(file.readAll())
  file.close()
  if type(config) ~= "table" then return nil end
  config.roleIds = type(config.roleIds) == "table" and config.roleIds or {}
  if not tonumber(config.configVersion) or tonumber(config.configVersion) < 2 then
    if tostring(config.roleIds.ally or "") == "" and
        tostring(config.roleIds.enemy or "") == "" and
        tostring(config.roleIds.unknown or "") == "" then
      config.roleIds.ally = "1525923176196866048"
      config.roleIds.enemy = "1525922403283243048"
      config.roleIds.unknown = "1525922526553968911"
    end
    config.configVersion = 2
    saveConfig(config)
  end
  config.groups = type(config.groups) == "table" and config.groups or {}
  config.groups.member = type(config.groups.member) == "table" and config.groups.member or {}
  config.groups.ally = type(config.groups.ally) == "table" and config.groups.ally or {}
  config.groups.enemy = type(config.groups.enemy) == "table" and config.groups.enemy or {}
  if tonumber(config.configVersion) < 3 then
    local defaults = defaultConfig()
    if next(config.groups.member) == nil then config.groups.member = defaults.groups.member end
    if next(config.groups.ally) == nil then config.groups.ally = defaults.groups.ally end
    if next(config.groups.enemy) == nil then config.groups.enemy = defaults.groups.enemy end
    local function unset(zone)
      return type(zone) ~= "table" or
        ((tonumber(zone.minX) or 0) == 0 and (tonumber(zone.maxX) or 0) == 0 and
         (tonumber(zone.minZ) or 0) == 0 and (tonumber(zone.maxZ) or 0) == 0)
    end
    if unset(config.home) then config.home = defaults.home end
    if unset(config.outer) then config.outer = defaults.outer end
    if unset(config.inner) then config.inner = defaults.inner end
    config.configVersion = 3
    saveConfig(config)
  end
  if tonumber(config.configVersion) < 4 then
    local defaults = defaultConfig()
    config.outer = type(config.outer) == "table" and config.outer or defaults.outer
    config.inner = type(config.inner) == "table" and config.inner or defaults.inner
    config.outer.maxY = 2000
    config.inner.maxY = 2000
    config.configVersion = 4
    saveConfig(config)
  end
  config.proxies = type(config.proxies) == "table" and config.proxies or defaultProxies
  return config
end

local function prompt(label, current)
  write(label .. " [" .. tostring(current) .. "]: ")
  local answer = read()
  return answer == "" and current or answer
end

local function numberPrompt(label, current)
  while true do
    local value = tonumber(prompt(label, current))
    if value then return value end
    print("Please enter a number.")
  end
end

local function sidePrompt(label, current, allowOff, forbidden)
  while true do
    local side = prompt(label, current):lower()
    if allowOff and (side == "off" or side == "none") then return "" end
    if (side ~= "" or allowOff) and (side == "" or validSides[side]) and side ~= forbidden then
      return side
    end
    print("Use top, bottom, left, right, front, back" .. (allowOff and ", or off." or "."))
  end
end

local function zoneSetup(label, zone)
  print("")
  print(label .. " ZONE")
  zone.minX = numberPrompt("Minimum X", zone.minX)
  zone.maxX = numberPrompt("Maximum X", zone.maxX)
  zone.minY = numberPrompt("Minimum Y", zone.minY)
  zone.maxY = numberPrompt("Maximum Y", zone.maxY)
  zone.minZ = numberPrompt("Minimum Z", zone.minZ)
  zone.maxZ = numberPrompt("Maximum Z", zone.maxZ)
end

local function setup()
  local config = loadConfig() or defaultConfig()
  print("BASE CONTROL v" .. version .. " SETUP")
  config.doorSide = sidePrompt("Door redstone side", config.doorSide or "right", false)
  config.closeSignal = prompt("Does redstone ON close the doors? y/n",
    config.closeSignal == false and "n" or "y"):lower() ~= "n"
  config.emergencyOpenSide = sidePrompt("Emergency OPEN input side", config.emergencyOpenSide or "off",
    true, config.doorSide)
  config.refreshSeconds = math.max(2, numberPrompt("Player refresh seconds", config.refreshSeconds or 6))
  config.roleIds.ally = prompt("Discord ally role ID", config.roleIds.ally or "")
  config.roleIds.enemy = prompt("Discord enemy role ID", config.roleIds.enemy or "")
  config.roleIds.unknown = prompt("Discord unknown role ID", config.roleIds.unknown or "")
  zoneSetup("MEMBER HOME", config.home)
  zoneSetup("OUTER PERIMETER", config.outer)
  zoneSetup("INNER CORE", config.inner)
  saveConfig(config)
  print("")
  print("Setup saved. Next commands:")
  print("  base_control webhook")
  print("  base_control add member PlayerName")
end

local function normalizeGroup(value)
  value = tostring(value or ""):lower()
  if value == "members" then value = "member" end
  if value == "allies" then value = "ally" end
  if value == "enemies" then value = "enemy" end
  return value
end

local function printHelp()
  print("BASE CONTROL v" .. version)
  print("")
  print("Installation and configuration:")
  print("  base_control setup")
  print("  base_control webhook")
  print("  base_control door <side>")
  print("  base_control signal <on|off>")
  print("  base_control emergency <side|off>")
  print("")
  print("Player lists:")
  print("  base_control add <member|ally|enemy> <name>")
  print("  base_control remove <member|ally|enemy> <name>")
  print("  base_control list")
  print("")
  print("Discord roles:")
  print("  base_control role <ally|enemy|unknown> <role ID>")
  print("")
  print("Controller:")
  print("  base_control run")
  print("  base_control help")
  print("")
  print("Door logic: one selected redstone output controls")
  print("the Redstone Link connected to every door.")
  print("signal on = redstone ON closes all doors")
  print("signal off = redstone OFF closes all doors")
end

local args = { ... }
local command = tostring(args[1] or "run"):lower()

if command == "help" or command == "-h" or command == "--help" then printHelp(); return end
if command == "setup" then setup(); return end

local config = loadConfig()
if not config then
  config = defaultConfig()
  saveConfig(config)
  print("Existing workshop coordinates, roles and player lists loaded.")
  print("Use 'base_control setup' only if you want to change them.")
end

if command == "webhook" then
  write("Paste NEW Discord webhook with Ctrl+V: ")
  local url = read("*")
  if url == "" then error("Webhook was not changed.", 0) end
  if not url:match("^https://[^%s]+$") then error("That does not look like an HTTPS webhook URL.", 0) end
  config.webhookUrl = url
  saveConfig(config)
  print("Webhook saved locally. It is not stored on GitHub.")
  return
elseif command == "door" then
  if not args[2] or not validSides[tostring(args[2]):lower()] then
    error("Usage: base_control door <top|bottom|left|right|front|back>", 0)
  end
  local side = tostring(args[2]):lower()
  if side == config.emergencyOpenSide then
    error("Door output cannot use the emergency input side.", 0)
  end
  config.doorSide = side
  saveConfig(config)
  print("All-door Redstone Link output side: " .. side)
  return
elseif command == "signal" then
  local value = tostring(args[2] or ""):lower()
  if value ~= "on" and value ~= "off" then
    error("Usage: base_control signal <on|off>", 0)
  end
  config.closeSignal = value == "on"
  saveConfig(config)
  print(value == "on" and "Redstone ON closes all doors." or "Redstone OFF closes all doors.")
  return
elseif command == "emergency" then
  local side = tostring(args[2] or ""):lower()
  if side == "off" or side == "none" then side = "" end
  if side ~= "" and (not validSides[side] or side == config.doorSide) then
    error("Usage: base_control emergency <side|off>; do not use the door output side.", 0)
  end
  config.emergencyOpenSide = side
  saveConfig(config)
  print(side == "" and "Emergency OPEN input disabled." or ("Emergency OPEN input side: " .. side))
  return
elseif command == "role" then
  local group = normalizeGroup(args[2])
  if group ~= "ally" and group ~= "enemy" and group ~= "unknown" then
    error("Usage: base_control role <ally|enemy|unknown> <DiscordRoleID>", 0)
  end
  if not args[3] then error("Missing Discord role ID.", 0) end
  config.roleIds[group] = args[3]
  saveConfig(config)
  print("Role ID updated.")
  return
elseif command == "add" or command == "remove" then
  local group = normalizeGroup(args[2])
  local name = args[3]
  if not config.groups[group] or not name then
    error("Usage: base_control " .. command .. " <member|ally|enemy> <PlayerName>", 0)
  end
  local key = name:lower()
  if command == "add" then
    for _, entries in pairs(config.groups) do entries[key] = nil end
    config.groups[group][key] = name
  else
    config.groups[group][key] = nil
  end
  saveConfig(config)
  print(command == "add" and (name .. " added as " .. group .. ".") or (name .. " removed."))
  return
elseif command == "list" then
  for _, group in ipairs({ "member", "ally", "enemy" }) do
    print(group:upper() .. "S")
    local values = {}
    for _, name in pairs(config.groups[group]) do values[#values + 1] = name end
    table.sort(values, function(a, b) return a:lower() < b:lower() end)
    if #values == 0 then print("  (none)") end
    for _, name in ipairs(values) do print("  " .. name) end
  end
  return
elseif command ~= "run" then
  printHelp()
  return
end

local function inZone(position, zone)
  if type(position) ~= "table" or type(zone) ~= "table" then return false end
  local x, y, z = tonumber(position.x), tonumber(position.y), tonumber(position.z)
  if not x or not y or not z then return false end
  return x >= math.min(zone.minX, zone.maxX) and x <= math.max(zone.minX, zone.maxX) and
    y >= math.min(zone.minY, zone.maxY) and y <= math.max(zone.minY, zone.maxY) and
    z >= math.min(zone.minZ, zone.maxZ) and z <= math.max(zone.minZ, zone.maxZ)
end

local activeProxy = 1
local function fetchPlayers()
  local failures = {}
  for offset = 0, #config.proxies - 1 do
    local index = (activeProxy + offset - 1) % #config.proxies + 1
    local proxy = config.proxies[index]
    local separator = proxy:find("?", 1, true) and "&" or "?"
    local url = proxy .. separator .. "basecontrol=" ..
      tostring(os.epoch and os.epoch("utc") or math.random(1, 999999))
    local ok, response, err = pcall(http.get, {
      url=url, redirect=true,
      headers={ ["Accept"]="application/json", ["Cache-Control"]="no-cache" }
    })
    if ok and response then
      local body = response.readAll(); response.close()
      local payload = textutils.unserializeJSON(body)
      if type(payload) == "table" and type(payload.players) == "table" and not payload.error then
        activeProxy = index
        return payload.players, nil, payload
      end
      failures[#failures + 1] = "G" .. index .. ": " ..
        tostring(type(payload) == "table" and payload.error or "invalid JSON")
    else
      failures[#failures + 1] = "G" .. index .. ": " .. tostring(ok and err or response)
    end
  end
  return nil, table.concat(failures, " | ")
end

local function saveLiveData(payload)
  payload.hubUpdatedAt = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)
  payload.hubProxy = activeProxy
  local temporary = liveCacheFile .. ".tmp"
  local file = assert(fs.open(temporary, "w"))
  file.write(textutils.serializeJSON(payload))
  file.close()
  if fs.exists(liveCacheFile) then fs.delete(liveCacheFile) end
  fs.move(temporary, liveCacheFile)
end

local function category(name)
  local key = tostring(name or ""):lower()
  if config.groups.member[key] then return "member" end
  if config.groups.ally[key] then return "ally" end
  if config.groups.enemy[key] then return "enemy" end
  return "unknown"
end

local function rounded(position)
  return math.floor((tonumber(position.x) or 0) + 0.5),
    math.floor((tonumber(position.y) or 0) + 0.5),
    math.floor((tonumber(position.z) or 0) + 0.5)
end

local function roleTag(group)
  local roleId = tostring(config.roleIds[group] or "")
  if roleId == "" then return "[" .. group:upper() .. "]", nil end
  return "<@&" .. roleId .. "> [" .. group:upper() .. "]", roleId
end

local function sendWebhook(name, title, zoneName, position, color, ping)
  if not config.webhookUrl or config.webhookUrl == "" then return end
  local group = category(name)
  local tag, roleId = roleTag(group)
  local x, y, z = rounded(position or {})
  local payload = {
    username = "BaseGuard",
    content = ping and tag or "",
    embeds = {{
      title=title, color=color,
      fields={
        {name="Player", value=tostring(name), inline=true},
        {name="Category", value=tag, inline=true},
        {name="Zone", value=tostring(zoneName), inline=true},
        {name="Position", value=string.format("X: %d | Y: %d | Z: %d", x, y, z), inline=false},
        {name="Time", value=os.date("%H:%M:%S"), inline=false}
      }
    }},
    allowed_mentions = { roles = ping and roleId and { roleId } or {} }
  }
  local ok, response = pcall(http.post, config.webhookUrl,
    textutils.serializeJSON(payload), { ["Content-Type"]="application/json", ["User-Agent"]="CC-BaseGuard/1.0" })
  if ok and response then response.close()
  else print("[WEBHOOK ERROR] " .. tostring(response)) end
end

local speaker = peripheral.find("speaker")
local tracked = {}
local doorClosed = redstone.getOutput(config.doorSide) == config.closeSignal
local lastStatus, lastError = "STARTING", ""

local function sound(zone)
  if not speaker then return end
  if zone == "inner" then speaker.playSound("minecraft:block.bell.use", 1, 0.7)
  else speaker.playSound("minecraft:block.note_block.pling", 0.8, 0.8) end
end

local function setDoor(closed)
  if doorClosed == closed then return end
  doorClosed = closed
  redstone.setOutput(config.doorSide, closed == config.closeSignal)
  print(os.date("[%H:%M:%S] ") .. (closed and "Doors CLOSED." or "Doors OPEN."))
end

local function process(players)
  local current, membersHome = {}, 0
  for _, player in ipairs(players) do
    local name, position = tostring(player.name or "Unknown"), player.position
    local group = category(name)
    if group == "member" and inZone(position, config.home) then membersHome = membersHome + 1 end
    if group ~= "member" and type(position) == "table" then
      local zone = inZone(position, config.inner) and "inner" or
        (inZone(position, config.outer) and "outer" or nil)
      if zone then current[name:lower()] = { name=name, zone=zone, position=position } end
    end
  end

  for key, contact in pairs(current) do
    local previous = tracked[key]
    if not previous then
      local inner = contact.zone == "inner"
      print(os.date("[%H:%M:%S] ") .. contact.name .. " entered " .. contact.zone .. ".")
      sound(contact.zone)
      sendWebhook(contact.name,
        inner and "CRITICAL: SPOTTED IN INNER CORE" or "WARNING: ENTERED PERIMETER",
        inner and "Inner Core" or "Outer Perimeter", contact.position,
        inner and 16711680 or 16753920, true)
    elseif previous.zone ~= contact.zone then
      local inner = contact.zone == "inner"
      print(os.date("[%H:%M:%S] ") .. contact.name .. " moved to " .. contact.zone .. ".")
      sound(contact.zone)
      sendWebhook(contact.name,
        inner and "CRITICAL: BREACHED INNER CORE" or "UPDATE: RETREATED TO PERIMETER",
        inner and "Inner Core" or "Outer Perimeter", contact.position,
        inner and 16711680 or 16753920, inner)
    end
  end
  for key, previous in pairs(tracked) do
    if not current[key] then
      print(os.date("[%H:%M:%S] ") .. previous.name .. " left the monitored area.")
      sendWebhook(previous.name, "CLEAR: TARGET LEFT AREA", "Outside", previous.position, 65280, false)
    end
  end
  tracked = current
  return membersHome
end

local function controllerLoop()
  print("Base Control v" .. version .. " active. One proxy feed supplies security and dashboard.")
  while true do
    local players, err, payload = fetchPlayers()
    local emergencyOpen = config.emergencyOpenSide ~= "" and redstone.getInput(config.emergencyOpenSide)
    if players then
      lastError = ""
      saveLiveData(payload)
      local membersHome = process(players)
      if emergencyOpen then setDoor(false)
      else setDoor(membersHome == 0) end
      lastStatus = string.format("G%d | %d online | %d home | %d contacts",
        activeProxy, #players, membersHome,
        (function() local n=0 for _ in pairs(tracked) do n=n+1 end return n end)())
    else
      -- Network failure preserves the physical door state instead of locking users out.
      lastError = tostring(err)
      if emergencyOpen then setDoor(false) end
      lastStatus = "DATA STALE - HOLDING DOOR STATE"
    end
    term.setTextColor(lastError == "" and colors.lime or colors.orange)
    print(os.date("[%H:%M:%S] ") .. lastStatus)
    if lastError ~= "" then print(lastError) end
    sleep(config.refreshSeconds)
  end
end

local function dashboardLoop()
  if not fs.exists("team_dashboard.lua") then
    print("Dashboard missing. Run: updater base")
    return
  end
  shell.run("team_dashboard", "local")
end

if peripheral.find("monitor") and fs.exists("team_dashboard.lua") then
  parallel.waitForAll(controllerLoop, dashboardLoop)
else
  controllerLoop()
end
