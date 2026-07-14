local configFile = ".bluemap_tracker.cfg"
local defaultUrl = "https://script.google.com/macros/s/AKfycbw9DD4BqpG0ruyu86A0wn5VwZ8zbofbI16fvZu1nhu2SZ4Vyg6TGIrh2UQy763e3H2l/exec"

local function loadConfig()
  if not fs.exists(configFile) then
    return { url = defaultUrl, refresh = 3 }
  end
  local file = fs.open(configFile, "r")
  local config = textutils.unserialize(file.readAll())
  file.close()
  if type(config) ~= "table" then config = {} end
  config.url = config.url or defaultUrl
  config.refresh = tonumber(config.refresh) or 3
  return config
end

local function saveConfig(config)
  local file = assert(fs.open(configFile, "w"))
  file.write(textutils.serialize(config))
  file.close()
end

local function fetchPlayers(url)
  local separator = url:find("?", 1, true) and "&" or "?"
  local requestUrl = url .. separator .. "t=" ..
    tostring(os.epoch and os.epoch("utc") or math.random(1, 999999))
  local ok, response, err = pcall(http.get, {
    url = requestUrl,
    headers = { ["Accept"] = "application/json", ["Cache-Control"] = "no-cache" },
    redirect = true,
    timeout = 8
  })
  if not ok then return nil, tostring(response) end
  if not response then return nil, tostring(err or "request failed") end
  local body = response.readAll()
  response.close()
  local data = textutils.unserializeJSON(body)
  if type(data) ~= "table" or type(data.players) ~= "table" then
    return nil, "response contains no players list"
  end
  return data.players
end

local function writeAt(target, x, y, value, color)
  local width, height = target.getSize()
  if y < 1 or y > height then return end
  target.setCursorPos(x, y)
  target.setTextColor(color or colors.white)
  target.write(tostring(value):sub(1, math.max(0, width - x + 1)))
end

local args = { ... }
local config = loadConfig()
if args[1] == "setup" then
  write("BlueMap JSON/proxy URL [current]: ")
  local value = read()
  if value ~= "" then config.url = value end
  write("Refresh seconds [" .. config.refresh .. "]: ")
  value = read()
  if tonumber(value) then config.refresh = math.max(1, tonumber(value)) end
  saveConfig(config)
  print("Saved. Run bluemap_tracker")
  return
end

local monitor = peripheral.find("monitor")
local target = monitor or term
if monitor then monitor.setTextScale(1) end
local failures = 0

while true do
  target.setBackgroundColor(colors.black)
  target.clear()
  writeAt(target, 1, 1, "BLUEMAP LIVE TRACKER", colors.cyan)
  writeAt(target, 1, 2, "Updating...", colors.lightGray)

  local players, err = fetchPlayers(config.url)
  if players then
    failures = 0
    table.sort(players, function(a, b)
      return tostring(a.name):lower() < tostring(b.name):lower()
    end)
    target.clear()
    writeAt(target, 1, 1, "BLUEMAP LIVE  |  " .. #players .. " ONLINE", colors.cyan)
    writeAt(target, 1, 2, "NAME             X       Y       Z", colors.gray)
    local _, height = target.getSize()
    for index, player in ipairs(players) do
      if index + 2 > height then break end
      local position = player.position or {}
      local line = string.format("%-15s %7d %5d %7d", tostring(player.name or "?"),
        math.floor(tonumber(position.x) or 0), math.floor(tonumber(position.y) or 0),
        math.floor(tonumber(position.z) or 0))
      writeAt(target, 1, index + 2, line, index % 2 == 0 and colors.white or colors.lightGray)
    end
  else
    failures = failures + 1
    writeAt(target, 1, 4, "CONNECTION ERROR", colors.red)
    writeAt(target, 1, 5, err or "unknown error", colors.orange)
    writeAt(target, 1, 7, "Retry " .. failures .. " in " .. config.refresh .. "s", colors.lightGray)
    writeAt(target, 1, 9, "Run: bluemap_tracker setup", colors.yellow)
  end
  sleep(config.refresh)
end
