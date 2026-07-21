-- Shared building and infrastructure checklist for an Advanced Monitor.
-- Start with your Minecraft name: city_checklist Azadi

local monitor = peripheral.find("monitor")
if not monitor then error("Connect an Advanced Monitor first.", 0) end
if not monitor.isColor() then error("This board needs an Advanced Monitor.", 0) end

monitor.setTextScale(1)
local oldTerm = term.redirect(monitor)
local C = colors
local SAVE_FILE = ".city_checklist_data"
local member = table.concat({ ... }, " ")
if member == "" then member = "UNASSIGNED" end

local defaultProjects = {
  {name="Military Base", kind="Building"},
  {name="Main Power Plant", kind="Infrastructure"},
  {name="Administration Building", kind="Building"},
  {name="Housing District", kind="District"},
  {name="Main Roads", kind="Infrastructure"},
  {name="Parking", kind="Infrastructure"},
  {name="National Bank", kind="Building"},
  {name="School", kind="Building"},
  {name="Winery", kind="Building"},
  {name="South Power Plant", kind="Optional"},
  {name="Market Square", kind="Optional"},
  {name="Storage Yard", kind="Optional"},
  {name="Harbor Expansion", kind="Optional"},
}

local projects, page, selected, hitboxes, notice = {}, 1, nil, {}, "Select a project."

local function save()
  local file = fs.open(SAVE_FILE, "w")
  if not file then notice="Save failed."; return end
  file.write(textutils.serialize(projects))
  file.close()
  notice="Saved."
end

local function load()
  if fs.exists(SAVE_FILE) then
    local file = fs.open(SAVE_FILE, "r")
    local saved = file and textutils.unserialize(file.readAll())
    if file then file.close() end
    if type(saved) == "table" then projects=saved; return end
  end
  for _, project in ipairs(defaultProjects) do
    projects[#projects+1] = {name=project.name, kind=project.kind, status="TODO", owner="-"}
  end
end

local function writeAt(x,y,value,foreground,background)
  local w,h=monitor.getSize()
  if y<1 or y>h or x>w then return end
  monitor.setCursorPos(math.max(1,x),y)
  monitor.setTextColor(foreground or C.white)
  monitor.setBackgroundColor(background or C.black)
  monitor.write(tostring(value):sub(1,math.max(0,w-x+1)))
end

local function short(value, width)
  value=tostring(value or "")
  return #value>width and value:sub(1,math.max(1,width-1)).."~" or value
end

local function button(x1,y,x2,label,colour,action)
  monitor.setCursorPos(x1,y)
  monitor.setBackgroundColor(colour)
  monitor.setTextColor(colour==C.yellow or colour==C.lime and C.black or C.white)
  monitor.write((" "..label.." "):sub(1,x2-x1+1))
  hitboxes[#hitboxes+1]={x1=x1,y1=y,x2=x2,y2=y,action=action}
end

local function statusColour(status)
  if status=="DONE" then return C.lime end
  if status=="BUILD" then return C.yellow end
  return C.red
end

local function draw()
  local w,h=monitor.getSize()
  hitboxes={}
  monitor.setBackgroundColor(C.black)
  monitor.clear()
  monitor.setBackgroundColor(C.gray)
  monitor.setCursorPos(1,1)
  monitor.setTextColor(C.white)
  monitor.write(" CITY BUILD CHECKLIST")
  writeAt(1,2,"Logged in: "..short(member,w-12),C.lightBlue,C.black)
  writeAt(w-7,2,"Pg "..page,C.lightGray,C.black)

  local rowsPerPage=h-9
  local first=(page-1)*rowsPerPage+1
  local last=math.min(#projects,first+rowsPerPage-1)
  for index=first,last do
    local project=projects[index]
    local y=3+(index-first)
    local active=selected==index
    monitor.setBackgroundColor(active and C.lightGray or C.black)
    monitor.setCursorPos(1,y)
    monitor.write(string.rep(" ",w))
    writeAt(1,y,project.status,statusColour(project.status),active and C.lightGray or C.black)
    writeAt(7,y,short(project.name,math.max(8,w-20)),active and C.black or C.white,active and C.lightGray or C.black)
    writeAt(w-10,y,short(project.owner,9),active and C.black or C.cyan,active and C.lightGray or C.black)
    hitboxes[#hitboxes+1]={x1=1,y1=y,x2=w,y2=y,project=index}
  end

  local controlsY=h-5
  button(1,controlsY,8,"TAKE",C.blue,function()
    if not selected then notice="Select a project first." elseif member=="UNASSIGNED" then notice="Run: city_checklist YourName" else
      projects[selected].owner=member; projects[selected].status="BUILD"; save()
    end
  end)
  button(10,controlsY,17,"DONE",C.lime,function()
    if selected then projects[selected].status="DONE"; save() else notice="Select a project first." end
  end)
  button(19,controlsY,26,"TODO",C.red,function()
    if selected then projects[selected].status="TODO"; projects[selected].owner="-"; save() else notice="Select a project first." end
  end)
  button(28,controlsY,w,"SAVE",C.green,save)
  button(1,h-3,8,"< PAGE",C.gray,function() if page>1 then page=page-1 end end)
  button(10,h-3,17,"PAGE >",C.gray,function() if last<#projects then page=page+1 end end)
  button(19,h-3,w,"REFRESH",C.gray,function() notice="Board refreshed." end)
  writeAt(1,h,short(notice,w),C.lightGray,C.black)
end

load()
draw()
while true do
  local event,side,x,y=os.pullEventRaw()
  if event=="monitor_touch" then
    for i=#hitboxes,1,-1 do
      local box=hitboxes[i]
      if x>=box.x1 and x<=box.x2 and y>=box.y1 and y<=box.y2 then
        if box.project then selected=box.project; notice=projects[selected].name else box.action() end
        draw()
        break
      end
    end
  elseif event=="monitor_resize" then
    draw()
  elseif event=="terminate" then
    term.redirect(oldTerm)
    return
  end
end

