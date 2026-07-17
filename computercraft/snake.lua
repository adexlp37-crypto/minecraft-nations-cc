local version = "1.0"
local highScoreFile = ".snake_highscore"
local baseSpeed = 0.28
local minimumSpeed = 0.07

local monitor = peripheral.find("monitor")
if not monitor then error("Connect an Advanced Monitor first.", 0) end
monitor.setTextScale(0.5)

local speaker = peripheral.find("speaker")
local monitorName = peripheral.getName(monitor)
local width, height = monitor.getSize()
local panelWidth = math.max(13, math.min(18, math.floor(width * 0.30)))
local gridX, gridY = 2, 4
local panelX = width - panelWidth + 1
local gridPixelRight = panelX - 3
local gridWidth = math.floor((gridPixelRight - gridX + 1) / 2)
gridPixelRight = gridX + gridWidth * 2 - 1
local gridHeight = height - gridY

if gridWidth < 10 or gridHeight < 12 then
  error("Monitor is too small. Use a larger Advanced Monitor.", 0)
end

pcall(monitor.setPaletteColor, colors.blue, 0.02, 0.18, 0.58)
pcall(monitor.setPaletteColor, colors.green, 0.08, 0.55, 0.18)
pcall(monitor.setPaletteColor, colors.lime, 0.35, 1.00, 0.25)

local function loadHighScore()
  if not fs.exists(highScoreFile) then return 0 end
  local file = fs.open(highScoreFile, "r")
  if not file then return 0 end
  local value = tonumber(file.readAll()) or 0
  file.close()
  return math.max(0, math.floor(value))
end

local function saveHighScore(value)
  local file = fs.open(highScoreFile, "w")
  if file then
    file.write(tostring(value))
    file.close()
  end
end

local highScore = loadHighScore()
local score = 0
local snake = {}
local food = { x=1, y=1 }
local direction = { x=1, y=0 }
local pendingDirection = { x=1, y=0 }
local state = "ready"
local buttons = {}
local flashButton = nil
local flashUntil = 0
local tickTimer = nil

math.randomseed(os.epoch and os.epoch("utc") or math.floor(os.clock() * 100000))

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

local function centered(x1, x2, y, text, foreground, background)
  text = tostring(text)
  local x = x1 + math.max(0, math.floor((x2 - x1 + 1 - #text) / 2))
  writeAt(x, y, text, foreground, background)
end

local function sound(kind)
  if not speaker then return end
  if kind == "eat" then
    pcall(speaker.playNote, "pling", 1.2, 18)
  elseif kind == "start" then
    pcall(speaker.playNote, "pling", 0.8, 10)
  elseif kind == "over" then
    pcall(speaker.playSound, "minecraft:block.note_block.bass", 1.0, 0.55)
  end
end

local function occupied(x, y)
  for _, part in ipairs(snake) do
    if part.x == x and part.y == y then return true end
  end
  return false
end

local function placeFood()
  local available = gridWidth * gridHeight - #snake
  if available <= 0 then return false end
  repeat
    food.x = math.random(1, gridWidth)
    food.y = math.random(1, gridHeight)
  until not occupied(food.x, food.y)
  return true
end

local function resetGame()
  score = 0
  direction = { x=1, y=0 }
  pendingDirection = { x=1, y=0 }
  local centerX = math.max(5, math.floor(gridWidth / 2))
  local centerY = math.floor(gridHeight / 2)
  snake = {
    { x=centerX, y=centerY },
    { x=centerX - 1, y=centerY },
    { x=centerX - 2, y=centerY },
    { x=centerX - 3, y=centerY }
  }
  placeFood()
  state = "ready"
end

local function addButton(action, x1, y1, x2, y2, label, background)
  local flashed = flashButton == action and os.clock() < flashUntil
  local bg = flashed and colors.white or background
  local fg = flashed and colors.blue or colors.white
  fill(x1, y1, x2, y2, bg)
  centered(x1, x2, math.floor((y1 + y2) / 2), label, fg, bg)
  buttons[#buttons + 1] = { action=action, x1=x1, y1=y1, x2=x2, y2=y2 }
end

local function drawCell(x, y, background, character, foreground)
  local px = gridX + (x - 1) * 2
  local py = gridY + y - 1
  fill(px, py, px + 1, py, background)
  if character then writeAt(px, py, character, foreground or colors.white, background) end
end

local function drawBoard()
  fill(1, 3, gridPixelRight + 1, 3, colors.gray)
  fill(1, height, gridPixelRight + 1, height, colors.gray)
  fill(1, 3, 1, height, colors.gray)
  fill(gridPixelRight + 1, 3, gridPixelRight + 1, height, colors.gray)
  fill(gridX, gridY, gridPixelRight, height - 1, colors.black)

  local foodColors = { colors.red, colors.orange, colors.yellow, colors.orange }
  local foodColor = foodColors[math.floor(os.clock() * 5) % #foodColors + 1]
  drawCell(food.x, food.y, foodColor, "<>", colors.white)

  for index = #snake, 1, -1 do
    local part = snake[index]
    if index == 1 then
      local eye = direction.x < 0 and ": " or direction.x > 0 and " :" or "::"
      drawCell(part.x, part.y, colors.lime, eye, colors.black)
    else
      drawCell(part.x, part.y, colors.green)
    end
  end

  if state ~= "running" then
    local boxY = math.floor((gridY + height - 1) / 2) - 2
    fill(4, boxY, gridPixelRight - 2, boxY + 4, colors.gray)
    if state == "gameover" then
      centered(4, gridPixelRight - 2, boxY + 1, "GAME OVER", colors.red, colors.gray)
      centered(4, gridPixelRight - 2, boxY + 3, "TOUCH PLAY", colors.white, colors.gray)
    elseif state == "paused" then
      centered(4, gridPixelRight - 2, boxY + 1, "PAUSED", colors.yellow, colors.gray)
      centered(4, gridPixelRight - 2, boxY + 3, "TOUCH RESUME", colors.white, colors.gray)
    else
      centered(4, gridPixelRight - 2, boxY + 1, "SNAKE READY", colors.lime, colors.gray)
      centered(4, gridPixelRight - 2, boxY + 3, "TOUCH PLAY", colors.white, colors.gray)
    end
  end
end

local function drawPanel()
  fill(panelX, 3, width, height, colors.black)
  centered(panelX, width, 4, "TOUCH CONTROL", colors.lightBlue, colors.black)
  local innerLeft, innerRight = panelX + 1, width - 1
  local middle = math.floor((innerLeft + innerRight) / 2)
  addButton("up", middle - 3, 6, middle + 3, 8, "UP", colors.blue)
  addButton("left", innerLeft, 10, middle - 1, 12, "LEFT", colors.blue)
  addButton("right", middle + 1, 10, innerRight, 12, "RIGHT", colors.blue)
  addButton("down", middle - 3, 14, middle + 3, 16, "DOWN", colors.blue)

  local playLabel = state == "running" and "PAUSE" or state == "paused" and "RESUME" or "PLAY"
  addButton("toggle", innerLeft, height - 7, innerRight, height - 5, playLabel,
    state == "running" and colors.orange or colors.green)
  addButton("new", innerLeft, height - 3, innerRight, height - 1, "NEW GAME", colors.red)
end

local function draw()
  width, height = monitor.getSize()
  buttons = {}
  monitor.setBackgroundColor(colors.black)
  monitor.clear()
  fill(1, 1, width, 1, colors.blue)
  fill(1, 2, width, 2, colors.white)
  centered(1, width, 1, "SNAKE  //  ADVANCED MONITOR", colors.white, colors.blue)
  writeAt(2, 2, "SCORE " .. tostring(score), colors.blue, colors.white)
  local best = "BEST " .. tostring(highScore)
  writeAt(width - #best - 1, 2, best, colors.blue, colors.white)
  drawBoard()
  drawPanel()
end

local function setDirection(x, y)
  if x == -direction.x and y == -direction.y then return end
  pendingDirection = { x=x, y=y }
  if state == "ready" then
    state = "running"
    sound("start")
  elseif state == "gameover" then
    resetGame()
    state = "running"
    if not (x == -direction.x and y == -direction.y) then pendingDirection = { x=x, y=y } end
    sound("start")
  end
end

local function toggleGame()
  if state == "running" then
    state = "paused"
  elseif state == "paused" then
    state = "running"
  elseif state == "gameover" then
    resetGame()
    state = "running"
    sound("start")
  else
    state = "running"
    sound("start")
  end
end

local function moveSnake()
  if state ~= "running" then return end
  direction = { x=pendingDirection.x, y=pendingDirection.y }
  local head = { x=snake[1].x + direction.x, y=snake[1].y + direction.y }
  local grow = head.x == food.x and head.y == food.y

  if head.x < 1 or head.x > gridWidth or head.y < 1 or head.y > gridHeight then
    state = "gameover"
    sound("over")
    return
  end

  local collisionLimit = #snake - (grow and 0 or 1)
  for index = 1, collisionLimit do
    if snake[index].x == head.x and snake[index].y == head.y then
      state = "gameover"
      sound("over")
      return
    end
  end

  table.insert(snake, 1, head)
  if grow then
    score = score + 1
    if score > highScore then
      highScore = score
      saveHighScore(highScore)
    end
    sound("eat")
    if not placeFood() then state = "gameover" end
  else
    table.remove(snake)
  end
end

local function runAction(action)
  flashButton, flashUntil = action, os.clock() + 0.15
  if action == "up" then setDirection(0, -1)
  elseif action == "down" then setDirection(0, 1)
  elseif action == "left" then setDirection(-1, 0)
  elseif action == "right" then setDirection(1, 0)
  elseif action == "toggle" then toggleGame()
  elseif action == "new" then resetGame() end
end

local function currentSpeed()
  return math.max(minimumSpeed, baseSpeed - score * 0.008)
end

resetGame()
draw()
tickTimer = os.startTimer(currentSpeed())

local ok, failure = pcall(function()
  while true do
    local event, a, b, c = os.pullEvent()
    if event == "timer" and a == tickTimer then
      moveSnake()
      draw()
      tickTimer = os.startTimer(currentSpeed())
    elseif event == "monitor_touch" and a == monitorName then
      for index = #buttons, 1, -1 do
        local button = buttons[index]
        if b >= button.x1 and b <= button.x2 and c >= button.y1 and c <= button.y2 then
          runAction(button.action)
          draw()
          break
        end
      end
    elseif event == "key" then
      if a == keys.up or a == keys.w then setDirection(0, -1)
      elseif a == keys.down or a == keys.s then setDirection(0, 1)
      elseif a == keys.left or a == keys.a then setDirection(-1, 0)
      elseif a == keys.right or a == keys.d then setDirection(1, 0)
      elseif a == keys.space then toggleGame()
      elseif a == keys.r then resetGame() end
      draw()
    elseif event == "monitor_resize" then
      error("Monitor size changed. Restart snake.", 0)
    elseif event == "peripheral_detach" and a == monitorName then
      error("Monitor disconnected.", 0)
    end
  end
end)

monitor.setBackgroundColor(colors.black)
monitor.setTextColor(colors.white)
monitor.clear()
monitor.setCursorPos(1, 1)
if not ok and tostring(failure) ~= "Terminated" then error(failure, 0) end
