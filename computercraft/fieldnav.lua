local dataFile = ".fieldnav.db"
local beaconProtocol = "minecraft_nations_position"

local function clear()
  term.clear()
  term.setCursorPos(1, 1)
end

local function pause()
  print()
  write("Enter zum Fortfahren...")
  read()
end

local function loadTargets()
  if not fs.exists(dataFile) then
    return {}
  end

  local file = fs.open(dataFile, "r")
  if not file then
    return {}
  end

  local contents = file.readAll()
  file.close()
  local targets = textutils.unserialize(contents)
  return type(targets) == "table" and targets or {}
end

local function saveTargets(targets)
  local temporary = dataFile .. ".tmp"
  local file = assert(fs.open(temporary, "w"))
  file.write(textutils.serialize(targets))
  file.close()

  if fs.exists(dataFile) then
    fs.delete(dataFile)
  end
  fs.move(temporary, dataFile)
end

local function locate(timeout)
  local x, y, z = gps.locate(timeout or 2, false)
  if not x then
    return nil, "Kein GPS-Signal"
  end
  return { x = x, y = y, z = z }
end

local function readNumber(label)
  while true do
    write(label)
    local value = tonumber(read())
    if value then
      return value
    end
    print("Bitte eine Zahl eingeben.")
  end
end

local function direction(dx, dz)
  local angle = math.deg(math.atan(dx, -dz))
  if angle < 0 then
    angle = angle + 360
  end

  local names = { "N", "NO", "O", "SO", "S", "SW", "W", "NW" }
  local index = math.floor((angle + 22.5) / 45) % 8 + 1
  return names[index], math.floor(angle + 0.5) % 360
end

local function distance(a, b)
  local dx = b.x - a.x
  local dy = b.y - a.y
  local dz = b.z - a.z
  return math.sqrt(dx * dx + dy * dy + dz * dz), dx, dy, dz
end

local function printTargets(targets)
  if #targets == 0 then
    print("Keine Ziele gespeichert.")
    return
  end

  for index, target in ipairs(targets) do
    print(("%d. %s (%d, %d, %d)"):format(
      index, target.name, target.x, target.y, target.z
    ))
  end
end

local function addTarget(targets)
  clear()
  print("Ziel speichern")
  print("==============")
  write("Name: ")
  local name = read()
  if name == "" then
    print("Abgebrochen.")
    pause()
    return
  end

  print("1 - Aktuelle GPS-Position")
  print("2 - Koordinaten eingeben")
  write("Auswahl: ")
  local choice = read()
  local position

  if choice == "1" then
    write("Suche GPS... ")
    local err
    position, err = locate(3)
    if not position then
      print("FEHLER")
      print(err)
      pause()
      return
    end
    print("OK")
  elseif choice == "2" then
    position = {
      x = readNumber("X: "),
      y = readNumber("Y: "),
      z = readNumber("Z: ")
    }
  else
    print("Abgebrochen.")
    pause()
    return
  end

  targets[#targets + 1] = {
    name = name,
    x = math.floor(position.x),
    y = math.floor(position.y),
    z = math.floor(position.z)
  }
  saveTargets(targets)
  print("Ziel gespeichert.")
  pause()
end

local function navigate(target)
  while true do
    clear()
    print("NAV: " .. target.name)
    print("Q zum Beenden")
    print()

    local current, err = locate(1.5)
    if current then
      local blocks, dx, dy, dz = distance(current, target)
      local cardinal, degrees = direction(dx, dz)
      print(("Position: %.0f %.0f %.0f"):format(current.x, current.y, current.z))
      print(("Ziel:     %d %d %d"):format(target.x, target.y, target.z))
      print()
      print(("Distanz:  %.1f Bloecke"):format(blocks))
      print(("Richtung: %s (%d Grad)"):format(cardinal, degrees))
      print(("Hoehe:    %+.0f"):format(dy))

      if blocks < 5 then
        print()
        print("*** ZIEL ERREICHT ***")
      end
    else
      print(err)
      print("Wireless Modem/GPS pruefen.")
    end

    local timer = os.startTimer(1)
    while true do
      local event, value = os.pullEvent()
      if event == "key" and value == keys.q then
        return
      elseif event == "timer" and value == timer then
        break
      end
    end
  end
end

local function chooseNavigation(targets)
  clear()
  printTargets(targets)
  if #targets == 0 then
    pause()
    return
  end

  write("\nZielnummer: ")
  local target = targets[tonumber(read()) or 0]
  if not target then
    print("Ungueltige Nummer.")
    pause()
    return
  end
  navigate(target)
end

local function deleteTarget(targets)
  clear()
  printTargets(targets)
  if #targets == 0 then
    pause()
    return
  end

  write("\nNummer loeschen: ")
  local index = tonumber(read())
  if not index or not targets[index] then
    print("Ungueltige Nummer.")
    pause()
    return
  end

  local name = targets[index].name
  table.remove(targets, index)
  saveTargets(targets)
  print(name .. " geloescht.")
  pause()
end

local function findWirelessModem()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.hasType(name, "modem") then
      local modem = peripheral.wrap(name)
      if modem.isWireless and modem.isWireless() then
        return name
      end
    end
  end
end

local function sendBeacon()
  clear()
  local position, err = locate(3)
  if not position then
    print(err)
    pause()
    return
  end

  local modemName = findWirelessModem()
  if not modemName then
    print("Kein Wireless Modem gefunden.")
    pause()
    return
  end

  if not rednet.isOpen(modemName) then
    rednet.open(modemName)
  end

  write("Beacon-Name: ")
  local label = read()
  if label == "" then
    label = os.getComputerLabel() or ("Pocket " .. os.getComputerID())
  end

  rednet.broadcast({
    label = label,
    sender = os.getComputerID(),
    x = position.x,
    y = position.y,
    z = position.z
  }, beaconProtocol)

  print(("Gesendet: %.0f %.0f %.0f"):format(position.x, position.y, position.z))
  pause()
end

local targets = loadTargets()

while true do
  clear()
  print("FieldNav")
  print("========")
  print("1 - Live zum Ziel navigieren")
  print("2 - Ziel speichern")
  print("3 - Ziele anzeigen")
  print("4 - Ziel loeschen")
  print("5 - Position funken")
  print("6 - Beenden")
  write("\nAuswahl: ")

  local choice = read()
  if choice == "1" then
    chooseNavigation(targets)
  elseif choice == "2" then
    addTarget(targets)
  elseif choice == "3" then
    clear()
    printTargets(targets)
    pause()
  elseif choice == "4" then
    deleteTarget(targets)
  elseif choice == "5" then
    sendBeacon()
  elseif choice == "6" then
    clear()
    print("FieldNav beendet.")
    return
  end
end
