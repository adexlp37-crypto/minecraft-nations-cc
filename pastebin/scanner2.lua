math.randomseed(os.time())

-- === KONFIGURATION ===
local monitorName = "left"
local updateInterval = 0.1 -- Sicherer Intervall für Google (Sperren-Schutz)
local modemSide = "top"   -- Wireless Modem oben

-- DEINE SCHANDLISTE (Trage hier die Spieler für die "sad people"-Box ein)
local sadPeople = {
    ["Tbnyeet"] = true,
    ["Lilia_Mer"] = true,
}

-- Deine Google Web-App URL
local googleAppUrl = "https://script.google.com/macros/s/AKfycbw9DD4BqpG0ruyu86A0wn5VwZ8zbofbI16fvZu1nhu2SZ4Vyg6TGIrh2UQy763e3H2l/exec"

-- === RGB, ANIMATION & CLICK SYSTEM ===
local cachedPlayers = {}      -- Live-Daten Zwischenspeicher
local highlightedPlayers = {} -- Hier werden markierte (gepinnte) Spieler gespeichert
local playerClickMap = {}     -- Ordnet Zeilen (Y) den Spielernamen zu

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

-- === LOOP 1: DATEN AUS DEM INTERNET HOLEN ===
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
                    cachedPlayers = data.players
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
        local maxW, maxH = monitor.getSize()
        playerClickMap = {} -- Klick-Karte für diesen Frame zurücksetzen
        
        monitor.setBackgroundColor(colors.black)
        monitor.clear()
        
        -- Haupt-Titel ganz oben
        monitor.setTextColor(colors.white)
        monitor.setCursorPos(1, 1)
        monitor.write("=== BlueMap Player Tracker ===")
        
        -- Listen vorbereiten und vorsortieren
        local pinnedList = {}
        local normalList = {}
        local sadList = {}
        
        for _, player in ipairs(cachedPlayers) do
            if player.name and player.position then
                if highlightedPlayers[player.name] then
                    table.insert(pinnedList, player) -- Wandert in die Top-Sektion
                elseif sadPeople[player.name] then
                    table.insert(sadList, player)    -- Wandert in die untere Box
                else
                    table.insert(normalList, player) -- Normaler Spieler
                end
            end
        end
        
        local currentY = 3
        
        -- ======================================================
        -- 1. SEKTION: GEPINNTE SPIELER (Ganz oben mit Mega-Effekt)
        -- ======================================================
        if #pinnedList > 0 then
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(blinkState and colors.yellow or colors.orange)
            monitor.setCursorPos(1, currentY)
            monitor.write(">> 📌 HIGH PRIORITY TARGETS 📌 <<")
            currentY = currentY + 1
            
            for _, player in ipairs(pinnedList) do
                playerClickMap[currentY] = player.name -- Klick registrieren
                
                local x = math.floor(player.position.x + 0.5)
                local y = math.floor(player.position.y + 0.5)
                local z = math.floor(player.position.z + 0.5)
                
                -- Krasse Pfeil- und Farb-Animation generieren
                local prefix = blinkState and "==> " or "--> "
                local suffix = blinkState and " <==" or " <-- "
                local txtColor = blinkState and colors.white or colors.yellow
                
                monitor.setBackgroundColor(colors.purple) -- Auffälliger lila Balken
                monitor.setTextColor(txtColor)
                monitor.setCursorPos(1, currentY)
                
                local formattedText = string.format("%s%s: X:%d Y:%d Z:%d%s", prefix, player.name, x, y, z, suffix)
                -- Zeile komplett ausfüllen, damit der lila Balken durchgezogen ist
                monitor.write(formattedText .. string.rep(" ", maxW - #formattedText))
                
                currentY = currentY + 1
            end
            
            -- Kleine Trennlinie nach den gepinnten Leuten
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(colors.gray)
            monitor.setCursorPos(1, currentY)
            monitor.write(string.rep("-", maxW))
            currentY = currentY + 1
        end
        
        -- ======================================================
        -- 2. SEKTION: NORMALE ONLINE-SPIELER
        -- ======================================================
        monitor.setBackgroundColor(colors.black)
        for _, player in ipairs(normalList) do
            playerClickMap[currentY] = player.name -- Klick registrieren
            
            local x = math.floor(player.position.x + 0.5)
            local y = math.floor(player.position.y + 0.5)
            local z = math.floor(player.position.z + 0.5)
            local formattedText = string.format("%s: X:%d Y:%d Z:%d", player.name, x, y, z)
            
            monitor.setTextColor(colors.lightGray)
            monitor.setCursorPos(1, currentY)
            monitor.write(formattedText .. string.rep(" ", maxW - #formattedText))
            currentY = currentY + 1
        end
        
        -- Falls absolut niemand online ist
        if #cachedPlayers == 0 then
            monitor.setTextColor(colors.gray)
            monitor.setCursorPos(1, 3)
            monitor.write("Warte auf Daten/Keiner online...")
        end
        
        -- ======================================================
        -- 3. SEKTION: DIE "SAD PEOPLE" BOX (Unten am Monitor)
        -- ======================================================
        if #sadList > 0 then
            local boxHeight = #sadList + 2
            local boxTop = maxH - boxHeight
            
            local boxColor = blinkState and colors.red or colors.gray
            monitor.setTextColor(boxColor)
            monitor.setBackgroundColor(colors.black)
            
            -- Obere Box-Linie
            monitor.setCursorPos(1, boxTop)
            monitor.write("+" .. string.rep("-", maxW - 2) .. "+")
            
            -- Inhalt der Box zeichnen
            for i, player in ipairs(sadList) do
                local sadY = boxTop + i
                playerClickMap[sadY] = player.name -- Klick registrieren
                
                -- Seitenwände
                monitor.setTextColor(boxColor)
                monitor.setCursorPos(1, sadY)
                monitor.write("|")
                monitor.setCursorPos(maxW, sadY)
                monitor.write("|")
                
                local x = math.floor(player.position.x + 0.5)
                local y = math.floor(player.position.y + 0.5)
                local z = math.floor(player.position.z + 0.5)
                local formattedText = string.format("%s: X:%d Y:%d Z:%d", player.name, x, y, z)
                
                -- Regenbogeneffekt für die unmarkierten Sad-People
                local localColorIndex = ((colorIndex + i) % #rainbowColors) + 1
                monitor.setTextColor(rainbowColors[localColorIndex])
                monitor.setCursorPos(3, sadY)
                monitor.write(formattedText)
            end
            
            -- Untere Box-Linie
            monitor.setTextColor(boxColor)
            monitor.setCursorPos(1, maxH - 1)
            monitor.write("+" .. string.rep("-", maxW - 2) .. "+")
            
            -- Box-Tag ganz unten
            monitor.setTextColor(colors.red)
            monitor.setCursorPos(2, maxH)
            monitor.write("GoyimRadar")
        end
        
        -- Animations-Ticker weiterschalten
        blinkState = not blinkState
        colorIndex = colorIndex + 1
        
        os.sleep(0.3) -- Frame-Geschwindigkeit
    end
end

-- === LOOP 3: TOUCH-EINGABEN REGISTRIEREN ===
local function monitorTouchLoop()
    while true do
        local event, side, x, y = os.pullEvent("monitor_touch")
        
        if side == monitorName then
            local clickedPlayer = playerClickMap[y]
            
            if clickedPlayer then
                -- Wenn bereits gepinnt -> entpinnen, ansonsten anheften!
                if highlightedPlayers[clickedPlayer] then
                    highlightedPlayers[clickedPlayer] = nil
                else
                    highlightedPlayers[clickedPlayer] = true
                end
            end
        end
    end
end

-- === START ===
if not http then error("HTTP-Plugin deaktiviert!") end

-- Startet alle drei Prozesse absolut synchron
parallel.waitForAny(internetFetchLoop, monitorRenderLoop, monitorTouchLoop)
