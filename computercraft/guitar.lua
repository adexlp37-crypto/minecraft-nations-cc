local version = "1.0"

local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
if not monitor then error("Connect a 6x6 Advanced Monitor.", 0) end
if not speaker then error("Connect a Speaker to the computer.", 0) end

monitor.setTextScale(0.5)
local monitorName = peripheral.getName(monitor)
local width, height = monitor.getSize()
if width < 80 or height < 45 then
  error("This guitar is designed for a 6x6 Advanced Monitor.", 0)
end

pcall(monitor.setPaletteColor, colors.brown, 0.30, 0.12, 0.03)
pcall(monitor.setPaletteColor, colors.orange, 0.90, 0.38, 0.05)
pcall(monitor.setPaletteColor, colors.gray, 0.22, 0.23, 0.26)

local volume = 2.0
local status = "TOUCH A STRING OR PLAY A CHORD"
local activeString, activeFret = nil, nil
local activeChord = nil
local releaseTimer = nil
local controls, strings, chordButtons = {}, {}, {}
local chars, foregrounds, backgrounds
local blitCache = {}

-- Two-octave speaker range, arranged like standard E A D G B E tuning.
local stringData = {
  { name="e", base=12, color=colors.white },
  { name="B", base=7,  color=colors.lightGray },
  { name="G", base=3,  color=colors.lightGray },
  { name="D", base=10, color=colors.gray },
  { name="A", base=5,  color=colors.gray },
  { name="E", base=0,  color=colors.orange }
}

local chords = {
  { name="C",  notes={0,4,7,12} },
  { name="G",  notes={7,11,14,19} },
  { name="Am", notes={9,12,16,21} },
  { name="F",  notes={5,9,12,17} },
  { name="Em", notes={4,7,11,16} },
  { name="Dm", notes={2,5,9,14} }
}

local function toBlit(color)
  if not blitCache[color] then blitCache[color] = colors.toBlit(color) end
  return blitCache[color]
end

local function newCanvas()
  chars, foregrounds, backgrounds = {}, {}, {}
  local white, black = toBlit(colors.white), toBlit(colors.black)
  for y = 1, height do
    chars[y], foregrounds[y], backgrounds[y] = {}, {}, {}
    for x = 1, width do
      chars[y][x], foregrounds[y][x], backgrounds[y][x] = " ", white, black
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
    for x = x1, x2 do cell(x, y, character or " ", foreground, background) end
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

local function contains(item, x, y)
  return x >= item.x1 and x <= item.x2 and y >= item.y1 and y <= item.y2
end

local function addButton(collection, action, x1, y1, x2, y2, label, color, active)
  local background = active and colors.orange or color
  rectangle(x1, y1, x2, y2, background)
  border(x1, y1, x2, y2, colors.white, background)
  centered(x1, x2, math.floor((y1 + y2) / 2), label,
    active and colors.black or colors.white, background)
  collection[#collection + 1] = { action=action, x1=x1, y1=y1, x2=x2, y2=y2 }
end

local function pitchFor(stringIndex, fret)
  local pitch = stringData[stringIndex].base + fret
  while pitch > 24 do pitch = pitch - 12 end
  return pitch
end

local function draw()
  width, height = monitor.getSize()
  controls, strings, chordButtons = {}, {}, {}
  newCanvas()

  rectangle(1, 1, width, 3, colors.brown)
  centered(1, width, 2, "TOUCH GUITAR  v" .. version, colors.orange, colors.brown)

  local chordGap = 1
  local chordWidth = math.floor((width - 2 - chordGap * (#chords - 1)) / #chords)
  for index, chord in ipairs(chords) do
    local x1 = 2 + (index - 1) * (chordWidth + chordGap)
    local x2 = index == #chords and width - 1 or x1 + chordWidth - 1
    addButton(chordButtons, index, x1, 5, x2, 10, chord.name, colors.gray,
      activeChord == index)
  end

  addButton(controls, "volume_down", 2, 12, math.floor(width * 0.22), 16,
    "- VOLUME", colors.gray, false)
  centered(math.floor(width * 0.24), math.floor(width * 0.76), 14,
    status, colors.lightBlue, colors.black)
  addButton(controls, "volume_up", math.floor(width * 0.78), 12, width - 1, 16,
    string.format("%.1f +", volume), colors.blue, false)

  local boardLeft, boardRight = 7, width - 2
  local boardTop, boardBottom = 19, height - 3
  rectangle(boardLeft, boardTop, boardRight, boardBottom, colors.brown)

  local fretCount = 12
  local fretWidth = (boardRight - boardLeft + 1) / (fretCount + 1)
  local stringSpacing = (boardBottom - boardTop) / (#stringData - 1)

  for fret = 0, fretCount do
    local x1 = boardLeft + math.floor(fret * fretWidth)
    local x2 = boardLeft + math.floor((fret + 1) * fretWidth) - 1
    local lineX = x2
    for y = boardTop, boardBottom do cell(lineX, y, "|", colors.lightGray, colors.brown) end
    centered(x1, x2, boardBottom + 1, tostring(fret), colors.lightGray, colors.black)
  end

  for stringIndex, data in ipairs(stringData) do
    local y = math.floor(boardTop + (stringIndex - 1) * stringSpacing + 0.5)
    textAt(2, y, data.name, data.color, colors.black)
    local thickness = stringIndex >= 5 and 2 or 1
    for offset = 0, thickness - 1 do
      for x = boardLeft, boardRight do cell(x, y + offset, "-", data.color, colors.brown) end
    end
    for fret = 0, fretCount do
      local x1 = boardLeft + math.floor(fret * fretWidth)
      local x2 = boardLeft + math.floor((fret + 1) * fretWidth) - 1
      strings[#strings + 1] = {
        string=stringIndex, fret=fret,
        x1=x1, y1=math.max(boardTop, y - 2),
        x2=x2, y2=math.min(boardBottom, y + 2)
      }
      if activeString == stringIndex and activeFret == fret then
        local cx = math.floor((x1 + x2) / 2)
        rectangle(cx - 1, y - 1, cx + 1, y + 1, colors.orange, "o", colors.black)
      end
    end
  end

  centered(1, width, height, "OPEN STRINGS AT FRET 0  |  TOUCH ANY STRING/FRET", colors.gray, colors.black)
  for y = 1, height do
    monitor.setCursorPos(1, y)
    monitor.blit(table.concat(chars[y]), table.concat(foregrounds[y]), table.concat(backgrounds[y]))
  end
end

local function playString(target)
  activeChord = nil
  activeString, activeFret = target.string, target.fret
  local data = stringData[target.string]
  local pitch = pitchFor(target.string, target.fret)
  status = data.name .. " STRING  |  FRET " .. target.fret
  local ok, played = pcall(speaker.playNote, "guitar", volume, pitch)
  if not ok or played == false then status = "SPEAKER BUSY - TRY AGAIN" end
  draw()
  releaseTimer = os.startTimer(0.20)
end

local function playChord(index)
  activeString, activeFret = nil, nil
  activeChord = index
  status = chords[index].name .. " CHORD"
  for _, pitch in ipairs(chords[index].notes) do
    pcall(speaker.playNote, "guitar", volume, pitch)
  end
  draw()
  releaseTimer = os.startTimer(0.30)
end

draw()
while true do
  local event, a, x, y = os.pullEvent()
  if event == "monitor_touch" and a == monitorName then
    local handled = false
    for _, button in ipairs(chordButtons) do
      if contains(button, x, y) then
        playChord(button.action)
        handled = true
        break
      end
    end
    if not handled then
      for _, button in ipairs(controls) do
        if contains(button, x, y) then
          if button.action == "volume_down" then
            volume = math.max(0.5, volume - 0.5)
          else
            volume = math.min(3.0, volume + 0.5)
          end
          status = "GUITAR VOLUME " .. string.format("%.1f", volume)
          draw()
          handled = true
          break
        end
      end
    end
    if not handled then
      for _, target in ipairs(strings) do
        if contains(target, x, y) then
          playString(target)
          break
        end
      end
    end
  elseif event == "timer" and a == releaseTimer then
    activeString, activeFret, activeChord = nil, nil, nil
    status = "TOUCH A STRING OR PLAY A CHORD"
    draw()
  elseif event == "monitor_resize" and a == monitorName then
    draw()
  elseif event == "peripheral" or event == "peripheral_detach" then
    speaker = peripheral.find("speaker")
    if not speaker then error("Speaker disconnected.", 0) end
  end
end
