-- === KONFIGURATION ===
local modemSide = "top"          -- Wo sitzt das Wireless Modem an diesem PC?
local discordWebhookUrl = "REPLACE_WITH_DISCORD_WEBHOOK_URL"

-- === AUSSCHLUSSLISTE (Eure Gruppe wird ignoriert) ==
local baseMembers = {
    ["DeformedRac"] = true,
    ["ShayCass382"] = true,
    ["Kekdex"] = true,
    ["arseniymuromov"] = true
}

-- === BASE PARAMETER (Hier eure Koordinaten-Box eintragen!) ===
local base = {
    minX = 6800, maxX = 7500,
    minY = 50,   maxY = 120,
    minZ = -7000, maxZ = -6000
}

-- === INTERNER STATE ===
local intrudersInBase = {}

-- === REDNET INITIALISIEREN ===
if peripheral.isPresent(modemSide) and peripheral.getType(modemSide) == "modem" then
    rednet.open(modemSide)
    print("=== Base Guard aktiv ===")
    print("Scanne Funkdaten nach unbefugten Spielern...")
else
    error("FEHLER: Kein Modem auf Seite '" .. modemSide .. "' gefunden!")
end

-- === DISCORD WEBHOOK FUNKTION ===
local function sendDiscordNotification(message)
    local payload = textutils.serializeJSON({
        username = "GoySpotter9000",
        avatar_url = "https://imgs.search.brave.com/IwkDNGKGP7CVJq_1RzZaDWySV-7C6JpWx0KtR5FSgBk/rs:fit:500:0:0:0/g:ce/aHR0cHM6Ly91cGxv/YWQud2lraW1lZGlh/Lm9yZy93aWtpcGVk/aWEvZW4vMS8xZC9U/aGVfSGFwcHlfTWVy/Y2hhbnQuanBn",
        content = "ðŸš¨ **ALARM:** " .. message
    })
    
    local headers = {
        ["Content-Type"] = "application/json",
        ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
    }
    
    local success, response = pcall(http.post, discordWebhookUrl, payload, headers)
    if success and response then
        response.close()
    else
        print("[Discord] FEHLER: Webhook konnte nicht gesendet werden.")
    end
end

-- === MAIN LOOP ===
while true do
    -- Warte auf das Funksignal von Computer 1
    local senderId, message, protocol = rednet.receive("bluemap_alarm_system")
    
    if message then
        local jsonSuccess, data = pcall(textutils.unserializeJSON, message)
        
        if jsonSuccess and data and data.players then
            local currentIntruders = {}
            
            -- 1. Spielerliste scannen
            for _, player in ipairs(data.players) do
                if player.name and player.position then
                    
                    -- PrÃ¼fen: Ist es ein Fremder?
                    if not baseMembers[player.name] then
                        local x = math.floor(player.position.x + 0.5)
                        local y = math.floor(player.position.y + 0.5)
                        local z = math.floor(player.position.z + 0.5)
                        
                        -- Ist der Fremde in eurer Base-Box?
                        if x >= base.minX and x <= base.maxX and
                           y >= base.minY and y <= base.maxY and
                           z >= base.minZ and z <= base.maxZ then
                            
                            currentIntruders[player.name] = {x = x, y = y, z = z}
                        end
                    end
                end
            end
            
            -- 2. Wer ist NEU reingekommen?
            for name, pos in pairs(currentIntruders) do
                if not intrudersInBase[name] then
                    intrudersInBase[name] = true
                    local alertMsg = string.format("`%s` GOYIM ON PREMISE ALARM! (X: %d, Y: %d, Z: %d)", name, pos.x, pos.y, pos.z)
                    print("[ALARM] " .. alertMsg)
                    sendDiscordNotification(alertMsg)
                else
                    print(string.format("[!] %s ist noch in der Base (%d, %d, %d)", name, pos.x, pos.y, pos.z))
                end
            end
            
            -- 3. Wer ist GEGANGEN oder hat sich ausgeloggt?
            for name, _ in pairs(intrudersInBase) do
                if not currentIntruders[name] then
                    intrudersInBase[name] = nil
                    local leaveMsg = string.format("`%s` left the base again.", name)
                    print("[SAFE] " .. leaveMsg)
                    sendDiscordNotification(leaveMsg)
                end
            end
            
            if next(intrudersInBase) == nil then
                print("[.] Base is save.")
            end
        end
    end
end

