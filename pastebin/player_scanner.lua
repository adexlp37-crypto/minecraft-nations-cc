math.randomseed(os.time())

-- === KONFIGURATION ===
local monitorName = "left"
local updateInterval = 0.01 -- Wie oft Google nach Updates gefragt wird
local modemSide = "top"   -- Wireless Modem oben

-- DEINE SCHANDLISTE (Trage hier die Spieler für die "sad people"-Box ein)
local sadPeople = {
    ["Tbnyeet"] = true,
    ["Lilia_Mer"] = true,
    -- Du kannst beliebig viele hinzufügen!
}

-- Deine Google Web-App URL
local googleAppUrl = "https://script.google.com/macros/s/AKfycbw9DD4BqpG0ruyu86A0wn5VwZ8zbofbI16fvZu1nhu2SZ4Vyg6TGIrh2UQy763e3H2l/exec"

-- === RGB & ANIMATION SYSTEM ===
local cachedPlayers = {} -- Hier werden die Live-Daten zwischengespeichert
local blinkState = true
local colorIndex = 1
local rainbowColors = {
    colors.red, colors.orange, colors.yellow, 
    colors.green, colors.blue, colors.purple, colors.magenta
}

-- === REDNET INITIALISIEREN ===
if peripheral.isPresent(modemSide) and peripheral.getType(modemSide) == "modem" then
    rednet.open(modemSide)
    print("Rednet aktiv auf Seite '" .. modemSide .. "'.")
else
    print("WARNUNG: Kein Modem auf '" .. modemSide .. "' gefunden!")
end

local monitor = peripheral.wrap(monitorName)
if monitor then monitor.setTextScale(1.0) end

-- === LOOP 1: DATEN AUS DEM INTERNET HOLEN (Hintergrund) ===
local function internetFetchLoop()
    local httpHeaders = {
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        ["Accept"] = "application/json"
    }
    
    while true do
        print("[" .. os.date("%X") .. "] Update von Google Cloud...")
        local cacheBuster = math.random(1, 100000)
        local finalUrl = googleAppUrl .. "?cb=" .. cacheBuster
        
        local httpSuccess, response = pcall(http.get, finalUrl, httpHeaders)
        if httpSuccess and response then
            local readSuccess, rawJson = pcall(response.readAll)
            response.close()
            
            if readSuccess and rawJson and rawJson ~= "" then
                local jsonSuccess, data = pcall(textutils.unserializeJSON, rawJson)
                if jsonSuccess and data and data.players then
                    -- Daten für den Monitor-Loop zwischenspeichern
                    cachedPlayers = data.players
                    
                    -- Funkspruch an die anderen Computer senden
                    if rednet.isOpen() then
                        rednet.broadcast(rawJson, "bluemap_alarm_system")
                    end
                end
            end
        else
            print("[WARNUNG] Google-Timeout. Nutze alte Daten weiter.")
        end
        os.sleep(updateInterval)
    end
end

-- === LOOP 2: ANIMATION UND MONITOR-RENDERING (Dauerfeuer) ===
local function monitorRenderLoop()
    if not monitor then 
        print("Fehler: Kein Monitor gefunden.") 
        return 
    end

    while true do
        -- Monitor komplett leeren und Hintergrund auf Schwarz setzen
        monitor.setBackgroundColor(colors.black)
        monitor.clear()
        
        -- Titel oben anzeigen
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, 1)
        monitor.write("=== BlueMap Player Tracker ===")
        
        local normalLine = 3
        local activeSadPeople = {}
        
        -- Spieler sortieren: Wer ist normal, wer ist "sad"?
        for _, player in ipairs(cachedPlayers) do
            if player.name and player.position then
                local x = math.floor(player.position.x + 0.5)
                local y = math.floor(player.position.y + 0.5)
                local z = math.floor(player.position.z + 0.5)
                local formattedText = string.format("%s: X:%d Y:%d Z:%d", player.name, x, y, z)
                
                if sadPeople[player.name] then
                    -- Sad Person erfassen
                    table.insert(activeSadPeople, formattedText)
                else
                    -- Normalen Spieler anzeigen
                    monitor.setTextColor(colors.lightGray)
                    monitor.setCursorPos(1, normalLine)
                    monitor.write(formattedText)
                    normalLine = normalLine + 1
                end
            end
        end
        
        -- Falls keine Spieler da sind
        if #cachedPlayers == 0 then
            monitor.setTextColor(colors.gray)
            monitor.setCursorPos(1, 3)
            monitor.write("Warte auf Daten/Keiner online...")
        end
        
        -- === DIE BLINKENDE "SAD PEOPLE" BOX (Unten am Monitor) ===
        if #activeSadPeople > 0 then
            local maxW, maxH = monitor.getSize()
            
            -- Berechne Box-Höhe dynamisch basierend auf Anzahl der "Goyim Slaves"
            local boxHeight = #activeSadPeople + 2
            local boxTop = maxH - boxHeight
            
            -- Kasten-Farbe toggeln (Blinken zwischen Rot und Dunkelgrau/Schwarz)
            local boxColor = blinkState and colors.red or colors.gray
            monitor.setTextColor(boxColor)
            
            -- 1. Obere Linie der Box zeichnen
            monitor.setCursorPos(1, boxTop)
            monitor.write("+" .. string.rep("-", maxW - 2) .. "+")
            
            -- 2. Inhalt und Seitenwände zeichnen
            for i, playerText in ipairs(activeSadPeople) do
                local currentY = boxTop + i
                
                -- Seitenwände (|) zeichnen
                monitor.setTextColor(boxColor)
                monitor.setCursorPos(1, currentY)
                monitor.write("|")
                monitor.setCursorPos(maxW, currentY)
                monitor.write("|")
                
                -- Farbwechsel-Effekt (Regenbogen) für den Namen berechnen
                local localColorIndex = ((colorIndex + i) % #rainbowColors) + 1
                monitor.setTextColor(rainbowColors[localColorIndex])
                
                -- Text eingerückt in die Box schreiben
                monitor.setCursorPos(3, currentY)
                monitor.write(playerText)
            end
            
            -- 3. Untere Linie der Box zeichnen
            monitor.setCursorPos(1, maxH - 1)
            monitor.setTextColor(boxColor)
            monitor.write("+" .. string.rep("-", maxW - 2) .. "+")
            
            -- 4. Text unter der Box: "sad people"
            monitor.setTextColor(colors.red)
            monitor.setCursorPos(2, maxH)
            monitor.write("Goyim Slaves")
        end
        
        -- Animations-Variablen für den nächsten Frame weiterschalten
        blinkState = not blinkState
        colorIndex = colorIndex + 1
        
        -- Animationsgeschwindigkeit (0.3 Sekunden pro Frame)
        os.sleep(0.3)
    end
end

-- === START ===
if not http then error("HTTP-Plugin deaktiviert!") end

-- Startet beide Funktionen GLEICHZEITIG, damit die Animation beim Laden nicht stoppt
parallel.waitForAny(internetFetchLoop, monitorRenderLoop)
