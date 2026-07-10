local trackerUrl = "https://script.google.com/macros/s/AKfycbw9DD4BqpG0ruyu86A0wn5VwZ8zbofbI16fvZu1nhu2SZ4Vyg6TGIrh2UQy763e3H2l/exec"
local waypointFile = ".hovernav_waypoints"
local refreshRate = 1

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
    return nil, "Ungueltige Tracker-Antwort"
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
        z = tonumber(player.position.z)
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
    print("Keine Spieler vom Tracker empfangen.")
  else
    print("Online: " .. table.concat(names, ", "))
  end
end

local function readNumber(label)
  while true do
    write(label)
    local value = tonumber(read())
    if value then return value end
    print("Bitte eine Zahl eingeben.")
  end
end

local function configure()
  clear(term)
  print("AERO HOVERNAV // SETUP")
  print("======================")
  write("Fahrername: ")
  local driverName = read()

  write("Lade BlueMap-Daten... ")
  local players, err = fetchPlayers()
  if not players then
    print("FEHLER")
    error(err, 0)
  end
  print("OK")

  if not findPlayer(players, driverName) then
    print("Fahrer ist momentan nicht im Tracker.")
    printOnlinePlayers(players)
    error("HoverNav erneut starten und Namen pruefen.", 0)
  end

  write("Zielname: ")
  local destinationName = read()
  local waypoints = loadWaypoints()
  local targetPlayer = findPlayer(players, destinationName)
  local waypoint = waypoints[destinationName:lower()]

  if not targetPlayer and not waypoint then
    print("Ziel ist kein Online-Spieler und noch nicht gespeichert.")
    print("Koordinaten fuer '" .. destinationName .. "' eingeben:")
    waypoint = {
      name = destinationName,
      x = readNumber("X: "),
      y = readNumber("Y: "),
      z = readNumber("Z: ")
    }
    waypoints[destinationName:lower()] = waypoint
    saveWaypoints(waypoints)
    print("Ort gespeichert.")
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
  if difference <= 8 then return "GERADEAUS" end
  if difference >= 165 then return "UMDREHEN" end
  return relative > 0 and "RECHTS" or "LINKS"
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
  velocity, heading, relative, distance, heightDifference, trackerError)
  clear(display)
  local width, height = display.getSize()
  local color = directionColor(relative)

  safeWrite(display, 1, 1, string.rep(" ", width), colors.black, colors.blue)
  center(display, 1, "AERO // HOVERNAV", colors.white, colors.blue)
  safeWrite(display, 1, 2, "PILOT: " .. driver.name, colors.cyan, colors.black)
  safeWrite(display, 1, 3, "ZIEL : " .. destinationName, colors.magenta, colors.black)

  local speed = velocity and velocity.speed or 0
  local speedColor = speed > 20 and colors.red or speed > 10 and colors.orange or colors.lime
  safeWrite(display, 1, 5, ("SPEED  %5.1f b/s"):format(speed), speedColor, colors.black)
  safeWrite(display, 1, 6, ("       %5.1f km/h"):format(speed * 3.6), speedColor, colors.black)
  safeWrite(display, math.max(1, width - 14), 5,
    velocity and velocity.source or "KEINE DATEN", colors.gray, colors.black)

  safeWrite(display, 1, 8, ("DIST   %.0f m"):format(distance), colors.white, colors.black)
  safeWrite(display, 1, 9, ("HOEHE  %+.0f m"):format(heightDifference), colors.lightBlue, colors.black)

  if heading then
    safeWrite(display, math.max(1, width - 18), 8,
      ("KURS %s %03d"):format(cardinal(heading), math.floor(heading + 0.5) % 360),
      colors.lightGray, colors.black)
  end

  local compassTop = math.min(11, math.max(10, height - 11))
  drawCompass(display, relative, color, compassTop)

  local instruction = turnText(relative)
  center(display, height - 2,
    ("%s  %+.0f Grad"):format(instruction, relative), color, colors.black)
  center(display, height - 1, "Q Ende | R Neues Ziel", colors.gray, colors.black)

  if trackerError then
    center(display, height, "TRACKER: ALTE DATEN", colors.red, colors.black)
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

while true do
  local now = (os.epoch and os.epoch("utc") / 1000) or os.clock()
  local players, trackerError = fetchPlayers()
  local driver = players and findPlayer(players, driverName) or lastDriver
  local target = players and findPlayer(players, destinationName)
    or waypoints[destinationName:lower()] or lastTarget

  if driver and target then
    local elapsed = previousTime and (now - previousTime) or nil
    local velocity = sableVelocity() or derivedVelocity(driver, previousPosition, elapsed)

    if velocity and (math.abs(velocity.x) + math.abs(velocity.z)) > 0.15 then
      lastHeading = bearing(velocity.x, velocity.z)
    end

    local dx = target.x - driver.x
    local dy = target.y - driver.y
    local dz = target.z - driver.z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local targetBearing = bearing(dx, dz)
    local heading = lastHeading or targetBearing
    local relative = normalizeAngle(targetBearing - heading)

    drawDashboard(display, driver, target, destinationName, velocity,
      lastHeading, relative, distance, dy, trackerError)

    previousPosition = { x = driver.x, y = driver.y, z = driver.z }
    previousTime = now
    lastDriver = driver
    lastTarget = target
  else
    clear(display)
    center(display, 2, "HOVERNAV WARTE AUF TRACKER", colors.orange, colors.black)
    center(display, 4, not driver and "FAHRER NICHT GEFUNDEN" or "ZIEL NICHT GEFUNDEN",
      colors.red, colors.black)
  end

  local timer = os.startTimer(refreshRate)
  while true do
    local event, value = os.pullEvent()
    if event == "timer" and value == timer then
      break
    elseif event == "key" and value == keys.q then
      clear(display)
      clear(term)
      print("HoverNav beendet.")
      return
    elseif event == "key" and value == keys.r then
      clear(display)
      shell.run(shell.getRunningProgram())
      return
    end
  end
end
