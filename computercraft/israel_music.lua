local args = { ... }
local musicDir = "music"
local version = "2.2"
local bytesPerSecond = 6000
local chunkSize = 4096
-- Search/stream protocol used by the public Rc1PCzLH player.
local onlineApi = "https://ipod-2to6magyna-uc.a.run.app/"
local onlineApiVersion = "2.1"

local function cleanName(value)
  local name = tostring(value or "track")
  name = name:gsub("[\\/:*?\"<>|]", "_"):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then name = "track" end
  if not name:lower():match("%.dfpwm$") then name = name .. ".dfpwm" end
  return name
end

local function ensureMusicDir()
  if not fs.exists(musicDir) then fs.makeDir(musicDir) end
end

local function downloadTrack(url, filename)
  ensureMusicDir()
  local ok, response, err = pcall(http.get, {
    url=url, redirect=true, binary=true,
    headers={ ["Accept"]="application/octet-stream" }
  })
  if not ok then error("Download failed: " .. tostring(response), 0) end
  if not response then error("Download failed: " .. tostring(err or "no response"), 0) end
  local path = fs.combine(musicDir, cleanName(filename))
  local temporary = path .. ".download"
  if fs.exists(temporary) then fs.delete(temporary) end
  local file = assert(fs.open(temporary, "wb"))
  local total = 0
  while true do
    local chunk = response.read(16384)
    if not chunk then break end
    file.write(chunk)
    total = total + #chunk
  end
  file.close()
  response.close()
  if total == 0 then
    fs.delete(temporary)
    error("The downloaded audio file is empty.", 0)
  end
  if fs.exists(path) then fs.delete(path) end
  fs.move(temporary, path)
  print("Installed " .. path .. " (" .. tostring(total) .. " bytes)")
end

local command = tostring(args[1] or "run"):lower()
if command == "help" or command == "-h" or command == "--help" then
  print("Israel Music Player v" .. version)
  print("israel_music run")
  print("israel_music add <dfpwm-url> <track name>")
  print("israel_music remove <filename>")
  print("israel_music list")
  print("Run the player and type online searches on the computer keyboard.")
  return
elseif command == "add" then
  if not args[2] then error("Usage: israel_music add <dfpwm-url> <track name>", 0) end
  local name = args[3] or tostring(args[2]):match("/([^/?#]+)") or
    ("track_" .. tostring(os.epoch and os.epoch("utc") or os.clock()))
  downloadTrack(args[2], name)
  return
elseif command == "remove" then
  if not args[2] then error("Usage: israel_music remove <filename>", 0) end
  local path = fs.combine(musicDir, cleanName(args[2]))
  if not fs.exists(path) or fs.isDir(path) then error("Track not found: " .. path, 0) end
  fs.delete(path)
  print("Removed " .. path)
  return
elseif command == "list" then
  ensureMusicDir()
  local files = fs.list(musicDir)
  table.sort(files, function(a, b) return a:lower() < b:lower() end)
  for _, name in ipairs(files) do
    if name:lower():match("%.dfpwm$") then print(name) end
  end
  return
elseif command ~= "run" then
  error("Unknown command. Run: israel_music help", 0)
end

ensureMusicDir()
local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found. Connect an Advanced Monitor.", 0) end
monitor.setTextScale(0.5)
pcall(monitor.setPaletteColor, colors.blue, 0.02, 0.20, 0.58)
pcall(monitor.setPaletteColor, colors.lightBlue, 0.20, 0.55, 1.00)

local dfpwm = require("cc.audio.dfpwm")
local speakers = {}
local songs = {}
local buttons = {}
local current = 1
local listOffset = 1
local volume = 1.25
local repeatMode = 0 -- 0=off, 1=all, 2=one
local shuffle = false
local playing = false
local paused = false
local audioFile = nil
local decoder = nil
local pendingPcm = nil
local pendingAccepted = {}
local bytesRead = 0
local statusText = "READY"
local statusColor = colors.lightBlue
local flashAction = nil
local flashUntil = 0
local remoteTrack = nil
local remoteQueue = {}
local remoteLoadingUrl = nil
local searchUrl = nil
local searchQuery = ""
local searchResults = {}
local searchSelected = 1
local searchOffset = 1
local terminalMode = "input"
local terminalStatus = "TYPE A SONG, ARTIST OR YOUTUBE URL"
local queueOffset = 1

local function isSpeaker(name)
  if peripheral.hasType then return peripheral.hasType(name, "speaker") end
  return peripheral.getType(name) == "speaker"
end

local function refreshSpeakers()
  speakers = {}
  for _, name in ipairs(peripheral.getNames()) do
    if isSpeaker(name) then
      speakers[#speakers + 1] = { name=name, device=peripheral.wrap(name) }
    end
  end
  table.sort(speakers, function(a, b) return a.name < b.name end)
end

local function displayTitle(filename)
  return tostring(filename):gsub("%.dfpwm$", ""):gsub("[_%-]+", " ")
end

local function loadSongs()
  local selectedPath = songs[current] and songs[current].path or nil
  songs = {}
  for _, filename in ipairs(fs.list(musicDir)) do
    if filename:lower():match("%.dfpwm$") then
      local path = fs.combine(musicDir, filename)
      if not fs.isDir(path) then
        songs[#songs + 1] = {
          filename=filename,
          title=displayTitle(filename),
          path=path,
          size=fs.getSize(path)
        }
      end
    end
  end
  table.sort(songs, function(a, b) return a.title:lower() < b.title:lower() end)
  current = math.max(1, math.min(current, math.max(1, #songs)))
  if selectedPath then
    for index, song in ipairs(songs) do
      if song.path == selectedPath then current = index break end
    end
  end
end

local function stopSpeakers()
  for _, speaker in ipairs(speakers) do pcall(speaker.device.stop) end
end

local function closeAudio()
  if audioFile then pcall(audioFile.close) end
  audioFile = nil
  decoder = nil
  pendingPcm = nil
  pendingAccepted = {}
end

local function stopTrack(message)
  stopSpeakers()
  closeAudio()
  remoteLoadingUrl = nil
  playing, paused, bytesRead = false, false, 0
  statusText = message or "STOPPED"
  statusColor = colors.lightBlue
end

local startTrack, startRemote
local function chooseNext(direction)
  if #songs == 0 then return nil end
  if shuffle and #songs > 1 then
    local nextIndex = current
    while nextIndex == current do nextIndex = math.random(1, #songs) end
    return nextIndex
  end
  local nextIndex = current + (direction or 1)
  if nextIndex > #songs then nextIndex = 1 end
  if nextIndex < 1 then nextIndex = #songs end
  return nextIndex
end

local function popRemoteQueue()
  if #remoteQueue == 0 then return nil end
  local index = shuffle and math.random(1, #remoteQueue) or 1
  return table.remove(remoteQueue, index)
end

local function finishTrack()
  if remoteTrack then
    local finished = remoteTrack
    closeAudio()
    playing, paused = false, false
    if repeatMode == 2 then
      startRemote(finished)
      return
    end
    if repeatMode == 1 then remoteQueue[#remoteQueue + 1] = finished end
    local nextTrack = popRemoteQueue()
    if nextTrack then
      startRemote(nextTrack)
    else
      statusText, statusColor = "QUEUE COMPLETE", colors.lime
    end
    return
  end
  closeAudio()
  playing, paused = false, false
  if #songs == 0 then return end
  if repeatMode == 2 then
    startTrack(current)
  elseif current < #songs or repeatMode == 1 or shuffle then
    startTrack(chooseNext(1))
  else
    statusText = "PLAYLIST COMPLETE"
    statusColor = colors.lime
  end
end

local function feedAudio()
  if not playing or paused or #speakers == 0 or not audioFile then return end
  if not pendingPcm then
    local chunk = audioFile.read(chunkSize)
    if not chunk then finishTrack() return end
    bytesRead = bytesRead + #chunk
    pendingPcm = decoder(chunk)
    pendingAccepted = {}
  end

  local allAccepted = true
  for _, speaker in ipairs(speakers) do
    if not pendingAccepted[speaker.name] then
      local ok, accepted = pcall(speaker.device.playAudio, pendingPcm, volume)
      if ok and accepted then pendingAccepted[speaker.name] = true end
    end
    if not pendingAccepted[speaker.name] then allAccepted = false end
  end
  if allAccepted then
    pendingPcm = nil
    pendingAccepted = {}
  end
end

startTrack = function(index)
  if #songs == 0 then
    statusText, statusColor = "ADD DFPWM TRACKS", colors.orange
    return
  end
  if #speakers == 0 then
    statusText, statusColor = "NO SPEAKER", colors.red
    return
  end
  stopSpeakers()
  closeAudio()
  remoteLoadingUrl = nil
  remoteTrack = nil
  current = math.max(1, math.min(tonumber(index) or current, #songs))
  audioFile = fs.open(songs[current].path, "rb")
  if not audioFile then
    statusText, statusColor = "CANNOT OPEN TRACK", colors.red
    return
  end
  decoder = dfpwm.make_decoder()
  bytesRead = 0
  playing, paused = true, false
  statusText, statusColor = "NOW PLAYING", colors.lime
  feedAudio()
end

startRemote = function(track)
  if type(track) ~= "table" or not track.id then
    statusText, statusColor = "INVALID ONLINE TRACK", colors.red
    return
  end
  if #speakers == 0 then
    statusText, statusColor = "NO SPEAKER", colors.red
    return
  end
  stopSpeakers()
  closeAudio()
  remoteTrack = track
  playing, paused, bytesRead = false, false, 0
  statusText, statusColor = "LOADING ONLINE TRACK", colors.yellow
  remoteLoadingUrl = onlineApi .. "?v=" .. onlineApiVersion .. "&id=" ..
    textutils.urlEncode(tostring(track.id))
  local ok, err = http.request({ url=remoteLoadingUrl, binary=true, redirect=true, timeout=30 })
  if not ok then
    remoteLoadingUrl = nil
    statusText, statusColor = "STREAM REQUEST FAILED", colors.red
    terminalStatus = tostring(err or "REQUEST FAILED")
  end
end

local function addRemoteTrack(track, playNow)
  if type(track) ~= "table" then return end
  if track.type == "playlist" and type(track.playlist_items) == "table" then
    for index, item in ipairs(track.playlist_items) do
      addRemoteTrack(item, playNow and index == 1)
    end
    return
  end
  if not track.id then return end
  if playNow then
    startRemote(track)
  elseif not playing and not remoteLoadingUrl then
    startRemote(track)
  else
    remoteQueue[#remoteQueue + 1] = track
    statusText, statusColor = "ADDED TO QUEUE", colors.lightBlue
  end
end

local function startSearch()
  local query = searchQuery:gsub("^%s+", ""):gsub("%s+$", "")
  if query == "" then return end
  searchUrl = onlineApi .. "?v=" .. onlineApiVersion .. "&search=" .. textutils.urlEncode(query)
  searchResults, searchSelected, searchOffset = {}, 1, 1
  terminalMode = "loading"
  terminalStatus = "SEARCHING..."
  local ok, err = http.request({ url=searchUrl, redirect=true, timeout=20 })
  if not ok then
    searchUrl = nil
    terminalMode = "input"
    terminalStatus = tostring(err or "SEARCH REQUEST FAILED")
  end
end

local function togglePause()
  if not playing then
    if remoteTrack then startRemote(remoteTrack) else startTrack(current) end
    return
  end
  if paused then
    paused = false
    statusText, statusColor = "NOW PLAYING", colors.lime
    feedAudio()
  else
    paused = true
    stopSpeakers()
    pendingPcm = nil
    pendingAccepted = {}
    statusText, statusColor = "PAUSED", colors.yellow
  end
end

local function formatTime(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function fill(x1, y1, x2, y2, background)
  local width, height = monitor.getSize()
  x1, y1 = math.max(1, x1), math.max(1, y1)
  x2, y2 = math.min(width, x2), math.min(height, y2)
  monitor.setBackgroundColor(background)
  for y = y1, y2 do
    monitor.setCursorPos(x1, y)
    monitor.write(string.rep(" ", math.max(0, x2 - x1 + 1)))
  end
end

local function writeAt(x, y, text, foreground, background)
  local width, height = monitor.getSize()
  if x > width or y < 1 or y > height then return end
  monitor.setCursorPos(math.max(1, x), y)
  monitor.setTextColor(foreground or colors.white)
  monitor.setBackgroundColor(background or colors.black)
  monitor.write(tostring(text):sub(1, math.max(0, width - x + 1)))
end

local function centered(y, text, foreground, background)
  local width = monitor.getSize()
  writeAt(math.max(1, math.floor((width - #tostring(text)) / 2) + 1), y,
    text, foreground, background)
end

local function addButton(action, x1, y1, x2, y2, label, background, foreground)
  local active = flashAction == action and os.clock() < flashUntil
  local bg = active and colors.white or background
  local fg = active and colors.blue or foreground
  fill(x1, y1, x2, y2, bg)
  local labelY = math.floor((y1 + y2) / 2)
  local labelX = x1 + math.max(0, math.floor((x2 - x1 + 1 - #label) / 2))
  writeAt(labelX, labelY, label, fg, bg)
  buttons[#buttons + 1] = { action=action, x1=x1, y1=y1, x2=x2, y2=y2 }
end

local function scrollingTitle(title, width)
  title = tostring(title or "NO TRACK SELECTED")
  if #title <= width then return title end
  local padded = title .. "     " .. title
  local offset = math.floor(os.clock() * 2) % (#title + 5)
  return padded:sub(offset + 1, offset + width)
end

local function activeSong()
  if remoteTrack then
    return {
      title=tostring(remoteTrack.name or "ONLINE TRACK"),
      artist=tostring(remoteTrack.artist or "ONLINE"),
      size=0,
      online=true
    }
  end
  return songs[current]
end

local function drawLine(x1, y1, x2, y2, color, character)
  local dx, sx = math.abs(x2 - x1), x1 < x2 and 1 or -1
  local dy, sy = -math.abs(y2 - y1), y1 < y2 and 1 or -1
  local err = dx + dy
  while true do
    writeAt(x1, y1, character or "*", color, colors.black)
    if x1 == x2 and y1 == y2 then break end
    local doubled = 2 * err
    if doubled >= dy then err, x1 = err + dy, x1 + sx end
    if doubled <= dx then err, y1 = err + dx, y1 + sy end
  end
end

local function drawAnimatedStar(centerX, centerY, radiusX, radiusY)
  local phase = math.floor(os.clock() * 4) % 3
  local shades = { colors.blue, colors.lightBlue, colors.white }
  local function shade(offset) return shades[(phase + offset) % #shades + 1] end
  local topY, bottomY = centerY - radiusY, centerY + radiusY
  local upperBaseY = centerY + math.floor(radiusY / 2)
  local lowerBaseY = centerY - math.floor(radiusY / 2)
  drawLine(centerX, topY, centerX - radiusX, upperBaseY, shade(0), "*")
  drawLine(centerX - radiusX, upperBaseY, centerX + radiusX, upperBaseY, shade(1), "*")
  drawLine(centerX + radiusX, upperBaseY, centerX, topY, shade(2), "*")
  drawLine(centerX, bottomY, centerX - radiusX, lowerBaseY, shade(2), "*")
  drawLine(centerX - radiusX, lowerBaseY, centerX + radiusX, lowerBaseY, shade(0), "*")
  drawLine(centerX + radiusX, lowerBaseY, centerX, bottomY, shade(1), "*")
  writeAt(centerX, centerY, "+", colors.white, colors.black)
end

local function draw()
  local width, height = monitor.getSize()
  buttons = {}
  monitor.setBackgroundColor(colors.black)
  monitor.clear()

  fill(1, 1, width, 1, colors.blue)
  fill(1, 2, width, 2, colors.white)
  fill(1, 3, width, 3, colors.blue)
  centered(2, "< ISRAEL MUSIC >", colors.blue, colors.white)
  writeAt(2, 4, statusText, statusColor, colors.black)
  local connection = tostring(#speakers) .. " SPK  " .. tostring(#remoteQueue) .. " QUEUED"
  writeAt(math.max(2, width - #connection), 4, connection,
    #speakers > 0 and colors.lightBlue or colors.red, colors.black)

  -- Give the animated star most of the upper screen.
  local starRadiusX = math.max(8, math.min(math.floor(width * 0.45), math.floor(width / 2) - 2))
  drawAnimatedStar(math.floor(width / 2), 11, starRadiusX, 6)

  local navigationTop = height - 14
  local queueTop, queueBottom = 19, navigationTop - 2
  writeAt(2, queueTop, "UP NEXT / QUEUE  " .. tostring(#remoteQueue), colors.lightBlue, colors.black)
  addButton("up", width - 18, queueTop - 1, width - 13, queueTop, "UP", colors.blue, colors.white)
  addButton("clearqueue", width - 11, queueTop - 1, width - 7, queueTop, "CLR", colors.gray, colors.white)
  addButton("down", width - 5, queueTop - 1, width - 1, queueTop, "DN", colors.blue, colors.white)
  local visibleRows = math.max(0, queueBottom - queueTop)
  queueOffset = math.max(1, math.min(queueOffset, math.max(1, #remoteQueue - visibleRows + 1)))
  for row = 1, visibleRows do
    local index = queueOffset + row - 1
    local item = remoteQueue[index]
    if not item then break end
    local label = tostring(index) .. ". " .. tostring(item.name or "UNKNOWN")
    writeAt(3, queueTop + row, label, row == 1 and colors.white or colors.lightGray, colors.black)
  end
  if #remoteQueue == 0 and visibleRows > 0 then
    writeAt(3, queueTop + 1, "QUEUE IS EMPTY", colors.gray, colors.black)
  end

  local gap = 1
  local buttonWidth = math.floor((width - 4 - gap * 2) / 3)
  local x1 = 2
  local x2 = x1 + buttonWidth - 1
  addButton("prev", x1, navigationTop, x2, navigationTop + 2, "<<", colors.blue, colors.white)
  x1, x2 = x2 + gap + 1, x2 + gap + buttonWidth
  addButton("toggle", x1, navigationTop, x2, navigationTop + 2, (paused or not playing) and "PLAY" or "PAUSE",
    colors.lightBlue, colors.black)
  x1 = x2 + gap + 1
  addButton("next", x1, navigationTop, width - 1, navigationTop + 2, ">>", colors.blue, colors.white)

  local smallWidth = math.floor((width - 4 - gap * 2) / 3)
  x1, x2 = 2, 2 + smallWidth - 1
  addButton("stop", x1, height - 10, x2, height - 9, "STOP", colors.red, colors.white)
  x1, x2 = x2 + gap + 1, x2 + gap + smallWidth
  local repeatLabel = repeatMode == 0 and "LOOP OFF" or repeatMode == 1 and "LOOP ALL" or "LOOP ONE"
  addButton("repeat", x1, height - 10, x2, height - 9, repeatLabel, colors.blue, colors.white)
  x1 = x2 + gap + 1
  addButton("shuffle", x1, height - 10, width - 1, height - 9, shuffle and "SHUFFLE ON" or "SHUFFLE",
    shuffle and colors.lightBlue or colors.blue, shuffle and colors.black or colors.white)

  addButton("voldown", 2, height - 7, 7, height - 6, "VOL -", colors.gray, colors.white)
  centered(height - 7, "VOLUME " .. tostring(math.floor(volume * 100 / 3)) .. "%", colors.white, colors.black)
  addButton("volup", width - 6, height - 7, width - 1, height - 6, "VOL +", colors.gray, colors.white)

  -- The current track lives in a permanent animated footer.
  local song = activeSong()
  local nowTop = height - 4
  local animationPhase = math.floor(os.clock() * 4) % 4
  local playingColors = { colors.lightBlue, colors.white, colors.lime, colors.white }
  local playingLabel = playing and ("PLAYING RN" .. string.rep(".", animationPhase)) or "SELECTED"
  fill(1, nowTop, width, height, colors.gray)
  writeAt(3, nowTop, playingLabel, playingColors[animationPhase + 1], colors.gray)
  centered(nowTop + 1,
    scrollingTitle(song and song.title or "SEARCH ON THE COMPUTER", math.max(8, width - 6)),
    colors.white, colors.gray)
  if song and song.artist then
    centered(nowTop + 2, tostring(song.artist):sub(1, width - 6), colors.lightGray, colors.gray)
  end
  local progress = song and song.size > 0 and math.min(1, bytesRead / song.size) or 0
  local barX1, barX2 = 3, width - 2
  fill(barX1, nowTop + 3, barX2, nowTop + 3, colors.black)
  if song and song.online and playing then
    local barWidth = math.max(1, barX2 - barX1 + 1)
    local pulseWidth = math.max(3, math.floor(barWidth / 5))
    local pulseStart = barX1 + (math.floor(os.clock() * 8) % math.max(1, barWidth - pulseWidth + 1))
    fill(pulseStart, nowTop + 3, pulseStart + pulseWidth - 1, nowTop + 3, colors.lightBlue)
  elseif progress > 0 then
    fill(barX1, nowTop + 3,
      barX1 + math.floor((barX2 - barX1 + 1) * progress) - 1, nowTop + 3, colors.lightBlue)
  end
  local elapsed = formatTime(bytesRead / bytesPerSecond)
  local duration = song and song.online and "LIVE" or formatTime(song and song.size / bytesPerSecond or 0)
  writeAt(3, height, elapsed, colors.lightGray, colors.gray)
  writeAt(math.max(3, width - #duration - 1), height, duration, colors.lightGray, colors.gray)
end

local function runAction(button)
  flashAction, flashUntil = button.action, os.clock() + 0.18
  if button.action == "toggle" then togglePause()
  elseif button.action == "stop" then stopTrack("STOPPED")
  elseif button.action == "prev" then
    if remoteTrack then startRemote(remoteTrack) else startTrack(chooseNext(-1)) end
  elseif button.action == "next" then
    if remoteTrack then
      local nextTrack = popRemoteQueue()
      if nextTrack then startRemote(nextTrack) else stopTrack("QUEUE IS EMPTY") end
    else startTrack(chooseNext(1)) end
  elseif button.action == "repeat" then repeatMode = (repeatMode + 1) % 3
  elseif button.action == "shuffle" then shuffle = not shuffle
  elseif button.action == "voldown" then volume = math.max(0, volume - 0.25)
  elseif button.action == "volup" then volume = math.min(3, volume + 0.25)
  elseif button.action == "up" then queueOffset = math.max(1, queueOffset - 1)
  elseif button.action == "down" then queueOffset = math.min(math.max(1, #remoteQueue), queueOffset + 1)
  elseif button.action == "clearqueue" then remoteQueue, queueOffset = {}, 1 end
end

local function termWrite(x, y, text, foreground, background)
  local width, height = term.getSize()
  if y < 1 or y > height or x > width then return end
  term.setCursorPos(math.max(1, x), y)
  term.setTextColor(foreground or colors.white)
  term.setBackgroundColor(background or colors.black)
  term.write(tostring(text):sub(1, math.max(0, width - x + 1)))
end

local function termFill(y, background)
  local width = term.getSize()
  term.setCursorPos(1, y)
  term.setBackgroundColor(background)
  term.write(string.rep(" ", width))
end

local function drawTerminal()
  local width, height = term.getSize()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  termFill(1, colors.blue)
  termFill(2, colors.white)
  termFill(3, colors.blue)
  local heading = "ISRAEL MUSIC ONLINE SEARCH"
  termWrite(math.max(1, math.floor((width - #heading) / 2) + 1), 2,
    heading, colors.blue, colors.white)
  termWrite(2, 5, terminalStatus, terminalMode == "loading" and colors.yellow or colors.lightBlue, colors.black)

  if terminalMode == "input" or terminalMode == "loading" then
    termWrite(2, 7, "SEARCH / YOUTUBE URL", colors.lightGray, colors.black)
    termFill(8, colors.gray)
    termWrite(2, 8, "> " .. searchQuery, colors.white, colors.gray)
    termWrite(2, height - 1, "ENTER SEARCH   CTRL+T EXIT", colors.gray, colors.black)
    if terminalMode == "input" then
      term.setCursorPos(math.min(width, 4 + #searchQuery), 8)
      term.setCursorBlink(true)
    else
      term.setCursorBlink(false)
    end
    return
  end

  term.setCursorBlink(false)
  termWrite(2, 7, "RESULTS FOR: " .. searchQuery, colors.lightGray, colors.black)
  local resultRows = math.max(1, height - 10)
  if searchSelected < searchOffset then searchOffset = searchSelected end
  if searchSelected >= searchOffset + resultRows then searchOffset = searchSelected - resultRows + 1 end
  searchOffset = math.max(1, math.min(searchOffset, math.max(1, #searchResults - resultRows + 1)))
  for row = 1, resultRows do
    local index = searchOffset + row - 1
    local result = searchResults[index]
    if not result then break end
    local y = 7 + row
    local selected = index == searchSelected
    if selected then termFill(y, colors.blue) end
    local label = tostring(index) .. ". " .. tostring(result.name or "UNKNOWN") ..
      " - " .. tostring(result.artist or "UNKNOWN")
    termWrite(2, y, label, selected and colors.white or colors.lightGray,
      selected and colors.blue or colors.black)
  end
  if #searchResults == 0 then termWrite(2, 9, "NO RESULTS", colors.orange, colors.black) end
  termWrite(2, height - 1, "UP/DOWN  ENTER QUEUE  P PLAY NOW", colors.lightBlue, colors.black)
  termWrite(2, height, "BACKSPACE NEW SEARCH", colors.gray, colors.black)
end

local function selectedSearchResult()
  return searchResults[searchSelected]
end

local function handleSearchSuccess(handle)
  local body = handle.readAll()
  handle.close()
  local payload = textutils.unserializeJSON(body or "")
  if type(payload) ~= "table" then
    searchResults = {}
    terminalStatus = "INVALID SEARCH RESPONSE"
  else
    searchResults = {}
    for _, result in ipairs(payload) do
      local name = tostring(type(result) == "table" and result.name or "")
      if type(result) == "table" and (result.id or result.type == "playlist") and
          not name:lower():find("patreon", 1, true) then
        searchResults[#searchResults + 1] = result
      end
    end
    terminalStatus = tostring(#searchResults) .. " RESULTS - ENTER ADDS TO QUEUE"
  end
  searchSelected, searchOffset = 1, 1
  terminalMode = "results"
  searchUrl = nil
end

local function handleStreamSuccess(handle)
  audioFile = handle
  decoder = dfpwm.make_decoder()
  pendingPcm, pendingAccepted = nil, {}
  bytesRead = 0
  playing, paused = true, false
  remoteLoadingUrl = nil
  statusText, statusColor = "STREAMING ONLINE", colors.lime
  terminalStatus = "PLAYING: " .. tostring(remoteTrack and remoteTrack.name or "ONLINE TRACK")
  feedAudio()
end

local function handleHttpFailure(url, message, response)
  if response then pcall(response.close) end
  if url == searchUrl then
    searchUrl = nil
    terminalMode = "input"
    terminalStatus = "SEARCH FAILED: " .. tostring(message or "NETWORK ERROR")
  elseif url == remoteLoadingUrl then
    remoteLoadingUrl = nil
    playing, paused = false, false
    statusText, statusColor = "ONLINE STREAM FAILED", colors.red
    terminalStatus = "STREAM FAILED: " .. tostring(message or "NETWORK ERROR")
  end
end

local function handleKeyboard(event, value)
  if terminalMode == "input" then
    if event == "char" then
      searchQuery = searchQuery .. tostring(value)
    elseif event == "paste" then
      searchQuery = searchQuery .. tostring(value)
    elseif event == "key" and value == keys.backspace then
      searchQuery = searchQuery:sub(1, math.max(0, #searchQuery - 1))
    elseif event == "key" and value == keys.enter then
      startSearch()
    elseif event == "key" and value == keys.delete then
      searchQuery = ""
    end
  elseif terminalMode == "results" and event == "key" then
    if value == keys.up then
      searchSelected = math.max(1, searchSelected - 1)
    elseif value == keys.down then
      searchSelected = math.min(math.max(1, #searchResults), searchSelected + 1)
    elseif value == keys.enter then
      local result = selectedSearchResult()
      if result then
        addRemoteTrack(result, false)
        terminalStatus = "ADDED TO QUEUE: " .. tostring(result.name or "TRACK")
      end
    elseif value == keys.backspace or value == keys.escape then
      terminalMode = "input"
      terminalStatus = "TYPE A NEW SEARCH"
    end
  elseif terminalMode == "results" and event == "char" and tostring(value):lower() == "p" then
    local result = selectedSearchResult()
    if result then
      addRemoteTrack(result, true)
      terminalStatus = "PLAY NOW: " .. tostring(result.name or "TRACK")
    end
  elseif terminalMode == "loading" and event == "key" and value == keys.backspace then
    terminalMode = "input"
    terminalStatus = "SEARCH STILL RUNNING - TYPE A NEW QUERY"
  end
end

refreshSpeakers()
loadSongs()
if #speakers == 0 then statusText, statusColor = "NO SPEAKER CONNECTED", colors.red
elseif #songs == 0 then statusText, statusColor = "SEARCH MUSIC ON COMPUTER", colors.lightBlue end

local function mainLoop()
  local redrawTimer = os.startTimer(0.25)
  draw()
  drawTerminal()
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "monitor_touch" then
      local side, x, y = a, b, c
      if side == peripheral.getName(monitor) then
        for index = #buttons, 1, -1 do
          local button = buttons[index]
          if x >= button.x1 and x <= button.x2 and y >= button.y1 and y <= button.y2 then
            runAction(button)
            break
          end
        end
        draw()
      end
    elseif event == "char" or event == "paste" or event == "key" then
      handleKeyboard(event, a)
      drawTerminal()
      draw()
    elseif event == "http_success" then
      if a == searchUrl then
        handleSearchSuccess(b)
      elseif a == remoteLoadingUrl then
        handleStreamSuccess(b)
      elseif b then
        pcall(b.close)
      end
      drawTerminal()
      draw()
    elseif event == "http_failure" then
      handleHttpFailure(a, b, c)
      drawTerminal()
      draw()
    elseif event == "speaker_audio_empty" then
      feedAudio()
    elseif event == "timer" and a == redrawTimer then
      draw()
      drawTerminal()
      redrawTimer = os.startTimer(0.25)
    elseif event == "monitor_resize" then
      draw()
    elseif event == "peripheral" or event == "peripheral_detach" then
      refreshSpeakers()
      if #speakers == 0 and playing then stopTrack("SPEAKER DISCONNECTED") end
      draw()
      drawTerminal()
    end
  end
end

local ok, failure = pcall(mainLoop)
stopSpeakers()
closeAudio()
monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()
monitor.setCursorPos(1, 1)
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok and tostring(failure) ~= "Terminated" then error(failure, 0) end
