local webhook = "REPLACE_WITH_DISCORD_WEBHOOK_URL"
local targetPlayers = { "Myth_Yck", "Rebornsuperior", "Kekdex" } 
local targetUsers = { "374444577756676097", "302706230328295424" }

local detector = peripheral.find("player_detector")
if not detector then error("Player Detector nicht gefunden") end

-- Hier speichern wir die letzte bekannte Position
local lastKnownData = {}

print("Gestartet. Überwache auf: " .. table.concat(targetPlayers, ", "))

while true do
    local msg = "**Player Tracking Update**\n"
    local foundTargets = {}
    local currentOnline = {}
    
    local players = detector.getOnlinePlayers()
    
    -- 1. Alle aktuellen Spieler verarbeiten
    if #players > 0 then
        for i = 1, #players do
            local name = players[i]
            currentOnline[name] = true
            
            -- Prüfen ob Ziel-Spieler
            local isTarget = false
            for _, t in ipairs(targetPlayers) do if name == t then isTarget = true end end
            
            if isTarget then
                local pos = detector.getPlayerPos(name)
                if pos then
                    -- WICHTIG: Position JETZT sofort speichern/aktualisieren
                    lastKnownData[name] = {
                        x = math.floor(pos.x + 0.5),
                        y = math.floor(pos.y + 0.5),
                        z = math.floor(pos.z + 0.5),
                        dim = pos.dimension or "Overworld"
                    }
                    table.insert(foundTargets, name)
                    msg = msg .. name .. " | X: " .. lastKnownData[name].x .. " Y: " .. lastKnownData[name].y .. " Z: " .. lastKnownData[name].z .. "\n"
                end
            end
        end
    else
        msg = msg .. "Keine Spieler online.\n"
    end

    -- 2. Logout prüfen (Vergleich: War gespeichert, ist jetzt NICHT mehr online)
    local logoutMsg = ""
    for name, data in pairs(lastKnownData) do
        -- Wenn der Spieler in unserer Tabelle ist, aber NICHT in der aktuellen Online-Liste
        if not currentOnline[name] then
            -- Prüfen ob es ein Target-Spieler war
            local isTarget = false
            for _, t in ipairs(targetPlayers) do if name == t then isTarget = true end end
            
            if isTarget then
                -- HIER nutzen wir die GESPEICHERTE Position aus 'data', nicht vom Detector!
                logoutMsg = logoutMsg .. "⚠️ **" .. name .. " hat sich ausgeloggt.**\n"
                logoutMsg = logoutMsg .. "   Letzte Position: X: " .. data.x .. " Y: " .. data.y .. " Z: " .. data.z .. " (" .. data.dim .. ")\n\n"
                
                -- Erst NACH der Nachricht löschen, damit die Daten für die Meldung erhalten bleiben
                lastKnownData[name] = nil 
            end
        end
    end

    if logoutMsg ~= "" then
        msg = logoutMsg .. msg
    end

    -- 3. Tagging bei Online-Status
    if #foundTargets > 0 then
        local tagString = ""
        for i = 1, #targetUsers do
            tagString = tagString .. "<@" .. targetUsers[i] .. "> "
        end
        local namesString = table.concat(foundTargets, ", ")
        msg = tagString .. "**" .. namesString .. " ist/sind online!**\n\n" .. msg
    end

    -- Nur senden wenn sich was geändert hat oder alle 10 Sekunden (wie vorher)
    local payload = { content = msg, username = "Player Tracker" }
    local json = textutils.serializeJSON(payload)
    
    local result = http.post(webhook, json, { ["Content-Type"] = "application/json" })
    if result then
        result.close()
        print("Update gesendet.")
    else
        print("Senden fehlgeschlagen.")
    end

    sleep(10)
end   
