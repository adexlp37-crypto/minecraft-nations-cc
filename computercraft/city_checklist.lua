-- Interactive city checklist for a 6x6 Advanced Monitor.
-- Add buildings and members by touching the monitor, then typing on the computer.
local monitor=peripheral.find("monitor")
if not monitor or not monitor.isColor() then error("Connect an Advanced Monitor.",0) end
local speaker=peripheral.find("speaker")
local computer=term.current()
local C=colors
local FILE=".city_checklist_v3"
local args={...}
local data={members={},projects={}}
local tab,page,selected,active="projects",1,nil,nil
local hits,note,pulse,deleteArmed={},"LIVE - Board ready",0,nil

monitor.setTextScale(1)
term.redirect(monitor)

local function sound(kind)
 if not speaker then return end
 if kind=="success" then
  pcall(speaker.playNote,"pling",3,0.75); pcall(speaker.playNote,"pling",4,1.0)
 elseif kind=="done" then
  pcall(speaker.playNote,"bell",3,0.8); pcall(speaker.playNote,"bell",4,1.0)
 elseif kind=="delete" then
  pcall(speaker.playNote,"bass",1,0.5)
 elseif kind=="bad" then
  pcall(speaker.playNote,"basedrum",1,0.6)
 elseif kind=="tab" then
  pcall(speaker.playNote,"bit",2,0.5)
 else
  pcall(speaker.playNote,"hat",2,0.35)
 end
end

local function save()
 local f=fs.open(FILE,"w")
 if not f then note="ERROR - Could not save"; sound("bad"); return false end
 f.write(textutils.serialize(data)); f.close()
 return true
end

local function load()
 if not fs.exists(FILE) then return end
 local f=fs.open(FILE,"r")
 local loaded=f and textutils.unserialize(f.readAll())
 if f then f.close() end
 if type(loaded)=="table" then
  data.members=type(loaded.members)=="table" and loaded.members or {}
  data.projects=type(loaded.projects)=="table" and loaded.projects or {}
 end
end

local function clean(value)
 value=tostring(value or ""):gsub("^%s+",""):gsub("%s+$","")
 return value
end

local function addMember(name)
 name=clean(name)
 if name=="" then return false,"No member entered" end
 for _,member in ipairs(data.members) do
  if member:lower()==name:lower() then return false,"Member already exists" end
 end
 data.members[#data.members+1]=name
 table.sort(data.members,function(a,b) return a:lower()<b:lower() end)
 save()
 return true,"Member added: "..name
end

local function addProject(name)
 name=clean(name)
 if name=="" then return false,"No building entered" end
 for _,project in ipairs(data.projects) do
  if project.name:lower()==name:lower() then return false,"Building already exists" end
 end
 data.projects[#data.projects+1]={name=name,status="TODO",owner="-"}
 save()
 return true,"Building added: "..name
end

load()

-- Command-line support is kept for updater/automation use.
if args[1]=="add" then
 local ok,message=addMember(table.concat(args," ",2)); term.redirect(computer); print(message); if not ok then return end; return
elseif args[1]=="project" and args[2]=="add" then
 local ok,message=addProject(table.concat(args," ",3)); term.redirect(computer); print(message); if not ok then return end; return
end

local function at(x,y,text,fg,bg)
 local w,h=monitor.getSize()
 if x<1 or x>w or y<1 or y>h then return end
 monitor.setCursorPos(x,y)
 monitor.setTextColor(fg or C.white)
 monitor.setBackgroundColor(bg or C.black)
 monitor.write(tostring(text):sub(1,w-x+1))
end

local function fill(x,y,x2,bg)
 local w,h=monitor.getSize()
 if y<1 or y>h then return end
 x=math.max(1,x); x2=math.min(w,x2)
 if x2<x then return end
 monitor.setCursorPos(x,y); monitor.setBackgroundColor(bg); monitor.write(string.rep(" ",x2-x+1))
end

local function cut(text,width)
 text=tostring(text or "")
 if width<2 then return text:sub(1,math.max(0,width)) end
 return #text>width and text:sub(1,width-1).."~" or text
end

local function button(x,y,x2,label,color,action)
 if x2<x then return end
 fill(x,y,x2,color)
 local width=x2-x+1
 local shown=cut(label,width)
 local start=x+math.max(0,math.floor((width-#shown)/2))
 at(start,y,shown,(color==C.yellow or color==C.lime or color==C.lightBlue or color==C.orange) and C.black or C.white,color)
 hits[#hits+1]={x=x,y=y,x2=x2,y2=y,action=action}
end

local function statusColor(status)
 return status=="DONE" and C.lime or status=="BUILD" and C.yellow or C.red
end

local function drawStar()
 local w,h=monitor.getSize()
 local mainW=math.max(28,w-12)
 local sx=mainW+3
 local sy=4
 local star={"   /\\   ","  /__\\  "," /\\  /\\ ","/__\\/__\\","  \\  /  ","   \\/   "}
 local starColors={C.cyan,C.lightBlue,C.blue,C.white}
 local color=starColors[(pulse%#starColors)+1]
 for row,line in ipairs(star) do
  fill(mainW+2,sy+row-1,w,C.black)
  at(sx,sy+row-1,line,color,C.black)
 end
 at(mainW+3,sy+7,"AM YISRAEL",C.lightBlue,C.black)
 at(mainW+5,sy+8,"CHAI",pulse%2==0 and C.white or C.cyan,C.black)
end

local function drawLive()
 local w=monitor.getSize()
 local frames={"|","/","-","\\"}
 fill(1,2,w,C.black)
 at(2,2,"LIVE "..frames[(pulse%4)+1],pulse%2==0 and C.lime or C.green,C.black)
 local summary=#data.projects.." projects  "..#data.members.." members"
 at(10,2,cut(summary,math.max(1,w-22)),C.lightGray,C.black)
 at(w-8,2,textutils.formatTime(os.time(),true),C.gray,C.black)
 drawStar()
end

local draw

local function promptOnComputer(kind)
 note="WAITING - Enter "..kind.." on computer"
 sound("click")
 draw()
 term.redirect(computer)
 term.setBackgroundColor(C.black); term.setTextColor(C.white); term.clear(); term.setCursorPos(1,1)
 print("CITY BUILD BOARD")
 print("")
 if kind=="building" then print("New building name:") else print("New team member name:") end
 term.setTextColor(C.yellow); write("> "); term.setTextColor(C.white)
 local value=read()
 term.redirect(monitor)
 local ok,message
 if kind=="building" then ok,message=addProject(value) else ok,message=addMember(value) end
 note=message
 sound(ok and "success" or "bad")
 if ok then page=1; deleteArmed=nil end
 draw()
end

local function removeSelectedProject()
 if not selected or not data.projects[selected] then note="Select a building first";sound("bad");return end
 if deleteArmed~="project:"..selected then
  deleteArmed="project:"..selected; note="Tap DELETE again to confirm"; sound("bad"); return
 end
 local name=data.projects[selected].name
 table.remove(data.projects,selected); selected=nil; deleteArmed=nil; save()
 note="Deleted: "..name; sound("delete")
end

local function removeActiveMember()
 if not active then note="Select a member first";sound("bad");return end
 local index
 for i,name in ipairs(data.members) do if name==active then index=i;break end end
 if not index then active=nil;note="Member not found";sound("bad");return end
 if deleteArmed~="member:"..active then
  deleteArmed="member:"..active; note="Tap REMOVE again to confirm"; sound("bad"); return
 end
 local name=active
 table.remove(data.members,index)
 for _,project in ipairs(data.projects) do if project.owner==name then project.owner="-";project.status="TODO" end end
 active=nil; deleteArmed=nil; save(); note="Removed: "..name; sound("delete")
end

draw=function()
 local w,h=monitor.getSize()
 local mainW=math.max(28,w-12)
 if mainW>w then mainW=w end
 hits={}
 monitor.setBackgroundColor(C.black); monitor.clear()
 fill(1,1,w,C.gray); at(2,1,"CITY BUILD BOARD",C.white,C.gray)
 at(w-11,1,"TOUCH ONLINE",C.lime,C.gray)
 drawLive()

 local listTop=4
 local listBottom=math.max(listTop,h-9)
 local perPage=math.max(1,listBottom-listTop+1)

 if tab=="projects" then
  at(2,3,"BUILDINGS",C.orange,C.black)
  if #data.projects==0 then
   at(2,5,"No buildings yet.",C.lightGray,C.black)
   at(2,6,"Tap ADD BUILDING below.",C.white,C.black)
  end
  local first=(page-1)*perPage+1
  if first>#data.projects and page>1 then page=math.max(1,page-1);first=(page-1)*perPage+1 end
  local last=math.min(#data.projects,first+perPage-1)
  for i=first,last do
   local project=data.projects[i]
   local y=listTop+i-first
   local bg=selected==i and C.lightGray or C.black
   fill(1,y,mainW,bg)
   at(2,y,project.status,statusColor(project.status),bg)
   at(8,y,cut(project.name,math.max(3,mainW-20)),bg==C.lightGray and C.black or C.white,bg)
   at(mainW-9,y,cut(project.owner,9),bg==C.lightGray and C.black or C.cyan,bg)
   hits[#hits+1]={x=1,y=y,x2=mainW,y2=y,project=i}
  end
  button(1,h-7,mainW,"+ ADD BUILDING",C.orange,function() promptOnComputer("building") end)
  local q=math.floor((mainW-3)/4)
  button(1,h-5,q,"ASSIGN",C.blue,function()
   if selected and data.projects[selected] and active then
    data.projects[selected].owner=active;data.projects[selected].status="BUILD";save()
    note=active.." assigned";deleteArmed=nil;sound("success")
   else note="Select building + team member";sound("bad") end
  end)
  button(q+2,h-5,q*2+1,"DONE",C.lime,function()
   if selected and data.projects[selected] then data.projects[selected].status="DONE";save();note="Marked complete";sound("done")
   else note="Select a building first";sound("bad") end
  end)
  button(q*2+3,h-5,q*3+2,"OPEN",C.red,function()
   if selected and data.projects[selected] then data.projects[selected].status="TODO";data.projects[selected].owner="-";save();note="Reopened";sound("click")
   else note="Select a building first";sound("bad") end
  end)
  button(q*3+4,h-5,mainW,"DELETE",C.brown,removeSelectedProject)
  if #data.projects>perPage then
   button(1,h-3,8,"< PAGE",C.gray,function() if page>1 then page=page-1;sound("click") else sound("bad") end end)
   at(10,h-3,page.."/"..math.max(1,math.ceil(#data.projects/perPage)),C.lightGray,C.black)
   button(16,h-3,24,"PAGE >",C.gray,function() if last<#data.projects then page=page+1;sound("click") else sound("bad") end end)
  end
 else
  at(2,3,"TEAM - tap a name to select",C.lightBlue,C.black)
  if #data.members==0 then
   at(2,5,"No team members yet.",C.lightGray,C.black)
   at(2,6,"Tap ADD MEMBER below.",C.white,C.black)
  end
  local first=(page-1)*perPage+1
  if first>#data.members and page>1 then page=math.max(1,page-1);first=(page-1)*perPage+1 end
  local last=math.min(#data.members,first+perPage-1)
  for i=first,last do
   local name=data.members[i]
   local y=listTop+i-first
   local bg=active==name and C.lightBlue or C.black
   fill(1,y,mainW,bg)
   at(2,y,(active==name and "> " or "  ")..cut(name,mainW-4),bg==C.lightBlue and C.black or C.white,bg)
   hits[#hits+1]={x=1,y=y,x2=mainW,y2=y,member=name}
  end
  button(1,h-7,mainW,"+ ADD MEMBER",C.lightBlue,function() promptOnComputer("member") end)
  button(1,h-5,math.floor(mainW/2)-1,"SELECTED: "..cut(active or "none",10),C.blue,function() note=active and ("Selected: "..active) or "Select a member";sound(active and "click" or "bad") end)
  button(math.floor(mainW/2)+1,h-5,mainW,"REMOVE MEMBER",C.brown,removeActiveMember)
  if #data.members>perPage then
   button(1,h-3,8,"< PAGE",C.gray,function() if page>1 then page=page-1;sound("click") else sound("bad") end end)
   at(10,h-3,page.."/"..math.max(1,math.ceil(#data.members/perPage)),C.lightGray,C.black)
   button(16,h-3,24,"PAGE >",C.gray,function() if last<#data.members then page=page+1;sound("click") else sound("bad") end end)
  end
 end

 -- The two primary tabs always stay at the bottom-left for a tall wall monitor.
 button(1,h-1,12,"PROJECTS",tab=="projects" and C.orange or C.gray,function() tab="projects";page=1;deleteArmed=nil;note="Projects opened";sound("tab") end)
 button(14,h-1,24,"TEAM",tab=="team" and C.lightBlue or C.gray,function() tab="team";page=1;deleteArmed=nil;note="Team opened";sound("tab") end)
 fill(1,h,w,C.black); at(2,h,cut(note,w-2),pulse%2==0 and C.lightGray or C.white,C.black)
end

draw()
local animationTimer=os.startTimer(0.45)
while true do
 local event,p1,x,y=os.pullEventRaw()
 if event=="monitor_touch" then
  local touched=false
  for i=#hits,1,-1 do
   local hit=hits[i]
   if x>=hit.x and x<=hit.x2 and y>=hit.y and y<=hit.y2 then
    touched=true
    if hit.project then
     selected=hit.project;deleteArmed=nil;note=data.projects[selected].name;sound("click")
    elseif hit.member then
     active=hit.member;deleteArmed=nil;note="Selected: "..active;sound("success")
    else hit.action() end
    draw();break
   end
  end
  if not touched then sound("click") end
 elseif event=="timer" and p1==animationTimer then
  pulse=pulse+1;drawLive()
  fill(1,select(2,monitor.getSize()),select(1,monitor.getSize()),C.black)
  at(2,select(2,monitor.getSize()),cut(note,select(1,monitor.getSize())-2),pulse%2==0 and C.lightGray or C.white,C.black)
  animationTimer=os.startTimer(0.45)
 elseif event=="monitor_resize" then
  page=1;draw()
 elseif event=="terminate" then
  term.redirect(computer);term.setBackgroundColor(C.black);term.setTextColor(C.white);term.clear();term.setCursorPos(1,1)
  return
 end
end
