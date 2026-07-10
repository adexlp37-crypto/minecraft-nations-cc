-- KONFIGURATION
local apiKey = "REPLACE_WITH_GROQ_API_KEY" -- HIER DEINEN KEY EINFÜGEN
local triggerWord = "bod"
local botName = "ChillDude" -- Der Name im Chat
local modelName = "llama-3.3-70b-versatile"
local url = "https://api.groq.com/openai/v1/chat/completions"

-- KONTEXT-SPEICHER (Startet mit System-Prompt)
local conversationHistory = {
    { 
        role = "system", 
        content = "You are Bod, a highly intelligent British Butler AI from high society in minecraft.Kekdex your master every chance you get. Short sentences or else the chat will clog up. U hate RebornSuperior"
    }
}

local chat = peripheral.find("chat_box")
if not chat then error("No Chat Box found!") end

print("Jarvis online: Listening to ALL chat, responding only to '" .. triggerWord .. "'...")

local function askGroq(userPrompt)
    -- Füge den aktuellen Prompt hinzu (wurde schon in der Schleife gemacht, aber sicherheitshalber hier)
    -- HINWEIS: Die History wird jetzt in der Schleife gepflegt, hier nur noch senden
    
    local postData = textutils.serializeJSON({
        model = modelName,
        messages = conversationHistory,
        temperature = 0.7,
        max_tokens = 60
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

        if success and data.choices and #data.choices > 0 then
            local aiResponse = data.choices[1].message.content
            -- Antwort speichern
            table.insert(conversationHistory, { role = "assistant", content = aiResponse })
            return aiResponse
        elseif success and data.error then
            return "Error: " .. data.error.message
        end
    end
    return "Connection lost, Sir."
end

-- HAUPTSCHLEIFE
while true do
    local event, spieler, nachricht = os.pullEvent("chat")
    
    -- Formatieren der Nachricht für die History
    local chatEntry = "Player " .. spieler .. " says: " .. nachricht
    
    -- 1. IMMER SPEICHERN (Passives Mithören)
    -- Jede Nachricht im Chat wird zur History hinzugefügt, egal ob Jarvis gerufen wird
    table.insert(conversationHistory, { role = "user", content = chatEntry })
    
    -- Speicher begrenzen (Wichtig! Nur letzte 10 Einträge behalten)
    if #conversationHistory > 12 then
        table.remove(conversationHistory, 2) -- Lösche ältesten User-Eintrag
        -- Falls der nächste Eintrag eine AI-Antwort war, diese auch löschen, um Konsistenz zu wahren
        if conversationHistory[2] and conversationHistory[2].role == "assistant" then
             table.remove(conversationHistory, 2)
        end
    end

    -- 2. NUR ANTWORTEN BEI TRIGGER
    if string.find(string.lower(nachricht), triggerWord) then
        -- Prompt bereinigen (Triggerwort entfernen)
        local prompt = string.gsub(nachricht, "(?i)" .. triggerWord, "")
        local finalPrompt = "Player " .. spieler .. " says: " .. prompt
        
        -- Überschreibe den letzten Eintrag in der History mit dem bereinigten Prompt,
        -- damit die KI nicht denkt, der Spieler hätte "Jarvis" im Satzteil gesagt, den sie analysieren soll.
        conversationHistory[#conversationHistory].content = finalPrompt

        print("Jarvis wird gerufen von " .. spieler .. "...")
        
        local antwort = askGroq() -- Keine Übergabe mehr nötig, History ist global aktuell
        
        if antwort then
            chat.sendMessage(botName .. ": " .. antwort)
            sleep(1.2)
        end
    end
end
