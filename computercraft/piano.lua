local speaker = peripheral.find("speaker")
if not speaker then
  error("Kein Speaker gefunden. Befestige einen Speaker am Pocket Computer.", 0)
end

local whiteKeys = {
  { name = "C", pitch = 0 },
  { name = "D", pitch = 2 },
  { name = "E", pitch = 4 },
  { name = "F", pitch = 5 },
  { name = "G", pitch = 7 },
  { name = "A", pitch = 9 },
  { name = "H", pitch = 11 },
  { name = "C", pitch = 12 }
}

local blackKeys = {
  { after = 1, name = "C#", pitch = 1 },
  { after = 2, name = "D#", pitch = 3 },
  { after = 4, name = "F#", pitch = 6 },
  { after = 5, name = "G#", pitch = 8 },
  { after = 6, name = "A#", pitch = 10 }
}

local width, height = term.getSize()
local keyTop = 4
local keyBottom = height - 1
local blackBottom = keyTop + math.max(2, math.floor((keyBottom - keyTop) * 0.55))

local function fill(x1, y1, x2, y2, background, foreground, character)
  term.setBackgroundColor(background)
  term.setTextColor(foreground)
  local line = string.rep(character or " ", math.max(0, x2 - x1 + 1))
  for y = y1, y2 do
    term.setCursorPos(x1, y)
    term.write(line)
  end
end

local function boundsForWhite(index)
  local x1 = math.floor((index - 1) * width / #whiteKeys) + 1
  local x2 = math.floor(index * width / #whiteKeys)
  return x1, x2
end

local function blackX(afterIndex)
  local _, leftEnd = boundsForWhite(afterIndex)
  return leftEnd
end

local function draw(activePitch)
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
  term.write("Pocket Piano")

  local exitText = "[X]"
  term.setCursorPos(width - #exitText + 1, 1)
  term.setTextColor(colors.red)
  term.write(exitText)

  term.setTextColor(colors.lightGray)
  term.setCursorPos(1, 2)
  term.write("Tasten anklicken")

  for index, key in ipairs(whiteKeys) do
    local x1, x2 = boundsForWhite(index)
    local background = key.pitch == activePitch and colors.lightBlue or colors.white
    fill(x1, keyTop, x2, keyBottom, background, colors.black)

    if index > 1 then
      fill(x1, keyTop, x1, keyBottom, colors.gray, colors.gray)
    end

    local labelX = math.max(x1, math.floor((x1 + x2 - #key.name + 1) / 2))
    term.setCursorPos(labelX, keyBottom)
    term.setBackgroundColor(background)
    term.setTextColor(colors.black)
    term.write(key.name)
  end

  for _, key in ipairs(blackKeys) do
    local x = blackX(key.after)
    local background = key.pitch == activePitch and colors.blue or colors.black
    fill(x, keyTop, x, blackBottom, background, colors.white)
  end

  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.gray)
  term.setCursorPos(1, height)
  term.write("Q = Ende")
end

local function keyAt(x, y)
  if y < keyTop or y > keyBottom then
    return nil
  end

  if y <= blackBottom then
    for _, key in ipairs(blackKeys) do
      if x == blackX(key.after) then
        return key
      end
    end
  end

  for index, key in ipairs(whiteKeys) do
    local x1, x2 = boundsForWhite(index)
    if x >= x1 and x <= x2 then
      return key
    end
  end
end

local function play(key)
  draw(key.pitch)
  speaker.playNote("harp", 1, key.pitch)
  sleep(0.08)
  draw(nil)
end

draw(nil)

while true do
  local event, first, second, third = os.pullEvent()
  if event == "mouse_click" then
    local x, y = second, third
    if y == 1 and x >= width - 2 then
      break
    end

    local key = keyAt(x, y)
    if key then
      play(key)
    end
  elseif event == "key" and first == keys.q then
    break
  elseif event == "term_resize" then
    width, height = term.getSize()
    keyBottom = height - 1
    blackBottom = keyTop + math.max(2, math.floor((keyBottom - keyTop) * 0.55))
    draw(nil)
  end
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Piano beendet.")
