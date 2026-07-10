local stressometer = peripheral.find("Create_Stressometer")
local monitor = peripheral.find("monitor")

if not monitor or not stressometer then
    error("Hardware fehlt! Check die Verbindung.")
end

-- Monitor perfekt einstellen: Größere Schrift für das Setup im Bild
monitor.setTextScale(2) 
monitor.setBackgroundColor(colors.gray) -- Dunkelgrauer Industrie-Look statt Schwarz

local function drawUI()
    local w, h = monitor.getSize()
    
    -- Daten holen
    local stress = stressometer.getStress() or 0
    local capacity = stressometer.getStressCapacity() or 1
    local percent = math.min((stress / capacity) * 100, 100)
    
    -- Monitor leeren & Hintergrund setzen
    monitor.setBackgroundColor(colors.gray)
    monitor.clear()
    
    -- 1. HEADER (Kompakt oben)
    monitor.setCursorPos(math.floor((w - 14) / 2) + 1, 2)
    monitor.setTextColor(colors.yellow)
    monitor.write("STRESS REPORT")
    
    -- 2. TEXT-INFOS (Mittig platziert)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(2, 4)
    monitor.write(string.format("SU: %d / %d", stress, capacity))
    
    -- Ampel-Farbe für Prozenttext & Balken bestimmen
    local barColor = colors.green
    if percent > 90 then
        barColor = colors.red
        monitor.setTextColor(colors.red)
    elseif percent > 75 then
        barColor = colors.orange
        monitor.setTextColor(colors.orange)
    else
        monitor.setTextColor(colors.lime)
    end
    
    monitor.setCursorPos(2, 5)
    monitor.write(string.format("LOAD: %.1f%%", percent))
    
    -- 3. DER FETTE GRAFIK-BALKEN (Unten)
    -- Hintergrund des Balkens (Helles Grau)
    local barY = 7
    local barWidth = w - 2
    
    monitor.setBackgroundColor(colors.lightGray)
    monitor.setCursorPos(2, barY)
    monitor.write(string.rep(" ", barWidth)) -- Leerer Balken
    
    -- Gefüllter Teil des Balkens (Farbig)
    local filledWidth = math.floor((percent / 100) * barWidth)
    if filledWidth > 0 then
        monitor.setBackgroundColor(barColor)
        monitor.setCursorPos(2, barY)
        monitor.write(string.rep(" ", filledWidth))
    end
end

-- Hauptschleife (Aktualisiert alle 0.5 Sekunden für direkte Reaktion)
while true do
    drawUI()
    sleep(0.5)
end
