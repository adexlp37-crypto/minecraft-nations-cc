-- === KONFIGURATION ===
local apiKey = "REPLACE_WITH_GROQ_API_KEY" -- HIER DEINEN KEY EINFÜGEN
local monitorName = "left" -- Hier anpassen (z.B. "right", "top" oder "monitor_0")
local triggerWord = "ChatJewPT"
local botName = "ChatJewPT"
local modelName = "openai/gpt-oss-20b"
local url = "https://api.groq.com/openai/v1/chat/completions"

-- KONTEXT-SPEICHER (Gedächtnis & Persönlichkeit)
local conversationHistory = {
    { 
        role = "system", 
        content = "You are ChatJewPT and like israel. You are an asistance bot inside a minecraft nations war server and u try to help with realistic things"
    }
}

-- === PERIPHERALS SUCHEN ===
local speaker = peripheral.find("speaker")
if not speaker then
    print("Warning: Kein Speaker gefunden! Sprachausgabe & Klingelton deaktiviert.")
end

local monitor = peripheral.wrap(monitorName)
if not monitor then
    print("CRITICAL WARNING: Kein Monitor unter dem Namen '" .. monitorName .. "' gefunden!")
end

-- === SYSTEM VARIABLES ===
local currentScale = 1.0 -- Verhindert das unendliche Feuern von resize-Events


-- Coole, 2 Sekunden lange Klingel-Melodie
local function playCoolChime()
    if not speaker then return end
    local melody = {
        {inst = "bell", pitch = 12, delay = 0.2},
        {inst = "bell", pitch = 16, delay = 0.2},
        {inst = "chime", pitch = 19, delay = 0.2},
        {inst = "iron_xylophone", pitch = 24, delay = 0.4},
        {inst = "chime", pitch = 19, delay = 0.2},
        {inst = "bell", pitch = 24, delay = 0.1}
    }
    for _, note in ipairs(melody) do
        pcall(function() speaker.playNote(note.inst, 3, note.pitch) end)
        os.sleep(note.delay)
    end
end

-- Monitor scrollen
local function checkScroll()
    if not monitor then return end
    local w, h = monitor.getSize()
    local cx, cy = monitor.getCursorPos()
    if cy > h then
        monitor.scroll(1)
        monitor.setCursorPos(1, h)
    end
end

-- Text mit automatischem Zeilenumbruch
local function writeWrapped(text)
    if not monitor then return end
    local maxW, maxH = monitor.getSize()
    for word in text:gmatch("%S+") do
        local cx, cy = monitor.getCursorPos()
        if cx + #word > maxW then
            monitor.setCursorPos(1, cy + 1)
            checkScroll()
        end
        monitor.write(word .. " ")
    end
    local cx, cy = monitor.getCursorPos()
    monitor.setCursorPos(1, cy + 1)
    checkScroll()
end

-- Log Message (Terminal + Monitor)
local function logMessage(text)
    print(text)
    if monitor then
        writeWrapped(text)
    end
end

-- Text-to-Speech Audio abspielen
local function playAudioTTS(text)
    if not speaker then return end
    local encodedText = text:gsub("[^%w]", function(c) 
        return string.format("%%%02X", string.byte(c)) 
    end)
    local ttsUrl = "https://music.madebythecleaner.xyz/api/tts?text=" .. encodedText
    local response = http.get(ttsUrl, nil, true)
    if not response then return end
    
    local decoder = require("cc.audio.dfpwm").make_decoder()
    while true do
        local chunk = response.read(16 * 1024)
        if not chunk then break end
        local buffer = decoder(chunk)
        while not speaker.playAudio(buffer) do
            os.pullEvent("speaker_audio_empty")
        end
    end
    response.close()
end

-- API Request an Groq
local function askGroq(userPrompt)
    table.insert(conversationHistory, { role = "user", content = userPrompt })
    local postData = textutils.serializeJSON({
        model = modelName,
        messages = conversationHistory,
        temperature = 0.5,
        max_tokens = 150
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
        if success then
            if data.error then
                return "API Error: " .. data.error.message
            elseif data.choices and #data.choices > 0 then
                local aiResponse = data.choices[1].message.content
                table.insert(conversationHistory, { role = "assistant", content = aiResponse })
                if #conversationHistory > 12 then
                    table.remove(conversationHistory, 2)
                    table.remove(conversationHistory, 2)
                end
                return aiResponse
            else
                return "No response received."
            end
        else
            return "JSON Error: " .. rawResult
        end
    else
        return "Network Error: " .. tostring(err)
    end
end

-- Antwort verarbeiten
local function handleResponse(user, prompt)
    logMessage(user .. ": " .. prompt)
    local antwort = askGroq("Player " .. user .. " says: " .. prompt)
    logMessage(botName .. ": " .. antwort)
    
    pcall(playCoolChime)
    
    if chat then
        pcall(function() chat.sendMessage(botName .. ": " .. antwort) end)
    end
    pcall(function() playAudioTTS(antwort) end)
end

-- === THREADS ===

local function listenToChat()
    if not chat then
        while true do os.sleep(100) end
    end
    while true do
        local event, spieler, nachricht = os.pullEvent("chat")
        if string.find(nachricht, triggerWord) then
            local prompt = string.gsub(nachricht, triggerWord, "")
            handleResponse(spieler, prompt)
        end
    end
end

local function listenToTerminal()
    while true do
        write("Du: ")
        local input = read()
        if input and input ~= "" then
            handleResponse("Terminal-User", input)
        end
    end
end

local function listenForResize()
    while true do
        local event, side = os.pullEvent("monitor_resize")
        if side == monitorName then
            autoScaleMonitor()
        end
    end
end

-- === STARTUP ===

-- Monitor initialisieren
if monitor then
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

term.clear()
term.setCursorPos(1,1)
logMessage("Jarvis online.")
logMessage("Listening to chat ('" .. triggerWord .. "')")
logMessage("AND direct terminal input!")
logMessage("------------------------")

parallel.waitForAny(listenToChat, listenToTerminal, listenForResize)
