local function hasMethod(name, wanted)
  for _, method in ipairs(peripheral.getMethods(name) or {}) do
    if method == wanted then return true end
  end
  return false
end

local function findRadar()
  for _, name in ipairs(peripheral.getNames()) do
    if hasMethod(name, "getTracks") then return name end
  end
end

local function magnitude(vector)
  if type(vector) ~= "table" then return 0 end
  local x, y, z = tonumber(vector.x) or 0, tonumber(vector.y) or 0, tonumber(vector.z) or 0
  return math.sqrt(x * x + y * y + z * z)
end

local function listTracks(raw)
  local tracks = {}
  for id, track in pairs(type(raw) == "table" and raw or {}) do
    if type(track) == "table" then
      track._id = track.id or id
      tracks[#tracks + 1] = track
    end
  end
  table.sort(tracks, function(a, b)
    return magnitude(a.position) < magnitude(b.position)
  end)
  return tracks
end

local function line(target, y, text, color)
  local width, height = target.getSize()
  if y > height then return end
  target.setCursorPos(1, y)
  target.setTextColor(color or colors.white)
  target.write(tostring(text):sub(1, width))
end

local requestedName = ({ ... })[1]
local radarName = requestedName or findRadar()
if radarName and not peripheral.isPresent(radarName) then
  error("Peripheral not found: " .. radarName, 0)
end
if not radarName then
  error("No connected Create Radar peripheral with getTracks() found. Attach a wired modem and enable it.", 0)
end

local monitor = peripheral.find("monitor")
local target = monitor or term
if monitor then monitor.setTextScale(1) end

while true do
  target.setBackgroundColor(colors.black)
  target.clear()
  line(target, 1, "CREATE RADAR  |  " .. radarName, colors.orange)
  local ok, rawTracks = pcall(peripheral.call, radarName, "getTracks")
  if not ok then
    line(target, 3, "RADAR ERROR", colors.red)
    line(target, 4, rawTracks, colors.orange)
  else
    local tracks = listTracks(rawTracks)
    line(target, 2, #tracks .. " TRACKS   TYPE / POSITION / SPEED", colors.lightGray)
    local _, height = target.getSize()
    for index, track in ipairs(tracks) do
      if index + 2 > height then break end
      local p = track.position or {}
      local text = string.format("%-11s %6d %5d %6d  %4.1f",
        tostring(track.category or track.entityType or "UNKNOWN"),
        math.floor(tonumber(p.x) or 0), math.floor(tonumber(p.y) or 0),
        math.floor(tonumber(p.z) or 0), magnitude(track.velocity))
      line(target, index + 2, text, index % 2 == 0 and colors.white or colors.lightGray)
    end
  end
  sleep(0.5)
end
