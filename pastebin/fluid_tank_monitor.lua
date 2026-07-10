-- ==========================================
-- CONFIGURATION
-- ==========================================
local REFRESH_RATE = 0.5 
local MANUAL_MAX = 792000 -- <--- CHANGE THIS: (Number of blocks * 8000)

-- ==========================================
-- SYSTEM SEARCH
-- ==========================================
local mon = peripheral.find("monitor")
local tank = peripheral.find("fluid_storage") or peripheral.find("fluid_tank")

if not mon then error("Monitor not found!") end
if not tank then error("Tank not found! Place computer at the bottom block.") end

mon.setTextScale(1)
local width, height = mon.getSize()

-- ==========================================
-- MAIN LOOP
-- ==========================================
while true do
    mon.setBackgroundColor(colors.black)
    mon.clear()
    
    -- Header
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(2, 2)
    mon.write("--- FLUID MONITOR ---")
    
    -- Read Tank Data
    local current = 0
    local fluidName = "Empty"
    
    if tank.tanks then
        local tInfo = tank.tanks()
        if tInfo and tInfo[1] then
            -- Get first fluid slot
            local data = tInfo[1]
            current = data.amount or 0
            
            -- Extract and clean fluid name
            if data.name and data.name ~= "minecraft:empty" then
                local rawName = data.name:match("([^:]+)$")
                fluidName = rawName:sub(1,1):upper() .. rawName:sub(2)
            end
        end
    end
    
    -- Math
    local max = MANUAL_MAX 
    local percentage = math.max(0, math.min(current / max, 1))
    
    -- Draw Bar
    local barWidth = width - 4
    local filled = math.floor(barWidth * percentage)
    
    mon.setCursorPos(3, 4)
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(" ", barWidth))
    
    mon.setCursorPos(3, 4)
    mon.setBackgroundColor(colors.lime)
    mon.write(string.rep(" ", filled))
    
    -- Draw Text
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.white)
    
    mon.setCursorPos(3, 6)
    mon.write("Fluid: " .. fluidName)
    
    mon.setCursorPos(3, 7)
    mon.write("Amount: " .. current .. " / " .. max .. " mB")
    
    mon.setCursorPos(3, 8)
    mon.write("Percent: " .. math.floor(percentage * 100) .. "%")
    
    sleep(REFRESH_RATE)
end
