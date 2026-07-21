-- Touch checklist. Commands: add/remove Name | project add Building name
local monitor=peripheral.find("monitor")
if not monitor or not monitor.isColor() then error("Connect an Advanced Monitor.",0) end
local speaker=peripheral.find("speaker") -- Optional: the board stays fully usable without one.
monitor.setTextScale(1)
local old=term.redirect(monitor)
local C=colors
local FILE=".city_checklist_v2"
local args={...}
local defaults={"Military Base","Main Power Plant","Administration Building","Housing District","Main Roads","Parking","National Bank","School","Winery","South Power Plant","Market Square","Storage Yard","Harbor Expansion"}
local data={members={},projects={}}
local tab,page,selected,active,hits,note="projects",1,nil,nil,{},"Tap a project."

local function sound(kind)
 if not speaker then return end
 if kind=="done" then pcall(speaker.playNote,"pling",3,0.8)
 elseif kind=="bad" then pcall(speaker.playNote,"bass",1,0.45)
 else pcall(speaker.playNote,"hat",2,0.35) end
end
local function save() local f=fs.open(FILE,"w"); if f then f.write(textutils.serialize(data)); f.close(); note="Saved." end end
local function load()
 if fs.exists(FILE) then local f=fs.open(FILE,"r"); local d=f and textutils.unserialize(f.readAll()); if f then f.close() end; if type(d)=="table" and d.projects then data=d; return end end
 for _,n in ipairs(defaults) do data.projects[#data.projects+1]={name=n,status="TODO",owner="-"} end
end
local function add(name)
 if not name or name=="" then print("Usage: city_checklist add Name"); return end
 for _,m in ipairs(data.members) do if m:lower()==name:lower() then print("Already added."); return end end
 data.members[#data.members+1]=name; table.sort(data.members); save(); print("Added "..name)
end
local function remove(name)
 for i,m in ipairs(data.members) do if m:lower()==tostring(name):lower() then table.remove(data.members,i); if active==m then active=nil end; save(); print("Removed "..m); return end end
 print("Member not found.")
end
local function addProject(name)
 if not name or name=="" then print("Usage: city_checklist project add Building name"); return end
 for _,p in ipairs(data.projects) do if p.name:lower()==name:lower() then print("Building already exists."); return end end
 data.projects[#data.projects+1]={name=name,status="TODO",owner="-"}; save(); print("Added building: "..name)
end
load()
if args[1]=="add" then add(table.concat(args," ",2)); term.redirect(old); return end
if args[1]=="remove" then remove(table.concat(args," ",2)); term.redirect(old); return end
if args[1]=="project" and args[2]=="add" then addProject(table.concat(args," ",3)); term.redirect(old); return end

local function at(x,y,s,fg,bg) local w,h=monitor.getSize(); if y<1 or y>h then return end; monitor.setCursorPos(x,y); monitor.setTextColor(fg or C.white); monitor.setBackgroundColor(bg or C.black); monitor.write(tostring(s):sub(1,w-x+1)) end
local function cut(s,n) s=tostring(s or ""); return #s>n and s:sub(1,n-1).."~" or s end
local function btn(x,y,x2,label,col,fn) monitor.setCursorPos(x,y); monitor.setBackgroundColor(col); monitor.setTextColor((col==C.yellow or col==C.lime) and C.black or C.white); monitor.write((" "..label.." "):sub(1,x2-x+1)); hits[#hits+1]={x=x,y=y,x2=x2,y2=y,fn=fn} end
local function sc(s) return s=="DONE" and C.lime or s=="BUILD" and C.yellow or C.red end
local function draw()
 local w,h=monitor.getSize(); hits={}; monitor.setBackgroundColor(C.black); monitor.clear(); monitor.setBackgroundColor(C.gray); monitor.setCursorPos(1,1); monitor.setTextColor(C.white); monitor.write(" CITY BUILD BOARD")
 -- Leave a clear header area: tabs are deliberately lower for easy tapping.
 btn(1,4,11,"PROJECTS",tab=="projects" and C.lightBlue or C.gray,function() tab="projects";page=1 end)
 btn(13,4,20,"TEAM",tab=="team" and C.lightBlue or C.gray,function() tab="team";page=1 end)
 at(22,4,"Active: "..cut(active or "none",w-29),C.yellow,C.black)
 if tab=="projects" then
  local per=h-10; local first=(page-1)*per+1; local last=math.min(#data.projects,first+per-1)
  for i=first,last do local p=data.projects[i]; local y=5+i-first; local bg=selected==i and C.lightGray or C.black; monitor.setBackgroundColor(bg); monitor.setCursorPos(1,y); monitor.write(string.rep(" ",w)); at(1,y,p.status,sc(p.status),bg); at(7,y,cut(p.name,w-19),bg==C.lightGray and C.black or C.white,bg); at(w-10,y,cut(p.owner,9),bg==C.lightGray and C.black or C.cyan,bg); hits[#hits+1]={x=1,y=y,x2=w,y2=y,project=i} end
  btn(1,h-4,8,"ASSIGN",C.blue,function() if selected and active then data.projects[selected].owner=active;data.projects[selected].status="BUILD";save();sound("click") else note="Select project + team member.";sound("bad") end end)
  btn(10,h-4,17,"DONE",C.lime,function() if selected then data.projects[selected].status="DONE";save();sound("done") else sound("bad") end end)
  btn(19,h-4,26,"OPEN",C.red,function() if selected then data.projects[selected].status="TODO";data.projects[selected].owner="-";save();sound("click") else sound("bad") end end)
  btn(28,h-4,w,"SAVE",C.green,function() save();sound("click") end)
  btn(1,h-2,9,"< PAGE",C.gray,function() if page>1 then page=page-1 end end); btn(11,h-2,19,"PAGE >",C.gray,function() if last<#data.projects then page=page+1 end end)
 else
  at(1,5,"Tap a member to make them active.",C.lightGray,C.black)
  if #data.members==0 then at(1,7,"No members yet.",C.red,C.black); at(1,8,"Use computer: city_checklist add Name",C.white,C.black) end
  for i,m in ipairs(data.members) do local y=6+i; if y>h-2 then break end; local bg=active==m and C.lightBlue or C.black; monitor.setBackgroundColor(bg); monitor.setCursorPos(1,y); monitor.write(string.rep(" ",w)); at(2,y,(active==m and "> " or "  ")..m,bg==C.lightBlue and C.black or C.white,bg); hits[#hits+1]={x=1,y=y,x2=w,y2=y,member=m} end
 end
 if tab=="projects" then at(22,h-2,"Add: project add Building name",C.lightGray,C.black) end
 at(1,h,cut(note,w),C.lightGray,C.black)
end
draw()
while true do local e,_,x,y=os.pullEventRaw(); if e=="monitor_touch" then for i=#hits,1,-1 do local b=hits[i]; if x>=b.x and x<=b.x2 and y>=b.y and y<=b.y2 then if b.project then selected=b.project;note=data.projects[selected].name;sound("click") elseif b.member then active=b.member;note="Active: "..active;sound("click") else b.fn() end; draw();break end end elseif e=="monitor_resize" then draw() elseif e=="terminate" then term.redirect(old);return end end
