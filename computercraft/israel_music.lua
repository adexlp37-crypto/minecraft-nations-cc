local args = { ... }
local musicDir = "music"
local version = "1.0"
local bytesPerSecond = 6000
local chunkSize = 4096

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
  playing, paused, bytesRead = false, false, 0
  statusText = message or "STOPPED"
  statusColor = colors.lightBlue
end

local startTrack
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

local function finishTrack()
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

local function togglePause()
  if not playing then startTrack(current) return end
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
  local connection = tostring(#speakers) .. " SPK  " .. tostring(#songs) .. " TRACKS"
  writeAt(math.max(2, width - #connection), 4, connection,
    #speakers > 0 and colors.lightBlue or colors.red, colors.black)

  local song = songs[current]
  fill(2, 6, width - 1, 10, colors.gray)
  writeAt(4, 6, playing and "NOW PLAYING" or "SELECTED", colors.lightBlue, colors.gray)
  centered(8, scrollingTitle(song and song.title or "NO DFPWM TRACKS", math.max(8, width - 6)),
    colors.white, colors.gray)
  local progress = song and song.size > 0 and math.min(1, bytesRead / song.size) or 0
  local barX1, barX2 = 4, width - 3
  fill(barX1, 10, barX2, 10, colors.black)
  if progress > 0 then
    fill(barX1, 10, barX1 + math.floor((barX2 - barX1 + 1) * progress) - 1, 10, colors.lightBlue)
  end
  local elapsed = formatTime(bytesRead / bytesPerSecond)
  local duration = formatTime(song and song.size / bytesPerSecond or 0)
  writeAt(4, 11, elapsed, colors.lightGray, colors.black)
  writeAt(math.max(4, width - #duration - 2), 11, duration, colors.lightGray, colors.black)

  local gap = 1
  local buttonWidth = math.floor((width - 4 - gap * 2) / 3)
  local x1 = 2
  local x2 = x1 + buttonWidth - 1
  addButton("prev", x1, 13, x2, 15, "<<", colors.blue, colors.white)
  x1, x2 = x2 + gap + 1, x2 + gap + buttonWidth
  addButton("toggle", x1, 13, x2, 15, (paused or not playing) and "PLAY" or "PAUSE",
    colors.lightBlue, colors.black)
  x1 = x2 + gap + 1
  addButton("next", x1, 13, width - 1, 15, ">>", colors.blue, colors.white)

  local smallWidth = math.floor((width - 4 - gap * 2) / 3)
  x1, x2 = 2, 2 + smallWidth - 1
  addButton("stop", x1, 17, x2, 18, "STOP", colors.red, colors.white)
  x1, x2 = x2 + gap + 1, x2 + gap + smallWidth
  local repeatLabel = repeatMode == 0 and "LOOP OFF" or repeatMode == 1 and "LOOP ALL" or "LOOP ONE"
  addButton("repeat", x1, 17, x2, 18, repeatLabel, colors.blue, colors.white)
  x1 = x2 + gap + 1
  addButton("shuffle", x1, 17, width - 1, 18, shuffle and "SHUFFLE ON" or "SHUFFLE",
    shuffle and colors.lightBlue or colors.blue, shuffle and colors.black or colors.white)

  addButton("voldown", 2, 20, 7, 21, "VOL -", colors.gray, colors.white)
  centered(20, "VOLUME " .. tostring(math.floor(volume * 100 / 3)) .. "%", colors.white, colors.black)
  addButton("volup", width - 6, 20, width - 1, 21, "VOL +", colors.gray, colors.white)

  local listTop, listBottom = 23, height - 3
  writeAt(2, listTop, "PLAYLIST", colors.lightBlue, colors.black)
  local visibleRows = math.max(0, listBottom - listTop)
  if current < listOffset then listOffset = current end
  if current >= listOffset + visibleRows then listOffset = current - visibleRows + 1 end
  listOffset = math.max(1, math.min(listOffset, math.max(1, #songs - visibleRows + 1)))
  for row = 1, visibleRows do
    local index = listOffset + row - 1
    local item = songs[index]
    if not item then break end
    local y = listTop + row
    local selected = index == current
    local prefix = selected and (playing and not paused and "> " or "* ") or "  "
    fill(2, y, width - 1, y, selected and colors.blue or colors.black)
    writeAt(3, y, prefix .. tostring(index) .. ". " .. item.title,
      selected and colors.white or colors.lightGray, selected and colors.blue or colors.black)
    buttons[#buttons + 1] = { action="song", index=index, x1=2, y1=y, x2=width - 1, y2=y }
  end

  addButton("up", 2, height - 1, 10, height, "UP", colors.blue, colors.white)
  addButton("refresh", math.max(12, math.floor(width / 2) - 5), height - 1,
    math.min(width - 12, math.floor(width / 2) + 5), height, "REFRESH", colors.gray, colors.white)
  addButton("down", width - 9, height - 1, width - 1, height, "DOWN", colors.blue, colors.white)
end

local function runAction(button)
  flashAction, flashUntil = button.action, os.clock() + 0.18
  if button.action == "toggle" then togglePause()
  elseif button.action == "stop" then stopTrack("STOPPED")
  elseif button.action == "prev" then startTrack(chooseNext(-1))
  elseif button.action == "next" then startTrack(chooseNext(1))
  elseif button.action == "repeat" then repeatMode = (repeatMode + 1) % 3
  elseif button.action == "shuffle" then shuffle = not shuffle
  elseif button.action == "voldown" then volume = math.max(0, volume - 0.25)
  elseif button.action == "volup" then volume = math.min(3, volume + 0.25)
  elseif button.action == "up" then listOffset = math.max(1, listOffset - 1)
  elseif button.action == "down" then listOffset = math.min(math.max(1, #songs), listOffset + 1)
  elseif button.action == "refresh" then loadSongs()
  elseif button.action == "song" then startTrack(button.index) end
end

refreshSpeakers()
loadSongs()
if #speakers == 0 then statusText, statusColor = "NO SPEAKER CONNECTED", colors.red
elseif #songs == 0 then statusText, statusColor = "ADD DFPWM TRACKS", colors.orange end

local function mainLoop()
  local redrawTimer = os.startTimer(0.25)
  draw()
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
    elseif event == "speaker_audio_empty" then
      feedAudio()
    elseif event == "timer" and a == redrawTimer then
      draw()
      redrawTimer = os.startTimer(0.25)
    elseif event == "monitor_resize" then
      draw()
    elseif event == "peripheral" or event == "peripheral_detach" then
      refreshSpeakers()
      if #speakers == 0 and playing then stopTrack("SPEAKER DISCONNECTED") end
      draw()
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
if not ok and tostring(failure) ~= "Terminated" then error(failure, 0) end
