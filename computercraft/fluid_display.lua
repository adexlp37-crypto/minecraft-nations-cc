-- === KONFIGURATION ===
local modemSide = "top"
local monitorName = "left" -- Wo hÃ¤ngt der groÃŸe Monitor?

-- === INITIALISIEREN ===
if peripheral.isPresent(modemSide) and peripheral.getType(modemSide) == "modem" then
    rednet.open(modemSide)
    print("Monitor-EmpfÃ¤nger aktiv. Warte auf Tank-Daten...")
else
    error("FEHLER: Kein Wireless Modem auf 'top' gefunden!")
end

local monitor = peripheral.wrap(monitorName)
if not monitor then
    error("FEHLER: Kein Monitor auf '" .. monitorName .. "' gefunden!")
end
monitor.setTextScale(1.0)

-- === HILFSFUNKTION: LADEBALKEN ZEICHNEN ===
local function drawProgressBar(mon, x, y, width, percent)
    mon.setCursorPos(x, y)
    local filled = math.floor(width * (percent / 100))
    if filled > width then filled = width end
    if filled < 0 then filled = 0 end
    
    -- GefÃ¼llter Teil (GrÃ¼n)
    mon.setBackgroundColor(colors.green)
    mon.write(string.rep(" ", filled))
    
    -- Leerer Teil (Dunkelgrau)
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(" ", width - filled))
    
    -- Hintergrund wieder zurÃ¼cksetzen
    mon.setBackgroundColor(colors.black)
end

-- === HILFSFUNKTION: EINE TANK-SPALTE ANZEIGEN ===
local function drawTankColumn(mon, title, tankData, startX, width)
    -- Berechne Prozent
    local percent = 0
    if tankData.capacity > 0 then
        percent = (tankData.amount / tankData.capacity) * 100
    end
    
    -- Titel (z.B. "=== LINKER TANK ===")
    mon.setTextColor(colors.yellow)
    mon.setCursorPos(startX, 3)
    mon.write(title)
    
    -- FlÃ¼ssigkeitstyp
    mon.setTextColor(colors.white)
    mon.setCursorPos(startX, 5)
    mon.write("Inhalt: " .. tankData.name)
    
    -- Menge / KapazitÃ¤t
    mon.setCursorPos(startX, 6)
    mon.write(string.format("%d / %d mB", tankData.amount, tankData.capacity))
    
    -- Prozenttext
    mon.setCursorPos(startX, 7)
    mon.write(string.format("Fuelle: %.1f%%", percent))
    
    -- Der visuelle Balken
    drawProgressBar(mon, startX, 9, width - 2, percent)
end

-- === MAIN LOOP ===
while true do
    -- Auf Funkspruch vom Tank-Computer warten
    local senderId, message, protocol = rednet.receive("fluid_monitoring_system")
    
    if message then
        local success, data = pcall(textutils.unserializeJSON, message)
        
        if success and data and data.left and data.right then
            local maxW, maxH = monitor.getSize()
            
            -- Bildschirm vorbereiten
            monitor.setBackgroundColor(colors.black)
            monitor.clear()
            
            -- HauptÃ¼berschrift ganz oben zentriert
            monitor.setTextColor(colors.cyan)
            monitor.setCursorPos(math.floor(maxW/2 - 10), 1)
            monitor.write("FLUID TANK MONITORING")
            
            -- Trennlinie in der Mitte des Monitors zeichnen
            local middleX = math.floor(maxW / 2)
            monitor.setTextColor(colors.blue)
            for y = 2, maxH do
                monitor.setCursorPos(middleX, y)
                monitor.write("|")
            end
            
            -- Spaltenbreite berechnen
            local colWidth = middleX - 2
            
            -- Linken Tank auf der linken Seite anzeigen (Start bei X = 2)
            drawTankColumn(monitor, "=== LINKS ===", data.left, 2, colWidth)
            
            -- Rechten Tank auf der rechten Seite anzeigen (Start nach der Trennlinie)
            drawTankColumn(monitor, "=== RECHTS ===", data.right, middleX + 2, colWidth)
        end
    end
end

