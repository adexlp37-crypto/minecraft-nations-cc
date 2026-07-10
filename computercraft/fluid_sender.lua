-- === KONFIGURATION ===
local modemSide = "top"

-- Jetzt fest auf Links und Rechts eingestellt:
local tankLeftSource = "left"   
local tankRightSource = "right"

-- MANUELLE KAPAZITÃ„T (Wichtig, falls der Tank komplett leer ist!)
local defaultLeftCapacity = 790000
local defaultRightCapacity = 790000

local sendInterval = 1 -- Jede Sekunde funken

-- === REDNET INITIALISIEREN ===
if peripheral.isPresent(modemSide) and peripheral.getType(modemSide) == "modem" then
    rednet.open(modemSide)
    print("=== Wireless Tank-Sender aktiv ===")
else
    error("FEHLER: Kein Wireless Modem auf 'top' gefunden!")
end

-- === FEHLERRESISTENTE TANK-ABFRAGE ===
local function getTankData(source, defaultCapacity)
    if not peripheral.isPresent(source) then
        return { name = "Nicht verbunden!", amount = 0, capacity = 0, isError = true }
    end
    
    local tank = peripheral.wrap(source)
    
    -- 1. CC:Tweaked Standard (tanks)
    if tank.tanks then
        local info = tank.tanks()
        if info then
            for _, tankInfo in pairs(info) do
                if tankInfo and tankInfo.amount and tankInfo.amount > 0 then
                    local fluidName = tankInfo.name or "Unbekannt"
                    fluidName = fluidName:gsub("^[^:]+:", ""):gsub("^%l", string.upper)
                    
                    return {
                        name = fluidName,
                        amount = tankInfo.amount,
                        capacity = tankInfo.capacity or defaultCapacity,
                        isError = false
                    }
                end
                if tankInfo and tankInfo.capacity then
                    defaultCapacity = tankInfo.capacity
                end
            end
        end
        return { name = "Leer", amount = 0, capacity = defaultCapacity, isError = false }
    end
    
    -- 2. Fallback fÃ¼r Ã¤ltere/andere Mod-AnschlÃ¼sse
    if tank.getTankInfo then
        local info = tank.getTankInfo()
        if info and info[1] then
            local amt = info[1].contents and info[1].contents.amount or 0
            local fluidName = info[1].contents and info[1].contents.name or "Leer"
            fluidName = fluidName:gsub("^[^:]+:", ""):gsub("^%l", string.upper)
            return {
                name = fluidName,
                amount = amt,
                capacity = info[1].capacity or defaultCapacity,
                isError = false
            }
        end
    end
    
    return { name = "Falscher Block-Typ", amount = 0, capacity = 0, isError = true }
end

-- === MAIN LOOP ===
while true do
    local dataPack = {
        left = getTankData(tankLeftSource, defaultLeftCapacity),
        right = getTankData(tankRightSource, defaultRightCapacity)
    }
    
    local msg = textutils.serializeJSON(dataPack)
    rednet.broadcast(msg, "fluid_monitoring_system")
    
    print(string.format("[%s] Funk raus! L: %s (%d mB) | R: %s (%d mB)", 
        os.date("%X"), dataPack.left.name, dataPack.left.amount, dataPack.right.name, dataPack.right.amount))
    
    os.sleep(sendInterval)
end

