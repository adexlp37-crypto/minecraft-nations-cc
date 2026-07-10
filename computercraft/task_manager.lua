-- === CONFIGURATION ===
local monitorSide = "left"
local saveFile = "tasks.txt"

local monitor = peripheral.wrap(monitorSide)
if not monitor then
    error("Error: Kein Monitor auf der Seite '" .. monitorSide .. "' gefunden!")
end

local speaker = peripheral.find("speaker")

-- State Variables
local tasks = {}
local animFrame = 0
local animTimer = os.startTimer(0.2) -- Schnellerer Timer fÃ¼r weiche Animationen

-- Click Zones
local clickZones = {}
local newTaskBtnZone = {xMin = 0, xMax = 0, yMin = 0, yMax = 0}

-- Colors
local isColor = monitor.isColor()
local colors_bg   = colors.black
local colors_text = colors.white
local colors_btn  = isColor and colors.lime or colors.white
local colors_btn_text = colors.black

-- === SYSTEM FUNCTIONS ===

local function autoScaleMonitor()
    monitor.setTextScale(1.0)
    local baseW, baseH = monitor.getSize()
    local targetWidth = 40
    local idealScale = baseW / targetWidth
    idealScale = math.max(0.5, math.min(5.0, idealScale))
    local finalScale = math.floor(idealScale * 2 + 0.5) / 2
    monitor.setTextScale(finalScale)
end

-- Neues, erweitertes Sound-System
local function playSound(soundType)
    if not speaker then return end
    
    if soundType == "click" then
        speaker.playNote("bell", 3, 12)
    elseif soundType == "success" then
        speaker.playNote("chime", 3, 15)
        os.sleep(0.1)
        speaker.playNote("chime", 3, 20)
    elseif soundType == "delete" then
        speaker.playNote("snare", 3, 1)
        os.sleep(0.05)
        speaker.playNote("bass", 3, 5)
    elseif soundType == "startup" then
        speaker.playNote("bit", 3, 10)
        os.sleep(0.1)
        speaker.playNote("bit", 3, 15)
    elseif soundType == "error" then
        speaker.playNote("bass", 3, 1)
    end
end

local function loadTasks()
    if fs.exists(saveFile) then
        local file = fs.open(saveFile, "r")
        local content = file.readAll()
        file.close()
        local success, data = pcall(textutils.unserializeJSON, content)
        if success and data then tasks = data end
    end
end

local function saveTasks()
    local file = fs.open(saveFile, "w")
    file.write(textutils.serializeJSON(tasks))
    file.close()
end

-- === UI RENDERING TASKS ===

local function drawHeader(w)
    -- Spinner-Animation
    local spinners = {"|", "/", "-", "\\"}
    local spinChar = spinners[(animFrame % 4) + 1]
    
    monitor.setCursorPos(2, 1)
    monitor.setTextColor(isColor and colors.cyan or colors.white)
    monitor.write(spinChar .. " 3000 year jewish plan " .. spinChar)
    
    -- Scanner-Lauflicht in der Trennlinie
    local dotPos = (math.floor(animFrame / 2) % w) + 1
    monitor.setCursorPos(1, 2)
    
    for i = 1, w do
        if i == dotPos then
            monitor.setTextColor(isColor and colors.lightBlue or colors.white)
            monitor.write("=")
        else
            monitor.setTextColor(colors.gray)
            monitor.write("-")
        end
    end
end

local function drawTasks(w, maxAllowedY)
    local currentY = 4
    
    if #tasks == 0 then
        monitor.setCursorPos(2, currentY)
        monitor.setTextColor(colors.lightGray)
        monitor.write("No tasks open. Chilling time!")
        return
    end

    for id, task in ipairs(tasks) do
        if currentY > maxAllowedY then break end
        
        local fullText = task.name
        local startX = 2 -- Weiter links, da die Ausrufezeichen weg sind
        local maxTextWidth = w - 6
        local currentX = startX
        
        monitor.setTextColor(colors_text)
        for word in fullText:gmatch("%S+") do
            if currentX + #word > startX + maxTextWidth then
                currentY = currentY + 1
                currentX = startX
                if currentY > maxAllowedY then break end
            end
            monitor.setCursorPos(currentX, currentY)
            monitor.write(word .. " ")
            currentX = currentX + #word + 1
        end
        
        -- [X] Delete Button
        local btnX = w - 3
        monitor.setCursorPos(btnX, currentY)
        monitor.setBackgroundColor(isColor and colors.red or colors.black)
        monitor.setTextColor(colors.white)
        monitor.write("[X]")
        monitor.setBackgroundColor(colors_bg)
        
        table.insert(clickZones, {xMin = btnX, xMax = btnX + 2, y = currentY, taskId = id})
        currentY = currentY + 2
    end
end

local function drawNewTaskButton(w, h)
    local btnY1 = h - 3
    local btnY2 = h - 2
    local btnY3 = h - 1
    
    -- Pulsierende Pfeil-Animation
    local bounce = (math.floor(animFrame / 2)) % 4
    local decoL, decoR
    if bounce == 0 then decoL, decoR = ">  ", "  <"
    elseif bounce == 1 then decoL, decoR = " > ", " < "
    elseif bounce == 2 then decoL, decoR = "  >", "<  "
    else decoL, decoR = " > ", " < " end
    
    local textLine = " " .. decoL .. " CREATE NEW TASK " .. decoR .. " "
    local totalWidth = #textLine
    local btnX = math.floor((w - totalWidth) / 2)
    
    if btnX < 1 then btnX = 1 end
    
    monitor.setBackgroundColor(colors_btn)
    monitor.setTextColor(colors_btn_text)
    
    monitor.setCursorPos(btnX, btnY1)
    monitor.write(string.rep("#", math.min(totalWidth, w)))
    monitor.setCursorPos(btnX, btnY2)
    monitor.write(string.sub(textLine, 1, w))
    monitor.setCursorPos(btnX, btnY3)
    monitor.write(string.rep("#", math.min(totalWidth, w)))
    
    newTaskBtnZone = {xMin = btnX, xMax = btnX + totalWidth, yMin = btnY1, yMax = btnY3}
    
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end

local function drawUI()
    local w, h = monitor.getSize()
    
    monitor.setBackgroundColor(colors_bg)
    monitor.clear()
    clickZones = {} 
    
    drawHeader(w)
    drawTasks(w, h - 5)
    drawNewTaskButton(w, h)
end

-- === INTERACTIVE TERMINAL ===

local function createNewTaskInteractive()
    term.clear()
    term.setCursorPos(1,1)
    print("=== CREATE NEW TASK ===")
    print("")
    
    write("Whats the task? -> ")
    local tName = read()
    
    if tName == "" then 
        playSound("error")
        print("\nAborted: Task cannot be empty!")
        os.sleep(1.5)
    else
        -- Einfach hinten anhÃ¤ngen, da Importance wegfÃ¤llt
        table.insert(tasks, {name = tName})
        saveTasks()
        
        playSound("success")
        print("\nTask saved! Updating Board...")
        os.sleep(1)
    end
    
    term.clear()
    term.setCursorPos(1,1)
    print("System active. Click 'NEW TASK' on the monitor to add a mission.")
end

-- === MAIN LOOP ===

autoScaleMonitor()
loadTasks()
term.clear()
term.setCursorPos(1,1)

if speaker then
    print("Speaker-Block aktiv! Sound geladen.")
    playSound("startup")
else
    print("Notice: Kein Speaker. Sound ist stumm.")
end
print("System active. Click 'NEW TASK' on the monitor to add a mission.")

while true do
    drawUI()
    local event, p1, p2, p3 = os.pullEvent()
    
    if event == "monitor_resize" and p1 == monitorSide then
        autoScaleMonitor()
        
    elseif event == "monitor_touch" and p1 == monitorSide then
        local x, y = p2, p3
        
        if y >= newTaskBtnZone.yMin and y <= newTaskBtnZone.yMax and x >= newTaskBtnZone.xMin and x <= newTaskBtnZone.xMax then
            playSound("click")
            createNewTaskInteractive()
        end
        
        for _, zone in ipairs(clickZones) do
            if y == zone.y and x >= zone.xMin and x <= zone.xMax then
                playSound("delete")
                table.remove(tasks, zone.taskId)
                saveTasks()
                break
            end
        end
        
    elseif event == "timer" and p1 == animTimer then
        animFrame = animFrame + 1
        animTimer = os.startTimer(0.2) -- Loop aufrecht erhalten
    end
end

