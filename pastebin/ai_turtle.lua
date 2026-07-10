-- ================= KONFIGURATION =================
local apiKey = "REPLACE_WITH_GROQ_API_KEY" -- HIER DEINEN KEY EINFÜGEN
local triggerWord = "tt"
local botName = "Jarvis"
local modelName = "llama-3.3-70b-versatile"
local url = "https://api.groq.com/openai/v1/chat/completions"
local AUTO_REFUEL_INTERVAL = 60 -- Sekunden

-- ================= SYSTEM PROMPT =================
local systemPrompt = [[
You are Jarvis, an AI controlling a Minecraft Turtle (CC: Tweaked).
Output ONLY valid, complete Lua code. NO markdown, NO explanations, NO text outside code.
CRITICAL RULES:
1. Turtle functions take NO arguments. NEVER write turtle.up(1). Use loops: 'for i=1,3 do turtle.up() end'.
2. ALWAYS close loops with 'end'.
3. COMMUNICATION: After EVERY movement command, add 'chat.sendMessage("Status...")'.
4. PLAYER DETECTION: To follow, use 'turtle.inspect()'. If 'data.type == "player"', stop. If not, turn right and check again.
5. Available functions: turtle.forward(), turtle.back(), turtle.up(), turtle.down(), turtle.turnLeft(), turtle.turnRight(), turtle.dig(), turtle.digUp(), turtle.digDown(), turtle.place(), turtle.select(slot), turtle.refuel(count), turtle.inspect(), chat.sendMessage("text").
Example User: "Go up 3 blocks"
Example You: for i=1,3 do turtle.up(); chat.sendMessage("Moving up...") end
Example User: "Follow me"
Example You: while true do if turtle.inspect() then local d={turtle.inspect()}; if d[2] and d[2].type=="player" then chat.sendMessage("Found you!"); break end end turtle.turnRight(); chat.sendMessage("Scanning..."); os.sleep(0.2) end
]]

-- ================= INITIALISIERUNG =================
local chat = peripheral.find("chat_box")

if not chat then
    error("KRITISCHER FEHLER: Keine Chat Box gefunden! Bitte baue eine Chat Box neben die Turtle.")
end

-- Globale Chat-Funktion für den generierten Code
local function sendChat(msg)
    if chat then
        chat.sendMessage(botName .. ": " .. msg)
    end
end

print("Jarvis Online. Warte auf '" .. triggerWord .. "'...")

-- ================= AUTO REFUEL =================
local function autoRefuel()
    local fuelLevel = turtle.getFuelLevel()
    if fuelLevel == "unlimited" then return end
    
    local fuelLimit = turtle.getFuelLimit() or 20000
    
    if fuelLevel < fuelLimit * 0.8 then
        for i = 1, 16 do
            turtle.select(i)
            if turtle.refuel(0) then
                turtle.refuel()
                sendChat("Betankt. Level: " .. turtle.getFuelLevel())
                return
            end
        end
        sendChat("Warnung: Kein Brennstoff im Inventar!")
    end
end

-- ================= GROQ API =================
local conversationHistory = {
    { role = "system", content = systemPrompt }
}

local function askGroq(task)
    table.insert(conversationHistory, { role = "user", content = task })

    local postData = textutils.serializeJSON({
        model = modelName,
        messages = conversationHistory,
        temperature = 0.1,
        max_tokens = 350
    })

    local headers = {
        ["Authorization"] = "Bearer " .. apiKey,
        ["Content-Type"] = "application/json"
    }

    local response, err = http.post(url, postData, headers)
    
    if response then
        local rawResult = response.readAll()
        response.close()
        local success, data = pcall(textutils.unserializeJSON, rawResult)
        
        if success and data and data.choices and #data.choices > 0 then
            local code = data.choices[1].message.content
            table.insert(conversationHistory, { role = "assistant", content = code })
            return code
        end
    else
        sendChat("Netzwerkfehler: " .. tostring(err))
    end
    return nil
end

-- ================= CODE AUSFÜHRUNG =================
local function cleanCode(str)
    if not str then return "" end
    str = str:gsub("```lua", "\n"):gsub("```", "\n"):gsub("```text", "\n")
    return str:match("^%s*(.-)%s*$")
end

local function executeCode(codeString)
    local clean = cleanCode(codeString)
    if clean == "" then
        sendChat("Kein Code erhalten.")
        return
    end

    print("Führe aus:\n" .. clean)

    -- Sichere Umgebung mit allen nötigen Funktionen
    local env = {
        turtle = turtle,
        chat = { sendMessage = sendChat },
        os = { sleep = os.sleep, time = os.time },
        select = select,
        pairs = pairs,
        ipairs = ipairs,
        tonumber = tonumber,
        string = string,
        table = table,
        print = print,
        error = error
    }

    local func, err = load(clean, "JarvisCode", "t", env)
    
    if func then
        local success, runErr = pcall(func)
        if success then
            -- Erfolg wird oft schon im Code gemeldet
        else
            sendChat("Laufzeitfehler: " .. tostring(runErr))
        end
    else
        sendChat("Syntaxfehler: " .. tostring(err))
    end
end

-- ================= HAUPTSCHLEIFE =================
local lastRefuelTime = os.time()

while true do
    -- 1. Timer prüfen (alle 60 Sek tanken)
    if os.time() - lastRefuelTime >= AUTO_REFUEL_INTERVAL then
        autoRefuel()
        lastRefuelTime = os.time()
    end

    -- 2. Auf Chat warten (Timeout 1 Sekunde)
    local event, spieler, nachricht = os.pullEvent("chat", 1)
    
    if event == "chat" then
        if string.find(nachricht, triggerWord) then
            local task = string.gsub(nachricht, triggerWord, "")
            local finalPrompt = "Player " .. spieler .. " commands: " .. task
            
            print("Befehl von " .. spieler .. ": " .. task)
            sendChat("Verarbeite...")
            
            local code = askGroq(finalPrompt)
            if code then
                executeCode(code)
            end
        end
    end
end   
