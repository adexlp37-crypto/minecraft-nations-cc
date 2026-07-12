local trackerUrl = "https://script.google.com/macros/s/AKfycbw9DD4BqpG0ruyu86A0wn5VwZ8zbofbI16fvZu1nhu2SZ4Vyg6TGIrh2UQy763e3H2l/exec"
local waypointFile = ".hovernav_waypoints"
local refreshRate = 1
local arrivalDistance = 7
local turnDeadzone = 6
local throttleAngle = 45
local cruiseAltitude = 180
local altitudeTolerance = 2

-- Thruster wiring. The top side is intentionally never used by redstone.
local thrusterSides = {
  forward = "back",
  reverse = "front",
  -- Steering is crossed: the right thruster turns left and vice versa.
  left = "right",
  right = "left",
  lift = "bottom"
}

local autopilotArmed = false

local function allThrustersOff()
  for _, side in pairs(thrusterSides) do
    redstone.setAnalogOutput(side, 0)
  end
end

local function applyThrusters(state, levels)
  local function output(control)
    return state[control] and (levels[control] or 1) or 0
  end
  redstone.setAnalogOutput(thrusterSides.forward, output("forward"))
  redstone.setAnalogOutput(thrusterSides.reverse, output("reverse"))
  redstone.setAnalogOutput(thrusterSides.left, output("left"))
  redstone.setAnalogOutput(thrusterSides.right, output("right"))
  redstone.setAnalogOutput(thrusterSides.lift, output("lift"))
end

local function clear(target)
  target.setBackgroundColor(colors.black)
  target.setTextColor(colors.white)
  target.clear()
  target.setCursorPos(1, 1)
end

local function safeWrite(target, x, y, text, foreground, background)
  local width, height = target.getSize()
  if y < 1 or y > height or x > width then
    return
  end
  x = math.max(1, x)
  text = tostring(text):sub(1, width - x + 1)
  target.setCursorPos(x, y)
  if foreground then target.setTextColor(foreground) end
  if background then target.setBackgroundColor(background) end
  target.write(text)
end

local function center(target, y, text, foreground, background)
  local width = target.getSize()
  safeWrite(target, math.max(1, math.floor((width - #text) / 2) + 1), y,
    text, foreground, background)
end

local function loadWaypoints()
  if not fs.exists(waypointFile) then
    return {}
  end
  local file = fs.open(waypointFile, "r")
  if not file then return {} end
  local contents = file.readAll()
  file.close()
  local data = textutils.unserialize(contents)
  return type(data) == "table" and data or {}
end

local function saveWaypoints(waypoints)
  local temporary = waypointFile .. ".tmp"
  local file = assert(fs.open(temporary, "w"))
  file.write(textutils.serialize(waypoints))
  file.close()
  if fs.exists(waypointFile) then fs.delete(waypointFile) end
  fs.move(temporary, waypointFile)
end

local function fetchPlayers()
  local separator = trackerUrl:find("?", 1, true) and "&" or "?"
  local url = trackerUrl .. separator .. "hovernav=" ..
    tostring(os.epoch and os.epoch("utc") or math.random(1, 999999))

  local ok, response, err = pcall(http.get, {
    url = url,
    headers = {
      ["Accept"] = "application/json",
      ["Cache-Control"] = "no-cache"
    },
    redirect = true,
    timeout = 8
  })

  if not ok then return nil, tostring(response) end
  if not response then return nil, tostring(err or "HTTP fehlgeschlagen") end

  local body = response.readAll()
  response.close()
  local parsedOk, data = pcall(textutils.unserializeJSON, body)
  if not parsedOk or type(data) ~= "table" or type(data.players) ~= "table" then
    return nil, "Invalid tracker response"
  end
  return data.players
end

local function findPlayer(players, wanted)
  wanted = wanted:lower()
  for _, player in ipairs(players or {}) do
    if type(player.name) == "string" and player.name:lower() == wanted
      and type(player.position) == "table" then
      return {
        name = player.name,
        x = tonumber(player.position.x),
        y = tonumber(player.position.y),
        z = tonumber(player.position.z),
        yaw = player.rotation and tonumber(player.rotation.yaw) or nil
      }
    end
  end
end

local function printOnlinePlayers(players)
  local names = {}
  for _, player in ipairs(players or {}) do
    if player.name then names[#names + 1] = player.name end
  end
  table.sort(names)
  if #names == 0 then
    print("No players received from tracker.")
  else
    print("Online: " .. table.concat(names, ", "))
  end
end

local function readNumber(label)
  while true do
    write(label)
    local value = tonumber(read())
    if value then return value end
    print("Please enter a number.")
  end
end

local function configure()
  clear(term)
  print("AERO HOVERNAV // SETUP")
  print("======================")
  write("Driver name: ")
  local driverName = read()

  write("Loading BlueMap data... ")
  local players, err = fetchPlayers()
  if not players then
    print("ERROR")
    error(err, 0)
  end
  print("OK")

  if not findPlayer(players, driverName) then
    print("Driver is not currently visible in the tracker.")
    printOnlinePlayers(players)
    error("Restart HoverNav and check the driver name.", 0)
  end

  write("Destination name: ")
  local destinationName = read()
  local waypoints = loadWaypoints()
  local targetPlayer = findPlayer(players, destinationName)
  local waypoint = waypoints[destinationName:lower()]

  if not targetPlayer and not waypoint then
    print("Destination is not an online player or saved waypoint.")
    print("Enter coordinates for '" .. destinationName .. "':")
    waypoint = {
      name = destinationName,
      x = readNumber("X: "),
      y = readNumber("Y: "),
      z = readNumber("Z: ")
    }
    waypoints[destinationName:lower()] = waypoint
    saveWaypoints(waypoints)
    print("Waypoint saved.")
    sleep(0.8)
  end

  return driverName, destinationName, waypoints
end

local function bearing(dx, dz)
  local value = math.deg(math.atan(dx, -dz))
  if value < 0 then value = value + 360 end
  return value
end

local function normalizeAngle(value)
  return (value + 180) % 360 - 180
end

local function cardinal(value)
  local names = { "N", "NO", "O", "SO", "S", "SW", "W", "NW" }
  return names[math.floor((value + 22.5) / 45) % 8 + 1]
end

local function vectorLength(value)
  if type(value) ~= "table" then return nil end
  local x = tonumber(value.x or value[1])
  local y = tonumber(value.y or value[2])
  local z = tonumber(value.z or value[3])
  if not x or not y or not z then return nil end
  return math.sqrt(x * x + y * y + z * z), x, y, z
end

local function sableVelocity()
  if type(sublevel) ~= "table" or type(sublevel.getVelocity) ~= "function" then
    return nil
  end
  local inLevel = true
  if type(sublevel.isInPlotGrid) == "function" then
    local ok, result = pcall(sublevel.isInPlotGrid)
    inLevel = ok and result
  end
  if not inLevel then return nil end

  local ok, velocity = pcall(sublevel.getVelocity)
  if not ok then return nil end
  local speed, x, y, z = vectorLength(velocity)
  if not speed then return nil end
  return { speed = speed, x = x, y = y, z = z, source = "SABLE" }
end

local function derivedVelocity(current, previous, elapsed)
  if not current or not previous or not elapsed or elapsed <= 0 then return nil end
  local x = (current.x - previous.x) / elapsed
  local y = (current.y - previous.y) / elapsed
  local z = (current.z - previous.z) / elapsed
  return {
    speed = math.sqrt(x * x + y * y + z * z),
    x = x, y = y, z = z, source = "BLUEMAP"
  }
end

local function directionColor(relative)
  local difference = math.abs(relative)
  if difference <= 10 then return colors.lime end
  if difference <= 35 then return colors.yellow end
  if difference <= 90 then return colors.orange end
  return colors.red
end

local function turnText(relative)
  local difference = math.abs(relative)
  if difference <= turnDeadzone then return "FORWARD" end
  if difference >= 165 then return "TURN AROUND" end
  return relative > 0 and "TURN RIGHT" or "TURN LEFT"
end

local function steeringPulse(angle)
  angle = math.abs(angle)
  if angle <= 12 then return 0.05 end
  if angle <= 30 then return 0.08 end
  if angle <= 60 then return 0.12 end
  if angle <= 100 then return 0.16 end
  return 0.20
end

local function steeringStrength(angle)
  angle = math.abs(angle)
  if angle <= 12 then return 2 end
  if angle <= 30 then return 3 end
  if angle <= 60 then return 4 end
  if angle <= 100 then return 5 end
  return 6
end

local function approachSpeed(distance)
  if distance > 180 then return 18 end
  if distance > 90 then return 12 end
  if distance > 45 then return 7 end
  if distance > 20 then return 4 end
  return 1.5
end

local function forwardPulse(distance)
  if distance > 180 then return nil end
  if distance > 90 then return 0.35 end
  if distance > 45 then return 0.22 end
  if distance > 20 then return 0.12 end
  return 0.06
end

local function forwardStrength(distance)
  if distance > 180 then return 9 end
  if distance > 90 then return 7 end
  if distance > 45 then return 5 end
  if distance > 20 then return 4 end
  return 2
end

local function computeThrusters(relative, distance, heightDifference, speed, verticalSpeed)
  local state = {
    forward = false,
    reverse = false,
    left = false,
    right = false,
    lift = false
  }
  local pulses = {}
  local levels = { forward = 0, reverse = 0, left = 0, right = 0, lift = 0 }

  if not autopilotArmed then return state, pulses, 0, levels end

  local desiredSpeed = approachSpeed(distance)

  local function holdAltitude()
    if heightDifference > 12 then
      state.lift = true
      pulses.lift = 0.35
      levels.lift = 15
    elseif heightDifference > 6 then
      state.lift = true
      pulses.lift = 0.25
      levels.lift = 12
    elseif heightDifference > altitudeTolerance then
      state.lift = true
      pulses.lift = 0.16
      levels.lift = 9
    elseif heightDifference >= -altitudeTolerance
      and verticalSpeed < 0.15 then
      -- Stronger maintenance pulse: keep the bike around Y=180.
      state.lift = true
      pulses.lift = 0.12
      levels.lift = 5
    end
  end

  if distance <= arrivalDistance then
    state.reverse = speed > 0.5
    if state.reverse then
      pulses.reverse = 0.10
      levels.reverse = 4
    end
    holdAltitude()
    return state, pulses, 0, levels
  end

  state.left = relative < -turnDeadzone
  state.right = relative > turnDeadzone
  if state.left then
    pulses.left = steeringPulse(relative)
    levels.left = steeringStrength(relative)
  end
  if state.right then
    pulses.right = steeringPulse(relative)
    levels.right = steeringStrength(relative)
  end

  local aligned = math.abs(relative) <= throttleAngle
  state.forward = aligned and speed < desiredSpeed
  if state.forward then
    pulses.forward = forwardPulse(distance)
    levels.forward = forwardStrength(distance)
  end

  state.reverse = speed > desiredSpeed + 2
  if state.reverse then
    state.forward = false
    pulses.reverse = distance < 45 and 0.12 or 0.08
    levels.reverse = distance < 45 and 4 or 6
  end

  holdAltitude()

  return state, pulses, desiredSpeed, levels
end

local function stateText(state, levels)
  local function mark(control, label)
    return state[control] and (label .. tostring(levels[control] or 0)) or "-"
  end
  return table.concat({
    mark("forward", "F"),
    mark("reverse", "B"),
    mark("left", "L"),
    mark("right", "R"),
    mark("lift", "U")
  }, " ")
end

local function drawCompass(display, relative, color, top)
  local width, height = display.getSize()
  local cx = math.floor(width / 2)
  local cy = math.min(height - 4, top + 4)
  local radius = math.max(2, math.min(5, math.floor((height - top - 4) / 2)))

  for y = cy - radius, cy + radius do
    for x = cx - radius * 2, cx + radius * 2 do
      if x >= 1 and x <= width and y >= top and y <= height - 3 then
        local nx = (x - cx) / (radius * 2)
        local ny = (y - cy) / radius
        local edge = nx * nx + ny * ny
        if edge > 0.72 and edge < 1.28 then
          safeWrite(display, x, y, ".", colors.gray, colors.black)
        end
      end
    end
  end

  local radians = math.rad(relative)
  for step = 1, radius do
    local x = cx + math.floor(math.sin(radians) * step * 2 + 0.5)
    local y = cy - math.floor(math.cos(radians) * step + 0.5)
    safeWrite(display, x, y, step == radius and "#" or "*", color, colors.black)
  end
  safeWrite(display, cx, cy, "+", colors.white, colors.black)
end

local function chooseDisplay()
  local monitor = peripheral.find("monitor")
  if monitor then
    pcall(monitor.setTextScale, 0.5)
    return monitor, "MONITOR"
  end
  return term, "COMPUTER"
end

local function drawDashboard(display, driver, target, destinationName,
  velocity, heading, relative, distance, heightDifference, trackerError,
  thrusters, desiredSpeed, levels)
  clear(display)
  local width, height = display.getSize()
  local color = directionColor(relative)

  safeWrite(display, 1, 1, string.rep(" ", width), colors.black, colors.blue)
  center(display, 1, "AERO // HOVERNAV", colors.white, colors.blue)
  safeWrite(display, 1, 2, "PILOT: " .. driver.name, colors.cyan, colors.black)
  safeWrite(display, 1, 3, "DEST : " .. destinationName, colors.magenta, colors.black)
  safeWrite(display, 1, 4,
    "AUTOPILOT: " .. (autopilotArmed and "ARMED" or "DISARMED"),
    autopilotArmed and colors.lime or colors.red, colors.black)

  local speed = velocity and velocity.speed or 0
  local speedColor = speed > 20 and colors.red or speed > 10 and colors.orange or colors.lime
  safeWrite(display, 1, 5, ("SPEED  %5.1f b/s"):format(speed), speedColor, colors.black)
  safeWrite(display, 1, 6, ("       %5.1f km/h"):format(speed * 3.6), speedColor, colors.black)
  safeWrite(display, math.max(1, width - 14), 5,
    velocity and velocity.source or "NO DATA", colors.gray, colors.black)

  safeWrite(display, 1, 8, ("DISTANCE  %.0f blocks"):format(distance), colors.yellow, colors.black)
  safeWrite(display, 1, 9,
    ("ALTITUDE  Y %.0f / %d"):format(driver.y, cruiseAltitude),
    colors.lightBlue, colors.black)
  safeWrite(display, 1, 10, "THR: " .. stateText(thrusters, levels), colors.white, colors.black)
  safeWrite(display, math.max(1, width - 18), 6,
    ("TARGET %4.1f b/s"):format(desiredSpeed or 0), colors.gray, colors.black)

  if heading then
    safeWrite(display, math.max(1, width - 18), 8,
      ("COURSE %s %03d"):format(cardinal(heading), math.floor(heading + 0.5) % 360),
      colors.lightGray, colors.black)
  end

  local compassTop = math.min(12, math.max(11, height - 10))
  drawCompass(display, relative, color, compassTop)

  local instruction = turnText(relative)
  center(display, height - 2,
    ("%s  %+.0f DEG"):format(instruction, relative), color, colors.black)
  center(display, height - 1, "P ARM | R RESET | Q E-STOP", colors.gray, colors.black)

  if trackerError then
    center(display, height, "TRACKER: STALE DATA", colors.red, colors.black)
  else
    center(display, height, "TRACKER: ONLINE", colors.green, colors.black)
  end
end

math.randomseed(os.epoch and os.epoch("utc") or os.time())
local driverName, destinationName, waypoints = configure()
local display = chooseDisplay()
local previousPosition
local previousTime
local lastHeading
local lastDriver
local lastTarget

allThrustersOff()

local function runNavigation()
while true do
  local now = (os.epoch and os.epoch("utc") / 1000) or os.clock()
  local players, trackerError = fetchPlayers()
  local driver = players and findPlayer(players, driverName) or lastDriver
  local target = players and findPlayer(players, destinationName)
    or waypoints[destinationName:lower()] or lastTarget
  local thrusters = {
    forward = false, reverse = false, left = false, right = false, lift = false
  }
  local pulses = {}
  local desiredSpeed = 0
  local levels = { forward = 0, reverse = 0, left = 0, right = 0, lift = 0 }

  if driver and target then
    local elapsed = previousTime and (now - previousTime) or nil
    local velocity = sableVelocity() or derivedVelocity(driver, previousPosition, elapsed)

    local yawHeading = driver.yaw and ((180 + driver.yaw) % 360) or nil
    if velocity and (math.abs(velocity.x) + math.abs(velocity.z)) > 1 then
      lastHeading = bearing(velocity.x, velocity.z)
    elseif yawHeading then
      lastHeading = yawHeading
    end

    local dx = target.x - driver.x
    local dy = target.y - driver.y
    local dz = target.z - driver.z
    local horizontalDistance = math.sqrt(dx * dx + dz * dz)
    local distance = horizontalDistance
    local targetBearing = bearing(dx, dz)
    local heading = lastHeading or targetBearing
    local relative = normalizeAngle(targetBearing - heading)
    local speed = velocity and velocity.speed or 0
    local verticalSpeed = velocity and velocity.y or 0
    local controlHeightDifference = cruiseAltitude - driver.y
    if not trackerError then
      thrusters, pulses, desiredSpeed, levels =
        computeThrusters(relative, distance, controlHeightDifference, speed, verticalSpeed)
    end
    applyThrusters(thrusters, levels)

    drawDashboard(display, driver, target, destinationName, velocity,
      lastHeading, relative, distance, dy, trackerError, thrusters, desiredSpeed, levels)

    previousPosition = { x = driver.x, y = driver.y, z = driver.z }
    previousTime = now
    lastDriver = driver
    lastTarget = target
  else
    allThrustersOff()
    clear(display)
    center(display, 2, "HOVERNAV WAITING FOR TRACKER", colors.orange, colors.black)
    center(display, 4, not driver and "DRIVER NOT FOUND" or "DESTINATION NOT FOUND",
      colors.red, colors.black)
  end

  local timer = os.startTimer(refreshRate)
  local pulseTimers = {}
  if pulses then
    for control, duration in pairs(pulses) do
      if duration and thrusters[control] then
        pulseTimers[os.startTimer(duration)] = thrusterSides[control]
      end
    end
  end
  while true do
    local event, value = os.pullEvent()
    if event == "timer" then
      if pulseTimers[value] then
        redstone.setAnalogOutput(pulseTimers[value], 0)
        pulseTimers[value] = nil
      elseif value == timer then
        break
      end
    elseif event == "key" and value == keys.q then
      autopilotArmed = false
      allThrustersOff()
      clear(display)
      clear(term)
      print("HoverNav stopped. All thrusters are OFF.")
      return
    elseif event == "key" and value == keys.r then
      autopilotArmed = false
      allThrustersOff()
      clear(display)
      shell.run(shell.getRunningProgram())
      return
    elseif event == "key" and value == keys.p then
      autopilotArmed = not autopilotArmed
      if not autopilotArmed then allThrustersOff() end
    end
  end
end
end

local ok, runError = pcall(runNavigation)
autopilotArmed = false
allThrustersOff()
if not ok then
  error(runError, 0)
end
