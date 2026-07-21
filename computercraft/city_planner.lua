-- Interactive city planning display for a 6x6 Advanced Monitor.
-- CC:Tweaked: place this file on the computer and run `city_planner`.

local monitor = peripheral.find("monitor")
if not monitor then error("No monitor found. Connect a 6x6 Advanced Monitor.", 0) end
if not monitor.isColor() then error("An Advanced Monitor is required.", 0) end

monitor.setTextScale(0.5)
local oldTerm = term.redirect(monitor)

local C = colors
local projects = {
  { id="military", name="Military Base", kind="Military", color=C.green,
    rect={8,3,93,23}, status="Planned", note="Large northern base and expansion reserve." },
  { id="admin_north", name="North Administration", kind="Administration", color=C.yellow,
    rect={7,24,24,33}, status="Planned", note="Coastal administrative outpost." },
  { id="power", name="Power Plant", kind="Power", color=C.blue,
    rect={25,43,40,51}, status="Planned", note="Power generation site west of the main road." },
  { id="admin_centre", name="Central Administration", kind="Administration", color=C.yellow,
    rect={43,42,57,49}, status="Planned", note="Government building near the city centre." },
  { id="parking", name="Central Parking", kind="Parking", color=C.lightBlue,
    rect={17,58,38,68}, status="Planned", note="Parking area beside the civic district." },
  { id="housing", name="Housing District", kind="Housing", color=C.lightGray,
    rect={26,50,61,76}, status="Planned", note="Primary residential and civic development zone." },
  { id="power_south", name="South Power Plant", kind="Power", color=C.blue,
    rect={13,80,29,88}, status="Optional", note="Secondary power facility near the harbour." },
  { id="winery", name="Winery", kind="Winery", color=C.magenta,
    rect={49,80,65,86}, status="Planned", note="Winery on the southern city road." },
  { id="bank", name="Bank", kind="Bank", color=C.purple,
    rect={46,87,65,92}, status="Planned", note="Financial district and national bank." },
  { id="school", name="School", kind="School", color=C.lime,
    rect={50,93,67,98}, status="Planned", note="School at the southern edge of the city." },
}

-- Normalised outlines based on the supplied planning sketch.
local border = {
  {15,98},{10,90},{12,82},{7,73},{16,64},{23,59},{25,52},{33,48},
  {31,40},{35,31},{43,25},{55,22},{73,24},{83,29},{89,38},{91,48},
  {87,60},{85,73},{79,84},{72,97}
}
local coast = {
  {0,0},{38,0},{38,15},{34,28},{30,41},{20,52},{8,62},{0,67}
}
local mainRoad = {
  {36,27},{34,38},{38,48},{35,58},{38,66},{35,75},{40,83},{42,98}
}
local eastRoads = {
  {{38,34},{52,32},{64,28},{78,27}},
  {{37,40},{52,38},{68,34},{82,31}},
  {{37,47},{54,45},{70,40},{85,37}},
  {{38,54},{56,52},{72,47},{87,43}},
  {{38,60},{57,58},{74,54},{89,49}},
}

local selected = nil
local hitboxes = {}

local function fill(x1, y1, x2, y2, color)
  paintutils.drawFilledBox(math.floor(x1), math.floor(y1), math.floor(x2), math.floor(y2), color)
end

local function text(x, y, value, foreground, background)
  local w, h = monitor.getSize()
  if y < 1 or y > h or x > w then return end
  monitor.setCursorPos(math.max(1, math.floor(x)), math.floor(y))
  monitor.setTextColor(foreground or C.white)
  monitor.setBackgroundColor(background or C.black)
  monitor.write(tostring(value):sub(1, math.max(0, w - math.floor(x) + 1)))
end

local function center(x1, x2, y, value, foreground, background)
  value = tostring(value)
  text(math.floor((x1 + x2 - #value + 1) / 2), y, value, foreground, background)
end

local function line(points, color, tx, ty)
  for i = 1, #points - 1 do
    local a, b = points[i], points[i + 1]
    paintutils.drawLine(tx(a[1]), ty(a[2]), tx(b[1]), ty(b[2]), color)
  end
end

local function wrap(value, width)
  local rows, current = {}, ""
  for word in tostring(value):gmatch("%S+") do
    if #current == 0 then current = word
    elseif #current + #word + 1 <= width then current = current .. " " .. word
    else rows[#rows + 1], current = current, word end
  end
  if #current > 0 then rows[#rows + 1] = current end
  return rows
end

local function button(x1, y1, x2, y2, label, active, action)
  fill(x1, y1, x2, y2, active and C.lightGray or C.gray)
  center(x1, x2, y1, label, active and C.black or C.white,
    active and C.lightGray or C.gray)
  hitboxes[#hitboxes + 1] = {x1=x1,y1=y1,x2=x2,y2=y2,action=action}
end

local function drawMap(mapX1, mapY1, mapX2, mapY2)
  local mapW, mapH = mapX2-mapX1+1, mapY2-mapY1+1
  local tx = function(n) return mapX1 + math.floor(n / 100 * (mapW-1)) end
  local ty = function(n) return mapY1 + math.floor(n / 100 * (mapH-1)) end

  fill(mapX1, mapY1, mapX2, mapY2, C.brown)
  -- Ocean and a rough sandy coastal shelf.
  fill(mapX1, mapY1, tx(37), mapY2, C.blue)
  line(coast, C.lightBlue, tx, ty)
  for y=0,100 do
    local coastX = 38 - math.max(0, y-15) * 0.45
    if y > 67 then coastX = 0 end
    if coastX > 0 then fill(tx(coastX),ty(y),mapX2,ty(y),C.yellow) end
  end
  -- Mountain/river side gives orientation without copying the source image.
  fill(tx(72), mapY1, mapX2, mapY2, C.lightGray)
  line({{71,0},{75,18},{70,37},{76,57},{72,78},{78,100}}, C.gray, tx, ty)
  line({{66,20},{68,40},{65,60},{69,80},{66,100}}, C.cyan, tx, ty)

  line(border, C.red, tx, ty)
  line(mainRoad, C.black, tx, ty)
  for _, road in ipairs(eastRoads) do line(road, C.red, tx, ty) end

  for index, p in ipairs(projects) do
    local r = p.rect
    local x1,y1,x2,y2 = tx(r[1]),ty(r[2]),tx(r[3]),ty(r[4])
    paintutils.drawBox(x1,y1,x2,y2,p.color)
    if selected == index then
      if x2-x1 > 2 and y2-y1 > 2 then paintutils.drawBox(x1+1,y1+1,x2-1,y2-1,C.white) end
    end
    hitboxes[#hitboxes + 1] = {x1=x1,y1=y1,x2=x2,y2=y2,project=index}
  end
end

local function drawSidebar(x1, y1, x2, y2)
  fill(x1,y1,x2,y2,C.black)
  local width = x2-x1+1
  center(x1,x2,y1,"CITY PLAN",C.yellow,C.black)
  paintutils.drawLine(x1,y1+1,x2,y1+1,C.gray)

  if selected then
    local p = projects[selected]
    fill(x1+1,y1+3,x1+2,y1+4,p.color)
    text(x1+4,y1+3,p.name,C.white,C.black)
    text(x1+1,y1+6,"TYPE",C.lightGray,C.black)
    text(x1+1,y1+7,p.kind,p.color,C.black)
    text(x1+1,y1+9,"STATUS",C.lightGray,C.black)
    text(x1+1,y1+10,p.status,p.status == "Optional" and C.orange or C.lime,C.black)
    local rows = wrap(p.note,width-2)
    text(x1+1,y1+12,"NOTES",C.lightGray,C.black)
    for i=1,math.min(#rows,math.max(0,y2-y1-17)) do
      text(x1+1,y1+12+i,rows[i],C.white,C.black)
    end
    button(x1+1,y2-1,x2-1,y2-1,"< LEGEND",false,function() selected=nil end)
  else
    local legend = {
      {C.red,"Border"},{C.blue,"Power"},{C.yellow,"Administration"},
      {C.lightGray,"Housing"},{C.green,"Military"},{C.black,"Roads"},
      {C.purple,"Bank"},{C.lime,"School"},{C.magenta,"Winery"},
      {C.lightBlue,"Parking"},
    }
    local row = y1+3
    for _, item in ipairs(legend) do
      if row > y2-7 then break end
      fill(x1+1,row,x1+2,row,item[1])
      text(x1+4,row,item[2],C.white,C.black)
      row=row+2
    end
    text(x1+1,y2-4,"Touch a marked",C.lightGray,C.black)
    text(x1+1,y2-3,"area for details.",C.lightGray,C.black)
    text(x1+1,y2-1,"Tier III plan",C.yellow,C.black)
  end
end

local function draw()
  hitboxes = {}
  monitor.setBackgroundColor(C.black)
  monitor.setTextColor(C.white)
  monitor.clear()
  local w,h = monitor.getSize()
  local sideW = math.max(20,math.floor(w*0.29))
  local mapX2 = w-sideW-1
  fill(1,1,w,2,C.gray)
  text(2,1,"NATION CITY DEVELOPMENT",C.white,C.gray)
  text(2,2,"TIER III / MASTER PLAN",C.yellow,C.gray)
  drawMap(1,3,mapX2,h)
  drawSidebar(mapX2+2,1,w,h)
end

local function cleanup()
  term.redirect(oldTerm)
  monitor.setBackgroundColor(C.black)
  monitor.setTextColor(C.white)
  monitor.clear()
end

draw()
while true do
  local event, side, x, y = os.pullEventRaw()
  if event == "monitor_touch" then
    for i=#hitboxes,1,-1 do
      local box=hitboxes[i]
      if x>=box.x1 and x<=box.x2 and y>=box.y1 and y<=box.y2 then
        if box.project then selected=box.project elseif box.action then box.action() end
        draw()
        break
      end
    end
  elseif event == "monitor_resize" then
    draw()
  elseif event == "terminate" then
    cleanup()
    return
  end
end

