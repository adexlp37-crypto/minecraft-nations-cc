local version = "1.0"

local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
if not monitor then error("Connect a 6x6 Advanced Monitor.", 0) end
if not speaker then error("Connect a Speaker to the computer.", 0) end

monitor.setTextScale(0.5)
local monitorName = peripheral.getName(monitor)
local width, height = monitor.getSize()
if width < 80 or height < 45 then
  error("This piano is designed for a 6x6 Advanced Monitor.", 0)
end

pcall(monitor.setPaletteColor, colors.blue, 0.03, 0.12, 0.32)
pcall(monitor.setPaletteColor, colors.lightBlue, 0.20, 0.65, 1.00)
pcall(monitor.setPaletteColor, colors.gray, 0.18, 0.20, 0.24)

local instruments = {
  { label="PIANO", sound="harp" },
  { label="PLING", sound="pling" },
  { label="BELL", sound="bell" },
  { label="CHIME", sound="chime" },
  { label="GUITAR", sound="guitar" },
  { label="FLUTE", sound="flute" },
  { label="XYLOPHONE", sound="xylophone" }
}
local instrumentIndex = 1
local volume = 2.0
local activePitch = nil
local activeUntil = 0
local status = "TOUCH A KEY TO PLAY"
local controls, whiteKeys, blackKeys = {}, {}, {}
local chars, foregrounds, backgrounds
local blitCache = {}

local whiteNotes = {
  {"C3",0}, {"D3",2}, {"E3",4}, {"F3",5}, {"G3",7}, {"A3",9}, {"B3",11},
  {"C4",12}, {"D4",14}, {"E4",16}, {"F4",17}, {"G4",19}, {"A4",21}, {"B4",23},
  {"C5",24}
}
local blackNotes = {
  {1,"C#3",1}, {2,"D#3",3}, {4,"F#3",6}, {5,"G#3",8}, {6,"A#3",10},
  {8,"C#4",13}, {9,"D#4",15}, {11,"F#4",18}, {12,"G#4",20}, {13,"A#4",22}
}

local function now()
  return os.epoch and os.epoch("utc") / 1000 or os.clock()
end

local function toBlit(color)
  if not blitCache[color] then blitCache[color] = colors.toBlit(color) end
  return blitCache[color]
end

local function newCanvas()
  chars, foregrounds, backgrounds = {}, {}, {}
  local black, white = toBlit(colors.black), toBlit(colors.white)
  for y = 1, height do
    chars[y], foregrounds[y], backgrounds[y] = {}, {}, {}
    for x = 1, width do
      chars[y][x] = " "
      foregrounds[y][x] = white
      backgrounds[y][x] = black
    end
  end
end

local function cell(x, y, character, foreground, background)
  if x < 1 or x > width or y < 1 or y > height then return end
  chars[y][x] = character or " "
  foregrounds[y][x] = toBlit(foreground or colors.white)
  backgrounds[y][x] = toBlit(background or colors.black)
end

local function rectangle(x1, y1, x2, y2, background, character, foreground)
  x1, y1 = math.max(1, x1), math.max(1, y1)
  x2, y2 = math.min(width, x2), math.min(height, y2)
  for y = y1, y2 do
    for x = x1, x2 do cell(x, y, character or " ", foreground or colors.white, background) end
  end
end

local function textAt(x, y, value, foreground, background)
  value = tostring(value)
  for index = 1, #value do
    cell(x + index - 1, y, value:sub(index, index), foreground, background)
  end
end

local function centered(x1, x2, y, value, foreground, background)
  value = tostring(value)
  textAt(x1 + math.max(0, math.floor((x2 - x1 + 1 - #value) / 2)), y,
    value, foreground, background)
end

local function border(x1, y1, x2, y2, color, background)
  for x = x1, x2 do
    cell(x, y1, "-", color, background)
    cell(x, y2, "-", color, background)
  end
  for y = y1, y2 do
    cell(x1, y, "|", color, background)
    cell(x2, y, "|", color, background)
  end
  cell(x1, y1, "+", color, background)
  cell(x2, y1, "+", color, background)
  cell(x1, y2, "+", color, background)
  cell(x2, y2, "+", color, background)
end

local function addControl(action, x1, y1, x2, y2, label, color)
  rectangle(x1, y1, x2, y2, color)
  border(x1, y1, x2, y2, colors.white, color)
  centered(x1, x2, math.floor((y1 + y2) / 2), label, colors.white, color)
  controls[#controls + 1] = { action=action, x1=x1, y1=y1, x2=x2, y2=y2 }
end

local function buildKeys(keyTop, keyBottom)
  whiteKeys, blackKeys = {}, {}
  local keyboardLeft, keyboardRight = 2, width - 1
  local keyboardWidth = keyboardRight - keyboardLeft + 1
  for index, note in ipairs(whiteNotes) do
    local x1 = keyboardLeft + math.floor((index - 1) * keyboardWidth / #whiteNotes)
    local x2 = keyboardLeft + math.floor(index * keyboardWidth / #whiteNotes) - 1
    whiteKeys[index] = { name=note[1], pitch=note[2], x1=x1, y1=keyTop, x2=x2, y2=keyBottom }
  end

  local averageWidth = keyboardWidth / #whiteNotes
  local blackWidth = math.max(4, math.floor(averageWidth * 0.62))
  local blackBottom = keyTop + math.floor((keyBottom - keyTop + 1) * 0.58)
  for _, note in ipairs(blackNotes) do
    local boundary = whiteKeys[note[1]].x2
    blackKeys[#blackKeys + 1] = {
      name=note[2], pitch=note[3],
      x1=boundary - math.floor(blackWidth / 2) + 1,
      y1=keyTop, x2=boundary + math.ceil(blackWidth / 2), y2=blackBottom
    }
  end
end

local function draw()
  width, height = monitor.getSize()
  controls = {}
  newCanvas()

  rectangle(1, 1, width, 3, colors.blue)
  centered(1, width, 2, "GRAND TOUCH PIANO  v" .. version, colors.white, colors.blue)

  local section = math.floor((width - 8) / 4)
  local y1, y2 = 5, 10
  addControl("instrument_prev", 2, y1, 2 + section - 1, y2, "<  INSTRUMENT", colors.gray)
  addControl("instrument_next", 3 + section, y1, 2 + section * 2, y2,
    instruments[instrumentIndex].label .. "  >", colors.purple)
  addControl("volume_down", 4 + section * 2, y1, 3 + section * 3, y2, "-  VOLUME", colors.gray)
  addControl("volume_up", 5 + section * 3, y1, width - 1, y2,
    string.format("%.1f  +", volume), colors.blue)

  centered(1, width, 12, status, colors.lightBlue, colors.black)
  local keyTop, keyBottom = 14, height - 2
  buildKeys(keyTop, keyBottom)

  for _, key in ipairs(whiteKeys) do
    local active = key.pitch == activePitch
    local background = active and colors.lightBlue or colors.white
    rectangle(key.x1, key.y1, key.x2, key.y2, background)
    for y = key.y1, key.y2 do cell(key.x2, y, "|", colors.gray, background) end
    centered(key.x1, key.x2, key.y2 - 2, key.name,
      active and colors.white or colors.black, background)
  end
  for _, key in ipairs(blackKeys) do
    local active = key.pitch == activePitch
    local background = active and colors.orange or colors.black
    rectangle(key.x1, key.y1, key.x2, key.y2, background)
    border(key.x1, key.y1, key.x2, key.y2, colors.gray, background)
    centered(key.x1, key.x2, key.y2 - 1, key.name,
      active and colors.black or colors.white, background)
  end

  for y = 1, height do
    monitor.setCursorPos(1, y)
    monitor.blit(table.concat(chars[y]), table.concat(foregrounds[y]), table.concat(backgrounds[y]))
  end
end

local function contains(item, x, y)
  return x >= item.x1 and x <= item.x2 and y >= item.y1 and y <= item.y2
end

local function playKey(key)
  activePitch = key.pitch
  activeUntil = now() + 0.18
  status = key.name .. "  |  " .. instruments[instrumentIndex].label
  local ok, played = pcall(speaker.playNote,
    instruments[instrumentIndex].sound, volume, key.pitch)
  if not ok or played == false then status = "SPEAKER BUSY - TRY AGAIN" end
  draw()
end

local function handleControl(action)
  if action == "instrument_prev" then
    instrumentIndex = (instrumentIndex - 2) % #instruments + 1
  elseif action == "instrument_next" then
    instrumentIndex = instrumentIndex % #instruments + 1
  elseif action == "volume_down" then
    volume = math.max(0.5, volume - 0.5)
  elseif action == "volume_up" then
    volume = math.min(3.0, volume + 0.5)
  end
  status = instruments[instrumentIndex].label .. "  |  VOLUME " .. string.format("%.1f", volume)
  draw()
end

draw()
local releaseTimer = nil
while true do
  local event, a, x, y = os.pullEvent()
  if event == "monitor_touch" and a == monitorName then
    local selected = nil
    for _, key in ipairs(blackKeys) do
      if contains(key, x, y) then selected = key break end
    end
    if not selected then
      for _, key in ipairs(whiteKeys) do
        if contains(key, x, y) then selected = key break end
      end
    end
    if selected then
      playKey(selected)
      releaseTimer = os.startTimer(0.18)
    else
      for _, control in ipairs(controls) do
        if contains(control, x, y) then handleControl(control.action) break end
      end
    end
  elseif event == "timer" and a == releaseTimer then
    if activePitch and now() >= activeUntil then
      activePitch = nil
      status = "TOUCH A KEY TO PLAY"
      draw()
    end
  elseif event == "monitor_resize" and a == monitorName then
    draw()
  elseif event == "peripheral" or event == "peripheral_detach" then
    speaker = peripheral.find("speaker")
    if not speaker then error("Speaker disconnected.", 0) end
  end
end
