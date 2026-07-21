-- Minecraft Nations City Planner
-- 6x6 Advanced Monitor editor. Every change is stored on this computer.

local monitor = peripheral.find("monitor")
if not monitor then error("Connect an Advanced Monitor first.", 0) end
if not monitor.isColor() then error("This planner needs an Advanced Monitor.", 0) end

monitor.setTextScale(1)
local oldTerm = term.redirect(monitor)
local C = colors
local SAVE_FILE = ".city_planner_canvas_v3"
local baseMap = paintutils.loadImage("city_base_map.nfp")

local categories = {
  { "BORD", C.red }, { "PWR", C.blue }, { "ADMIN", C.yellow },
  { "HOME", C.lightGray }, { "BASE", C.green }, { "ROAD", C.black },
  { "BANK", C.purple }, { "SCHL", C.lime }, { "WINE", C.magenta },
  { "PARK", C.lightBlue },
}

local grid, canvasW, canvasH = {}, 0, 0
local selectedColor, tool, boxStart = C.red, "paint", nil
local history, hitboxes, notice = {}, {}, "Tap a colour, then draw."

local function writeAt(x, y, value, foreground, background)
  local w, h = monitor.getSize()
  if y < 1 or y > h or x > w then return end
  monitor.setCursorPos(math.max(1, x), y)
  monitor.setTextColor(foreground or C.white)
  monitor.setBackgroundColor(background or C.black)
  monitor.write(tostring(value):sub(1, math.max(0, w - x + 1)))
end

local function terrain(x, y, w)
  return 0 -- transparent editing layer: the base map remains visible.
end

local function makeGrid(w, h)
  local result = {}
  for y = 1, h do
    result[y] = {}
    for x = 1, w do result[y][x] = 0 end
  end
  return result
end

local function paintLine(x1, y1, x2, y2, colour)
  local dx, dy = math.abs(x2-x1), math.abs(y2-y1)
  local sx, sy = x1 < x2 and 1 or -1, y1 < y2 and 1 or -1
  local err = dx - dy
  while true do
    if grid[y1] and grid[y1][x1] then grid[y1][x1] = colour end
    if x1 == x2 and y1 == y2 then break end
    local twice = 2 * err
    if twice > -dy then err = err - dy; x1 = x1 + sx end
    if twice < dx then err = err + dx; y1 = y1 + sy end
  end
end

local function outline(x1, y1, x2, y2, colour)
  local left, right = math.min(x1,x2), math.max(x1,x2)
  local top, bottom = math.min(y1,y2), math.max(y1,y2)
  paintLine(left,top,right,top,colour)
  paintLine(right,top,right,bottom,colour)
  paintLine(right,bottom,left,bottom,colour)
  paintLine(left,bottom,left,top,colour)
end

local function seedPlan()
  grid = makeGrid(canvasW, canvasH)
end

local function copyGrid()
  return textutils.serialize(grid)
end

local function remember()
  history[#history + 1] = copyGrid()
  if #history > 20 then table.remove(history, 1) end
end

local function undo()
  local last = table.remove(history)
  if last then
    local restored = textutils.unserialize(last)
    if type(restored) == "table" then grid = restored; notice = "Last change undone." end
  else
    notice = "Nothing to undo."
  end
end

local function save()
  local file = fs.open(SAVE_FILE, "w")
  if not file then notice = "Could not save."; return end
  file.write(textutils.serialize({ width=canvasW, height=canvasH, grid=grid }))
  file.close()
  notice = "Plan saved on this computer."
end

local function load()
  if not fs.exists(SAVE_FILE) then seedPlan(); notice="Loaded starter plan."; return end
  local file = fs.open(SAVE_FILE, "r")
  local data = file and textutils.unserialize(file.readAll())
  if file then file.close() end
  if type(data) == "table" and type(data.grid) == "table" then
    grid = data.grid
    notice = "Saved plan loaded."
  else
    seedPlan()
    notice = "Save was invalid; starter plan loaded."
  end
end

local function button(x1, y, x2, label, colour, action)
  monitor.setBackgroundColor(colour or C.gray)
  monitor.setTextColor((colour == C.yellow or colour == C.lime or colour == C.lightBlue) and C.black or C.white)
  monitor.setCursorPos(x1, y)
  monitor.write((" " .. label .. " "):sub(1, x2-x1+1))
  hitboxes[#hitboxes + 1] = {x1=x1,y1=y,x2=x2,y2=y,action=action}
end

local function draw()
  local w, h = monitor.getSize()
  local sideW = math.max(13, math.floor(w * 0.31))
  local mapX2 = w - sideW - 1
  local mapY1, mapY2 = 3, h
  local newCanvasW, newCanvasH = mapX2, mapY2-mapY1+1
  if canvasW ~= newCanvasW or canvasH ~= newCanvasH then
    canvasW, canvasH = newCanvasW, newCanvasH
    if #grid == 0 then load() end
  end

  hitboxes = {}
  monitor.setBackgroundColor(C.black)
  monitor.clear()
  monitor.setBackgroundColor(C.gray)
  monitor.setTextColor(C.white)
  monitor.setCursorPos(1,1)
  monitor.write(" CITY PLANNER")
  writeAt(1,2,"EDIT MODE  |  " .. (tool == "box" and "BOX: choose 2 corners" or tool:upper()),C.lightGray,C.black)

  -- The supplied world map is the fixed base layer. The planning layer starts
  -- completely transparent, so every coloured cell belongs to the team.
  for y = 1, canvasH do
    for x = 1, canvasW do
      local base = (baseMap[y] and baseMap[y][x]) or C.black
      local overlay = grid[y] and grid[y][x]
      paintutils.drawPixel(x, mapY1+y-1, overlay and overlay ~= 0 and overlay or base)
    end
  end

  local sx1, sx2 = mapX2+2, w
  monitor.setBackgroundColor(C.black)
  for y=1,h do
    monitor.setCursorPos(sx1,y)
    monitor.write(string.rep(" ",sideW))
  end
  writeAt(sx1,2,"NATION PLAN",C.yellow,C.black)
  writeAt(sx1,3,"6x6 EDITOR",C.lightGray,C.black)
  writeAt(sx1,4,"",C.white,C.black)
  writeAt(sx1,5,"PALETTE",C.white,C.black)

  local row = 6
  for _, item in ipairs(categories) do
    if row > h-7 then break end
    local marker = selectedColor == item[2] and ">" or " "
    button(sx1,row,sx2,marker .. item[1],item[2],function()
      selectedColor=item[2]; tool="paint"; boxStart=nil; notice=item[1] .. " selected."
    end)
    row=row+1
  end
  row = math.max(row+1,h-6)
  button(sx1,row,sx2,"BOX",tool=="box" and C.lightGray or C.gray,function()
    tool="box"; boxStart=nil; notice="Tap two map corners."
  end)
  button(sx1,row+1,sx2,"ERASE",C.gray,function()
    tool="erase"; boxStart=nil; notice="Tap cells to restore terrain."
  end)
  button(sx1,row+2,sx2,"UNDO",C.gray,undo)
  button(sx1,row+3,sx2,"SAVE",C.green,save)
  button(sx1,row+4,sx2,"LOAD",C.blue,load)
  button(sx1,row+5,sx2,"RESET",C.red,function()
    remember(); seedPlan(); notice="Starter plan restored."
  end)

  -- Map cells are the final hitboxes, so their editing takes priority.
  hitboxes[#hitboxes + 1] = {x1=1,y1=mapY1,x2=mapX2,y2=mapY2,map=true}
  writeAt(1,h,notice:sub(1,mapX2),C.white,C.black)
end

local function editCell(x, y)
  if tool == "box" then
    if not boxStart then
      boxStart={x=x,y=y}; notice="Second corner..."
    else
      remember(); outline(boxStart.x,boxStart.y,x,y,selectedColor)
      boxStart=nil; notice="Plot outline drawn."
    end
  else
    remember()
    grid[y][x] = tool == "erase" and 0 or selectedColor
    notice = tool == "erase" and "Base map restored." or "Cell painted."
  end
end

draw()
while true do
  local event, side, x, y = os.pullEventRaw()
  if event == "monitor_touch" then
    for i=#hitboxes,1,-1 do
      local box = hitboxes[i]
      if x >= box.x1 and x <= box.x2 and y >= box.y1 and y <= box.y2 then
        if box.map then editCell(x, y-2) else box.action() end
        draw()
        break
      end
    end
  elseif event == "monitor_resize" then
    grid = {}; canvasW, canvasH = 0, 0; notice="Screen resized; loaded plan."; draw()
  elseif event == "terminate" then
    term.redirect(oldTerm)
    return
  end
end

