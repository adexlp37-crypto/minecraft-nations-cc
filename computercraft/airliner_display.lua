local version = "1.0"
local refreshRate = 0.25

local monitor = peripheral.find("monitor")
if not monitor then error("Connect an Advanced Monitor first.", 0) end
monitor.setTextScale(0.5)

local width, height = monitor.getSize()
if width < 38 or height < 20 then
  error("Airliner Display needs a larger Advanced Monitor.", 0)
end

pcall(monitor.setPaletteColor, colors.blue, 0.02, 0.18, 0.55)
pcall(monitor.setPaletteColor, colors.lightBlue, 0.20, 0.62, 1.00)
pcall(monitor.setPaletteColor, colors.brown, 0.34, 0.17, 0.05)

local page = "flight"
local buttons = {}
local startedAt = os.epoch and os.epoch("utc") / 1000 or os.clock()
local lastTrack = 0
local lastTelemetry = nil
local aeroApi = type(aero) == "table" and aero or aerodynamics

local function safeCall(api, method, ...)
  if type(api) ~= "table" or type(api[method]) ~= "function" then return nil end
  local ok, a, b, c = pcall(api[method], ...)
  if not ok then return nil end
  return a, b, c
end

local function components(value)
  if type(value) ~= "table" then return nil, nil, nil end
  local x = tonumber(value.x or value[1])
  local y = tonumber(value.y or value[2])
  local z = tonumber(value.z or value[3])
  return x, y, z
end

local function magnitude(value)
  local x, y, z = components(value)
  if not x then return 0 end
  return math.sqrt(x * x + y * y + z * z)
end

local function degrees(value)
  value = tonumber(value) or 0
  if math.abs(value) <= math.pi * 2 + 0.01 then return math.deg(value) end
  return value
end

local function orientationAngles(orientation)
  if type(orientation) ~= "table" or type(orientation.toEuler) ~= "function" then
    return 0, 0, 0
  end
  local ok, pitch, yaw, roll = pcall(function() return orientation:toEuler() end)
  if not ok then return 0, 0, 0 end
  return degrees(pitch), degrees(yaw), degrees(roll)
end

local function trackFromVelocity(x, z)
  if not x or not z or math.abs(x) + math.abs(z) < 0.15 then return lastTrack end
  local track = math.deg(math.atan(x, -z))
  if track < 0 then track = track + 360 end
  lastTrack = track
  return track
end

local function cardinal(angle)
  local names = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
  return names[math.floor((angle + 22.5) / 45) % 8 + 1]
end

local function collectTelemetry()
  if type(sublevel) ~= "table" or type(sublevel.isInPlotGrid) ~= "function" then
    return nil, "CC:SABLE API NOT FOUND"
  end
  local inSublevel = safeCall(sublevel, "isInPlotGrid")
  if not inSublevel then return nil, "COMPUTER IS NOT ON A SABLE OBJECT" end

  local pose = safeCall(sublevel, "getLogicalPose")
  if type(pose) ~= "table" then return nil, "NO SABLE POSE DATA" end
  local position = pose.position
  local px, py, pz = components(position)
  if not px then return nil, "INVALID SABLE POSITION" end

  local velocity = safeCall(sublevel, "getVelocity") or safeCall(sublevel, "getLinearVelocity")
  local vx, vy, vz = components(velocity)
  vx, vy, vz = vx or 0, vy or 0, vz or 0
  local angular = safeCall(sublevel, "getAngularVelocity")
  local ax, ay, az = components(angular)
  ax, ay, az = ax or 0, ay or 0, az or 0
  local pitch, yaw, roll = orientationAngles(pose.orientation)
  local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
  local groundSpeed = math.sqrt(vx * vx + vz * vz)
  local track = trackFromVelocity(vx, vz)
  local pressure = safeCall(aeroApi, "getAirPressure", position)
  local gravity = safeCall(aeroApi, "getGravity")
  local centerOfMass = safeCall(sublevel, "getCenterOfMass")

  return {
    name = tostring(safeCall(sublevel, "getName") or "UNNAMED AIRCRAFT"),
    uuid = tostring(safeCall(sublevel, "getUniqueId") or "UNKNOWN"),
    position = position,
    x = px, y = py, z = pz,
    velocity = velocity,
    vx = vx, vy = vy, vz = vz,
    speed = speed,
    groundSpeed = groundSpeed,
    track = track,
    pitch = pitch, yaw = yaw, roll = roll,
    angular = angular,
    angularSpeed = math.sqrt(ax * ax + ay * ay + az * az),
    mass = tonumber(safeCall(sublevel, "getMass")) or 0,
    pressure = tonumber(pressure),
    gravity = gravity,
    gravityStrength = magnitude(gravity),
    centerOfMass = centerOfMass
  }
end

local function flightPhase(data)
  if data.speed < 0.25 then return "PARKED", colors.lightGray end
  if data.vy > 1.2 then return "CLIMBING", colors.lime end
  if data.vy < -1.2 then return "DESCENDING", colors.orange end
  if data.groundSpeed < 3 then return "LOW SPEED", colors.yellow end
  if data.angularSpeed > 0.45 or math.abs(data.roll) > 18 or math.abs(data.pitch) > 15 then
    return "MANEUVERING", colors.red
  end
  return "CRUISING", colors.lightBlue
end

local function cabinStatus(data)
  local phase = flightPhase(data)
  if phase == "PARKED" then return "WELCOME ABOARD", colors.lime end
  if phase == "CLIMBING" or phase == "DESCENDING" or phase == "MANEUVERING" then
    return "FASTEN SEATBELTS", colors.orange
  end
  return "CABIN STATUS: NORMAL", colors.lime
end

local function formatDuration(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  return string.format("%02d:%02d:%02d", math.floor(seconds / 3600),
    math.floor(seconds / 60) % 60, seconds % 60)
end

local function formatLarge(value)
  value = tonumber(value) or 0
  if math.abs(value) >= 1000000 then return string.format("%.2fM", value / 1000000) end
  if math.abs(value) >= 1000 then return string.format("%.1fk", value / 1000) end
  return string.format("%.1f", value)
end

local function fill(x1, y1, x2, y2, background)
  x1, y1 = math.max(1, x1), math.max(1, y1)
  x2, y2 = math.min(width, x2), math.min(height, y2)
  if x1 > x2 or y1 > y2 then return end
  monitor.setBackgroundColor(background)
  for y = y1, y2 do
    monitor.setCursorPos(x1, y)
    monitor.write(string.rep(" ", x2 - x1 + 1))
  end
end

local function writeAt(x, y, text, foreground, background)
  if y < 1 or y > height or x > width then return end
  monitor.setCursorPos(math.max(1, x), y)
  monitor.setTextColor(foreground or colors.white)
  monitor.setBackgroundColor(background or colors.black)
  monitor.write(tostring(text):sub(1, math.max(0, width - x + 1)))
end

local function center(x1, x2, y, text, foreground, background)
  text = tostring(text)
  writeAt(x1 + math.max(0, math.floor((x2 - x1 + 1 - #text) / 2)), y,
    text, foreground, background)
end

local function addButton(action, x1, y1, x2, y2, label, active)
  local background = active and colors.lightBlue or colors.gray
  local foreground = active and colors.black or colors.white
  fill(x1, y1, x2, y2, background)
  center(x1, x2, math.floor((y1 + y2) / 2), label, foreground, background)
  buttons[#buttons + 1] = { action=action, x1=x1, y1=y1, x2=x2, y2=y2 }
end

local function drawHeader(data, errorText)
  fill(1, 1, width, 1, colors.blue)
  fill(1, 2, width, 2, colors.white)
  local title = data and data.name:upper() or "AIRLINER TELEMETRY"
  center(1, width, 1, title, colors.white, colors.blue)
  center(1, width, 2, "SABLE FLIGHT INFORMATION SYSTEM  v" .. version,
    colors.blue, colors.white)
  center(1, width, 3, errorText or "LIVE AIRFRAME TELEMETRY",
    errorText and colors.red or colors.lime, colors.black)
end

local function drawHorizon(x1, y1, x2, y2, pitch, roll)
  local cx = math.floor((x1 + x2) / 2)
  local cy = math.floor((y1 + y2) / 2)
  local limitedRoll = math.max(-45, math.min(45, roll))
  local slope = math.tan(math.rad(limitedRoll)) * 0.45
  local pitchShift = math.max(-5, math.min(5, pitch / 4))

  for y = y1, y2 do
    for x = x1, x2 do
      local horizon = cy + pitchShift + slope * (x - cx)
      local delta = y - horizon
      local background = delta < 0 and colors.lightBlue or colors.brown
      local character = math.abs(delta) < 0.6 and "-" or " "
      writeAt(x, y, character, colors.white, background)
    end
  end

  writeAt(cx - 4, cy, "---+---", colors.yellow,
    cy < cy + pitchShift and colors.lightBlue or colors.brown)
  center(x1, x2, y1, string.format("PITCH %+04.0f", pitch), colors.white, colors.blue)
  center(x1, x2, y2, string.format("ROLL  %+04.0f", roll), colors.white, colors.blue)
end

local function drawFlight(data)
  local phase, phaseColor = flightPhase(data)
  local cabin, cabinColor = cabinStatus(data)
  writeAt(2, 4, "FLIGHT PHASE", colors.gray, colors.black)
  writeAt(2, 5, phase, phaseColor, colors.black)
  writeAt(2, 7, "ALTITUDE", colors.gray, colors.black)
  writeAt(2, 8, string.format("Y %7.1f", data.y), colors.lightBlue, colors.black)
  writeAt(2, 10, "VERTICAL SPEED", colors.gray, colors.black)
  writeAt(2, 11, string.format("%+7.2f b/s", data.vy),
    math.abs(data.vy) > 2 and colors.orange or colors.white, colors.black)
  writeAt(2, 13, "POSITION", colors.gray, colors.black)
  writeAt(2, 14, string.format("X %7.0f", data.x), colors.white, colors.black)
  writeAt(2, 15, string.format("Z %7.0f", data.z), colors.white, colors.black)

  local horizonX1 = math.max(15, math.floor(width * 0.26))
  local horizonX2 = math.min(width - 15, math.floor(width * 0.74))
  drawHorizon(horizonX1, 4, horizonX2, height - 7, data.pitch, data.roll)

  local right = horizonX2 + 2
  writeAt(right, 4, "GROUND SPEED", colors.gray, colors.black)
  writeAt(right, 5, string.format("%6.1f km/h", data.groundSpeed * 3.6), colors.lime, colors.black)
  writeAt(right, 6, string.format("%6.1f b/s", data.groundSpeed), colors.white, colors.black)
  writeAt(right, 8, "TRACK", colors.gray, colors.black)
  writeAt(right, 9, string.format("%s  %03d DEG", cardinal(data.track),
    math.floor(data.track + 0.5) % 360), colors.yellow, colors.black)
  writeAt(right, 11, "AIR PRESSURE", colors.gray, colors.black)
  writeAt(right, 12, data.pressure and string.format("%.3f", data.pressure) or "N/A",
    colors.white, colors.black)
  writeAt(right, 14, "FLIGHT TIME", colors.gray, colors.black)
  local now = os.epoch and os.epoch("utc") / 1000 or os.clock()
  writeAt(right, 15, formatDuration(now - startedAt), colors.lightBlue, colors.black)

  fill(2, height - 5, width - 1, height - 4, colors.gray)
  center(2, width - 1, height - 5, cabin, cabinColor, colors.gray)
  local pulse = math.floor(os.clock() * 4) % math.max(1, width - 6)
  writeAt(3 + pulse, height - 4, "*", cabinColor, colors.gray)
end

local function drawAirframe(data)
  center(1, width, 4, "AIRFRAME / PHYSICS DATA", colors.lightBlue, colors.black)
  local left, right = 3, math.floor(width / 2) + 2
  local y = 6
  writeAt(left, y, "SABLE OBJECT", colors.gray, colors.black)
  writeAt(left, y + 1, data.name, colors.white, colors.black)
  writeAt(left, y + 3, "MASS", colors.gray, colors.black)
  writeAt(left, y + 4, formatLarge(data.mass) .. " units", colors.yellow, colors.black)
  writeAt(left, y + 6, "CENTER OF MASS", colors.gray, colors.black)
  local cx, cy, cz = components(data.centerOfMass)
  writeAt(left, y + 7, cx and string.format("%.1f / %.1f / %.1f", cx, cy, cz) or "N/A",
    colors.white, colors.black)
  writeAt(left, y + 9, "UUID", colors.gray, colors.black)
  writeAt(left, y + 10, data.uuid:sub(1, math.floor(width / 2) - 5), colors.lightGray, colors.black)

  writeAt(right, y, "TOTAL VELOCITY", colors.gray, colors.black)
  writeAt(right, y + 1, string.format("%.2f b/s", data.speed), colors.lime, colors.black)
  writeAt(right, y + 3, "VELOCITY VECTOR", colors.gray, colors.black)
  writeAt(right, y + 4, string.format("%+.2f / %+.2f / %+.2f", data.vx, data.vy, data.vz),
    colors.white, colors.black)
  writeAt(right, y + 6, "ANGULAR RATE", colors.gray, colors.black)
  writeAt(right, y + 7, string.format("%.3f", data.angularSpeed), colors.white, colors.black)
  writeAt(right, y + 9, "GRAVITY", colors.gray, colors.black)
  writeAt(right, y + 10, string.format("%.3f", data.gravityStrength), colors.white, colors.black)

  fill(2, height - 6, width - 1, height - 4, colors.gray)
  center(2, width - 1, height - 5,
    string.format("POSE  P %+05.1f   Y %+05.1f   R %+05.1f", data.pitch, data.yaw, data.roll),
    colors.lightBlue, colors.gray)
end

local function drawFooter()
  addButton("flight", 2, height - 2, math.floor(width / 2) - 1, height,
    "FLIGHT INFO", page == "flight")
  addButton("airframe", math.floor(width / 2) + 1, height - 2, width - 1, height,
    "AIRFRAME DATA", page == "airframe")
end

local function draw(data, errorText)
  width, height = monitor.getSize()
  buttons = {}
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()
  drawHeader(data, errorText)
  if data then
    if page == "airframe" then drawAirframe(data) else drawFlight(data) end
  else
    center(1, width, math.floor(height / 2) - 1, "NO AIRFRAME TELEMETRY", colors.orange, colors.black)
    center(1, width, math.floor(height / 2) + 1,
      "PLACE THIS COMPUTER ON THE AIRCRAFT", colors.white, colors.black)
  end
  drawFooter()
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Airliner Display v" .. version)
print("Reading the aircraft directly through CC:Sable.")
print("Touch the monitor tabs to change pages.")
print("Hold Ctrl+T to stop.")

local function main()
  local telemetry, telemetryError = collectTelemetry()
  if telemetry then lastTelemetry = telemetry end
  draw(telemetry or lastTelemetry, telemetryError)
  local timer = os.startTimer(refreshRate)
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "timer" and a == timer then
      telemetry, telemetryError = collectTelemetry()
      if telemetry then lastTelemetry = telemetry end
      draw(telemetry or lastTelemetry, telemetryError)
      timer = os.startTimer(refreshRate)
    elseif event == "monitor_touch" and a == peripheral.getName(monitor) then
      for index = #buttons, 1, -1 do
        local button = buttons[index]
        if b >= button.x1 and b <= button.x2 and c >= button.y1 and c <= button.y2 then
          page = button.action
          draw(lastTelemetry, telemetryError)
          break
        end
      end
    elseif event == "monitor_resize" then
      error("Monitor size changed. Restart airliner_display.", 0)
    end
  end
end

local ok, failure = pcall(main)
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()
monitor.setCursorPos(1, 1)
if not ok and tostring(failure) ~= "Terminated" then error(failure, 0) end
