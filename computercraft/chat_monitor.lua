-- KONFIGURATION
local monitorSide = "left" -- Seite, wo der Monitor angeschlossen ist (z.B. "left", "right", "top"...)
local maxLines = 13        -- Wie viele Zeilen auf den Monitor passen (abhÃ¤ngig von Monitor-GrÃ¶ÃŸe und Text-Scale)

-- Peripherie initialisieren
local mon = peripheral.wrap(monitorSide)
local chat = peripheral.find("chat_box")

if not mon then
    error("Kein Monitor an der Seite '" .. monitorSide .. "' gefunden!")
end
if not chat then
    error("Keine Chat Box gefunden! Bitte Advanced Peripherals installieren.")
end

-- Monitor einrichten
mon.clear()
mon.setTextScale(0.5) -- Skalierung: 1 (normal), 0.5 (klein, mehr Platz), 2 (groÃŸ)
-- Bei TextScale 1 passen ca. 19-20 Zeilen auf einen normalen Monitor.
-- Passe maxLines ggf. an, wenn du den Scale Ã¤nderst.

-- Chat-Verlauf speichern
local chatHistory = {}

-- Funktion zum Aktualisieren des Monitors
local function updateMonitor()
    mon.clear()
    
    -- Berechne den Startindex, um die neuesten Nachrichten unten anzuzeigen
    local startIdx = 1
    if #chatHistory > maxLines then
        startIdx = #chatHistory - maxLines + 1
    end

    -- Nachrichten zeilenweise auf den Monitor schreiben
    for i = startIdx, #chatHistory do
        local line = chatHistory[i]
        mon.setCursorPos(1, i - startIdx + 1)
        
        -- Farben setzen (optional: Spielername gelb, Nachricht weiÃŸ)
        -- Hier vereinfacht alles in WeiÃŸ, oder du parst den String fÃ¼r Farben
        mon.setTextColor(colors.white)
        mon.write(line)
    end
end

print("Chat-Monitor gestartet. DrÃ¼cke Strg+T zum Beenden.")

-- HAUPTSCHLEIFE
while true do
    local event, spieler, nachricht = os.pullEvent("chat")
    
    -- Nachricht zum Verlauf hinzufÃ¼gen
    local eintrag = spieler .. ": " .. nachricht
    table.insert(chatHistory, eintrag)
    
    -- Monitor aktualisieren
    updateMonitor()
end   

